import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/detection_result.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

/// Each screen owns a service and closes it on disposal. A timeout covers the
/// upload AND response body; closing the request client aborts pending I/O.
class ApiService {
  ApiService({
    this.baseUrl = ApiConfig.baseUrl,
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 60),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String baseUrl;
  final Duration requestTimeout;
  final http.Client Function() _clientFactory;
  final Set<http.Client> _clients = {};
  final Completer<void> _closed = Completer<void>();

  void close() {
    if (_closed.isCompleted) return;
    _closed.complete();
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }

  Uri _endpoint(List<String> path) {
    try {
      return ApiConfig.endpoint(baseUrl, path);
    } on FormatException catch (error) {
      throw ApiException(error.message);
    }
  }

  String getVideoUrl(String jobId) =>
      _endpoint(['video', _jobId(jobId)]).toString();

  static String _jobId(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(value)) {
      throw const ApiException('The service returned an invalid video job ID.');
    }
    return value;
  }

  Future<Map<String, dynamic>> _send(
    http.BaseRequest request, {
    Duration? timeout,
  }) async {
    if (_closed.isCompleted) throw const ApiException('Analysis cancelled.');
    request.headers.addAll(ApiConfig.headers);
    final client = _clientFactory();
    _clients.add(client);
    try {
      return await Future.any([
        (() async {
          final response = await client.send(request);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw ApiException(
              response.statusCode == 404
                  ? 'The video job or API endpoint is no longer available.'
                  : 'Analysis service request failed (HTTP ${response.statusCode}).',
              retryable:
                  response.statusCode >= 500 ||
                  response.statusCode == 408 ||
                  response.statusCode == 429,
            );
          }
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in response.stream) {
            if (bytes.length + chunk.length > 40 * 1024 * 1024) {
              throw const ApiException('The service response is too large.');
            }
            bytes.add(chunk);
          }
          final body = jsonDecode(utf8.decode(bytes.takeBytes()));
          if (body is! Map<String, dynamic>) {
            throw const FormatException('Expected a JSON object');
          }
          return body;
        })().timeout(timeout ?? requestTimeout),
        _closed.future.then<Map<String, dynamic>>(
          (_) => throw const ApiException('Analysis cancelled.'),
        ),
      ]);
    } on TimeoutException {
      throw const ApiException(
        'The service timed out. Please try again.',
        retryable: true,
      );
    } on FormatException {
      throw const ApiException('The service returned an invalid response.');
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the analysis service. Check your connection.',
        retryable: true,
      );
    } finally {
      _clients.remove(client);
      client.close();
    }
  }

  Future<bool> checkHealth() async {
    try {
      await _send(
        http.Request('GET', _endpoint(['health'])),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<DetectionResult> detectImageFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    if (bytes.isEmpty || bytes.length > ApiConfig.maxImageBytes) {
      throw const ApiException('Choose an image smaller than 20 MB.');
    }
    final extension = fileName.split('.').last.toLowerCase();
    final subtype = {'jpg': 'jpeg', 'jpeg': 'jpeg', 'png': 'png'}[extension];
    if (subtype == null) throw const ApiException('Choose a JPG or PNG image.');
    final request = http.MultipartRequest(
        'POST',
        _endpoint(['detect', 'image']),
      )
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType('image', subtype),
        ),
      );
    try {
      return DetectionResult.fromJson(await _send(request));
    } on FormatException {
      throw const ApiException('The service returned invalid image results.');
    }
  }

  Future<String> submitVideoJob(
    Uint8List? bytes,
    String fileName, {
    String? path,
  }) async {
    final subtype =
        {
          'mp4': 'mp4',
          'mov': 'quicktime',
          'avi': 'x-msvideo',
          'mkv': 'x-matroska',
        }[fileName.split('.').last.toLowerCase()];
    if (subtype == null) {
      throw const ApiException('Choose an MP4, MOV, AVI or MKV video.');
    }
    if (path == null && bytes == null) {
      throw const ApiException('Select a video first.');
    }
    final file =
        path != null
            ? await http.MultipartFile.fromPath(
              'file',
              path,
              filename: fileName,
              contentType: MediaType('video', subtype),
            )
            : http.MultipartFile.fromBytes(
              'file',
              bytes!,
              filename: fileName,
              contentType: MediaType('video', subtype),
            );
    if (file.length == 0 || file.length > ApiConfig.maxVideoBytes) {
      throw const ApiException('Choose a video smaller than 250 MB.');
    }
    final request = http.MultipartRequest(
      'POST',
      _endpoint(['detect', 'video']),
    )..files.add(file);
    // Never automatically retry uploads: a timed-out POST may have created a job.
    final data = await _send(request, timeout: const Duration(minutes: 3));
    final id = data['job_id'];
    if (id is! String) {
      throw const ApiException('The service did not return a video job ID.');
    }
    return _jobId(id);
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) => _send(
    http.Request('GET', _endpoint(['job', _jobId(jobId)])),
    timeout: const Duration(seconds: 10),
  );

  Future<Map<String, dynamic>> waitForVideoJob(
    String jobId, {
    required void Function(Map<String, dynamic>) onProgress,
    Duration timeout = const Duration(minutes: 30),
    Duration pollInterval = const Duration(seconds: 5),
    int maxFailures = 5,
  }) async {
    final clock = Stopwatch()..start();
    var failures = 0;
    Timer? delay;
    try {
      while (!_closed.isCompleted && clock.elapsed < timeout) {
        try {
          final status = await getJobStatus(
            jobId,
          ).timeout(timeout - clock.elapsed);
          if (_closed.isCompleted) {
            throw const ApiException('Analysis cancelled.');
          }
          final state = status['status'];
          if (state == 'error' || state == 'failed') {
            throw const ApiException(
              'Video processing failed. Try a different video or check the service.',
            );
          }
          if (!const [
            'queued',
            'pending',
            'processing',
            'completed',
          ].contains(state)) {
            throw const ApiException(
              'The service returned an unknown job state.',
            );
          }
          if (state == 'completed' &&
              (status['violations_found'] is! bool ||
                  status['total_violations'] is! num ||
                  !(status['total_violations'] as num).isFinite ||
                  (status['total_violations'] as num) < 0)) {
            throw const ApiException(
              'The service returned an incomplete video violation summary.',
            );
          }
          failures = 0;
          onProgress(status);
          if (state == 'completed') return status;
        } on ApiException catch (error) {
          if (!error.retryable || ++failures >= maxFailures) rethrow;
          onProgress({
            'status': 'processing',
            'message': 'Connection interrupted. Retrying status check…',
          });
        }
        final ready = Completer<void>();
        final remaining = timeout - clock.elapsed;
        if (remaining <= Duration.zero) break;
        delay = Timer(
          remaining < pollInterval ? remaining : pollInterval,
          ready.complete,
        );
        await Future.any([ready.future, _closed.future]);
        delay.cancel();
      }
    } on TimeoutException {
      throw const ApiException(
        'Video processing timed out. The server job may still be running.',
      );
    } finally {
      delay?.cancel();
      clock.stop();
    }
    throw ApiException(
      _closed.isCompleted
          ? 'Analysis cancelled.'
          : 'Video processing timed out. The server job may still be running.',
    );
  }
}
