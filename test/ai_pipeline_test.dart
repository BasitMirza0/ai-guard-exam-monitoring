import 'dart:async';
import 'package:aicheat/services/ai_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CameraImage frame() {
  // Exercise the public camera event decoder with real NV21 plane bytes.
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': 17,
    'width': 640,
    'height': 480,
    'planes': [
      {
        'bytes': Uint8List(640 * 480 * 3 ~/ 2),
        'bytesPerRow': 640,
        'bytesPerPixel': 1,
        'width': 640,
        'height': 480,
      },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  List<Map<String, dynamic>> labels = [];
  List<Map<String, dynamic>> faces = [];
  bool objectDetectorFails = false;
  Completer<List<dynamic>>? pendingFace;
  setUp(() {
    calls.clear();
    labels = [];
    faces = [];
    objectDetectorFails = false;
    pendingFace = null;
    for (final channel in [
      'google_mlkit_face_detector',
      'google_mlkit_face_mesh_detector',
      'google_mlkit_image_labeler',
      'google_mlkit_object_detector',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add(call.method);
        if (call.method == 'vision#startFaceDetector' && pendingFace != null) {
          return pendingFace!.future;
        }
        if (call.method == 'vision#startImageLabelDetector') {
          return labels;
        }
        if (call.method == 'vision#startFaceDetector') return faces;
        if (call.method == 'vision#startObjectDetector' &&
            objectDetectorFails) {
          throw PlatformException(code: 'detector-unavailable');
        }
        return call.method.contains('close') ? null : [];
      });
    }
  });
  tearDown(() {
    for (final channel in [
      'google_mlkit_face_detector',
      'google_mlkit_face_mesh_detector',
      'google_mlkit_image_labeler',
      'google_mlkit_object_detector',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });

  test(
    'Native inference completes before detectors close and late callbacks are suppressed',
    () async {
      final ai = AiHandler.session();
      await ai.initModel();
      pendingFace = Completer<List<dynamic>>();
      var results = 0;
      ai.onResult = () => results++;
      final inference = ai.runInferenceMobile(frame());
      await Future<void>.delayed(Duration.zero);
      final close = ai.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.contains('close')), isEmpty);
      pendingFace!.complete([]);
      await inference;
      await close;
      expect(calls.where((call) => call.contains('close')), hasLength(4));
      expect(results, 0);
    },
  );

  test(
    'No device candidates avoids unnecessary native object detection',
    () async {
      final ai = AiHandler.session();
      await ai.initModel();
      await ai.runInferenceMobile(frame());
      expect(calls, contains('vision#startFaceDetector'));
      expect(calls, contains('vision#startImageLabelDetector'));
      expect(calls, isNot(contains('vision#startObjectDetector')));
      expect(ai.detectedObjects, isEmpty);
      await ai.dispose();
    },
  );

  test(
    'Stable phone candidates still run object detection and retain fallback violation boxes',
    () async {
      labels = [
        {'text': 'Mobile phone', 'confidence': 0.95, 'index': 0},
      ];
      final ai = AiHandler.session();
      await ai.initModel();
      await ai.runInferenceMobile(frame());
      await ai.runInferenceMobile(frame());
      expect(calls, contains('vision#startObjectDetector'));
      expect(
        ai.detectedObjects.any(
          (object) => object.label == 'Phone' && object.isViolation,
        ),
        isTrue,
      );
      await ai.dispose();
    },
  );

  test('Room and desk labels must not erase strong phone evidence', () async {
    labels = [
      {'text': 'Mobile phone', 'confidence': 0.95, 'index': 257},
      {'text': 'Room', 'confidence': 0.9, 'index': 289},
      {'text': 'Desk', 'confidence': 0.9, 'index': 115},
    ];
    final ai = AiHandler.session();
    addTearDown(ai.dispose);
    await ai.initModel();
    await ai.runInferenceMobile(frame());
    await ai.runInferenceMobile(frame());
    expect(ai.detectedObjects.any((d) => d.label == 'Phone'), isTrue);
  });

  test(
    'A stronger label for another object does not override a phone',
    () async {
      labels = [
        {'text': 'Mobile phone', 'confidence': 0.8, 'index': 257},
        {'text': 'Television', 'confidence': 0.99, 'index': 310},
        {'text': 'Book', 'confidence': 0.95, 'index': 0},
      ];
      final ai = AiHandler.session();
      addTearDown(ai.dispose);
      await ai.initModel();
      await ai.runInferenceMobile(frame());
      await ai.runInferenceMobile(frame());
      expect(ai.detectedObjects.any((d) => d.label == 'Phone'), isTrue);
    },
  );

  test(
    'Multiple faces cannot establish a single-student calibration',
    () async {
      final face = {
        'rect': {'left': 100.0, 'top': 80.0, 'right': 220.0, 'bottom': 240.0},
        'headEulerAngleX': 0.0,
        'headEulerAngleY': 0.0,
        'landmarks': <String, dynamic>{},
      };
      faces = [face, face];
      final ai = AiHandler.session();
      addTearDown(ai.dispose);
      await ai.initModel();
      for (var i = 0; i < 20; i++) {
        await ai.runInferenceMobile(frame());
      }
      expect(ai.isCalibrated, isFalse);
      expect(ai.calibProgress, 0);
    },
  );

  test('Head calibration still publishes confirmed phone detections', () async {
    labels = [
      {'text': 'Mobile phone', 'confidence': 0.9, 'index': 257},
    ];
    faces = [
      {
        'rect': {'left': 100.0, 'top': 80.0, 'right': 220.0, 'bottom': 240.0},
        'headEulerAngleX': 0.0,
        'headEulerAngleY': 0.0,
        'landmarks': <String, dynamic>{},
      },
    ];
    final ai = AiHandler.session();
    addTearDown(ai.dispose);
    await ai.initModel();
    await ai.runInferenceMobile(frame());
    await ai.runInferenceMobile(frame());
    expect(ai.calibProgress, greaterThan(0));
    expect(ai.isCalibrated, isFalse);
    expect(ai.detectedObjects.any((d) => d.label == 'Phone'), isTrue);
    expect(ai.isViolationDetected, isTrue);
  });

  test(
    'Bounding-box failure does not discard a confirmed phone label',
    () async {
      labels = [
        {'text': 'Mobile phone', 'confidence': 0.9, 'index': 257},
      ];
      objectDetectorFails = true;
      final ai = AiHandler.session();
      addTearDown(ai.dispose);
      var results = 0;
      ai.onResult = () => results++;
      await ai.initModel();
      await ai.runInferenceMobile(frame());
      await ai.runInferenceMobile(frame());
      expect(results, 2);
      expect(ai.detectedObjects.any((d) => d.label == 'Phone'), isTrue);
    },
  );

  test(
    'Weak phone evidence and a single positive frame do not trigger',
    () async {
      final ai = AiHandler.session();
      addTearDown(ai.dispose);
      await ai.initModel();
      labels = [
        {'text': 'Mobile phone', 'confidence': 0.4, 'index': 257},
      ];
      await ai.runInferenceMobile(frame());
      await ai.runInferenceMobile(frame());
      expect(ai.detectedObjects, isEmpty);
      labels = [
        {'text': 'Mobile phone', 'confidence': 0.9, 'index': 257},
      ];
      await ai.runInferenceMobile(frame());
      expect(ai.detectedObjects, isEmpty);
      labels = [];
      await ai.runInferenceMobile(frame());
      labels = [
        {'text': 'Mobile phone', 'confidence': 0.9, 'index': 257},
      ];
      await ai.runInferenceMobile(frame());
      expect(ai.detectedObjects, isEmpty);
    },
  );
}
