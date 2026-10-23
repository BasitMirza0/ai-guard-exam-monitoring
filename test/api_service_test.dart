import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:aicheat/config/api_config.dart';
import 'package:aicheat/models/detection_result.dart';
import 'package:aicheat/services/api_service.dart';
import 'package:aicheat/services/media_response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const imageResult = {
  'violations_found': false,
  'violations': <dynamic>[],
  'total_detections': 1,
  'total_violations': 0,
  'detections': [
    {'class_name': 'person_normal', 'confidence': 0.8},
  ],
};

void main() {
  ApiService service(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 1),
  }) {
    final api = ApiService(
      baseUrl: 'https://example.com/api/',
      clientFactory: () => MockClient(handler),
      requestTimeout: timeout,
    );
    addTearDown(api.close);
    return api;
  }

  test(
    'Endpoint configuration normalizes slashes and retains deployment prefix',
    () {
      expect(
        ApiConfig.endpoint('https://example.com/api/', ['health']).toString(),
        'https://example.com/api/health',
      );
    },
  );
  for (final base in [
    '',
    'ftp://example.com',
    'https://user:pass@example.com',
    'https://example.com?token=secret',
    'https://example.com#fragment',
  ]) {
    test(
      'Reject malformed or credential-bearing endpoint: ${base.split(':').first}',
      () {
        expect(
          () => ApiConfig.endpoint(base, ['health']),
          throwsFormatException,
        );
      },
    );
  }
  test('Health checks expected path and accepts JSON object', () async {
    final api = service((request) async {
      expect(request.url.path, '/api/health');
      expect(request.headers['ngrok-skip-browser-warning'], 'true');
      return http.Response('{"status":"ok"}', 200);
    });
    expect(await api.checkHealth(), isTrue);
  });
  test('Malformed health body is not reported as an online API', () async {
    final api = service(
      (_) async => http.Response('<html>tunnel offline</html>', 200),
    );
    expect(await api.checkHealth(), isFalse);
  });
  test(
    'Image upload is multipart with correct field and MIME; preserves raw detections',
    () async {
      final api = service((request) async {
        expect(request.url.path, '/api/detect/image');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(request.body, contains('name="file"; filename="photo.png"'));
        expect(request.body, contains('image/png'));
        return http.Response(jsonEncode(imageResult), 200);
      });
      final result = await api.detectImageFromBytes(
        Uint8List.fromList([1, 2]),
        'photo.png',
      );
      expect(result.detections, hasLength(1));
      expect(result.violations, isEmpty);
    },
  );
  test('Invalid response does not become an all-clear result', () async {
    final api = service((_) async => http.Response('{}', 200));
    await expectLater(
      api.detectImageFromBytes(Uint8List(1), 'image.jpg'),
      throwsA(isA<ApiException>()),
    );
  });
  test('Image limits and unsupported format fail before upload', () async {
    var sent = 0;
    final api = service((_) async {
      sent++;
      return http.Response('{}', 200);
    });
    await expectLater(
      api.detectImageFromBytes(Uint8List(0), 'image.jpg'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.detectImageFromBytes(Uint8List(1), 'image.heic'),
      throwsA(isA<ApiException>()),
    );
    expect(sent, 0);
  });
  test('Video accepts HTTP 202 and validates returned job ID', () async {
    final api = service((request) async {
      expect(request.url.path, '/api/detect/video');
      return http.Response('{"job_id":"job_123-abc"}', 202);
    });
    final id = await api.submitVideoJob(Uint8List(1), 'video.mp4');
    expect(api.getVideoUrl(id), 'https://example.com/api/video/job_123-abc');
  });
  for (final body in [
    '{}',
    '{"job_id":null}',
    '{"job_id":""}',
    '{"job_id":"../private"}',
  ]) {
    test('Missing or unsafe job ID is rejected: $body', () async {
      final api = service((_) async => http.Response(body, 200));
      await expectLater(
        api.submitVideoJob(Uint8List(1), 'video.mp4'),
        throwsA(isA<ApiException>()),
      );
    });
  }
  test(
    'Polling reports progress then completes without another request',
    () async {
      var calls = 0;
      final api = service(
        (_) async => http.Response(
          jsonEncode(
            ++calls == 1
                ? {
                  'status': 'processing',
                  'progress': 35,
                  'message': 'Frame 1500 / 4303',
                }
                : {
                  'status': 'completed',
                  'violations_found': false,
                  'total_violations': 0,
                },
          ),
          200,
        ),
      );
      final updates = <Map<String, dynamic>>[];
      final result = await api.waitForVideoJob(
        'abc',
        onProgress: updates.add,
        pollInterval: Duration.zero,
      );
      expect(result['status'], 'completed');
      expect(updates.first['progress'], 35);
      expect(calls, 2);
    },
  );
  test(
    'Temporary GET failures retry with a limit, uploads do not retry',
    () async {
      var calls = 0;
      final api = service((_) async {
        calls++;
        return http.Response('offline', 503);
      });
      await expectLater(
        api.waitForVideoJob(
          'abc',
          onProgress: (_) {},
          pollInterval: Duration.zero,
          maxFailures: 3,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 3);
      calls = 0;
      await expectLater(
        api.submitVideoJob(Uint8List(1), 'video.mp4'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    },
  );
  test('Unknown job fails immediately without retrying 404', () async {
    var calls = 0;
    final api = service((_) async {
      calls++;
      return http.Response('{}', 404);
    });
    await expectLater(
      api.waitForVideoJob('abc', onProgress: (_) {}),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });
  for (final state in ['error', 'failed', 'unexpected']) {
    test('Terminal or unknown state $state stops polling', () async {
      final api = service(
        (_) async => http.Response(jsonEncode({'status': state}), 200),
      );
      await expectLater(
        api.waitForVideoJob('abc', onProgress: (_) {}),
        throwsA(isA<ApiException>()),
      );
    });
  }
  test('Polling has a wall-clock deadline', () async {
    final api = service(
      (_) async => http.Response('{"status":"processing"}', 200),
    );
    await expectLater(
      api.waitForVideoJob(
        'abc',
        onProgress: (_) {},
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'Closing the service cancels a long poll delay and prevents later requests',
    () async {
      var calls = 0;
      final api = service((_) async {
        calls++;
        return http.Response('{"status":"processing"}', 200);
      });
      final future = api.waitForVideoJob('abc', onProgress: (_) => api.close());
      await expectLater(future, throwsA(isA<ApiException>()));
      expect(calls, 1);
      await expectLater(api.getJobStatus('abc'), throwsA(isA<ApiException>()));
      expect(calls, 1);
    },
  );
  test('Response-body stalls time out and close the HTTP client', () async {
    final stream = StreamController<List<int>>();
    final client = _StalledClient(stream.stream);
    final api = ApiService(
      baseUrl: 'https://example.com',
      clientFactory: () => client,
      requestTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(api.close);
    await expectLater(
      api.detectImageFromBytes(Uint8List(1), 'a.jpg'),
      throwsA(isA<ApiException>()),
    );
    expect(client.closed, isTrue);
    await stream.close();
  });
  test(
    'Annotated images accept plain base64 and data URI and reject bad input',
    () {
      expect(decodeAnnotatedImage('AQI='), [1, 2]);
      expect(decodeAnnotatedImage('data:image/jpeg;base64,AQI='), [1, 2]);
      expect(
        () => decodeAnnotatedImage('data:image/jpeg,invalid'),
        throwsFormatException,
      );
      expect(() => decodeAnnotatedImage('%%%'), throwsFormatException);
    },
  );
  test('Accepted violations and raw detections remain separate', () {
    final result = DetectionResult.fromJson({
      ...imageResult,
      'detections': [
        {'class_name': 'peeking_around', 'confidence': 0.47},
      ],
    });
    expect(result.violationsFound, isFalse);
    expect(result.violations, isEmpty);
    expect(result.detections.single['confidence'], 0.47);
    expect(
      () =>
          DetectionResult.fromJson({...imageResult, 'violations_found': true}),
      throwsFormatException,
    );
  });
  test('Invalid confidence is rejected', () {
    expect(
      () =>
          Violation.fromJson({'violation': 'book_visible', 'confidence': 1.5}),
      throwsFormatException,
    );
  });
}

class _StalledClient extends http.BaseClient {
  _StalledClient(this.stream);
  final Stream<List<int>> stream;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(stream, 200);
  @override
  void close() {
    closed = true;
  }
}
