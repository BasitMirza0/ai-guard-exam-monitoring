import 'package:aicheat/services/ai_handler.dart';
import 'package:aicheat/services/camera_frame_encoder.dart';
import 'package:aicheat/services/camera_platform.dart';
import 'package:aicheat/widgets/exam_instructions.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

CameraImage cameraFrame(
  int format,
  int width,
  int height,
  List<Map<String, dynamic>> planes,
) {
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': format,
    'width': width,
    'height': height,
    'planes': planes,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channels = [
    'google_mlkit_face_detector',
    'google_mlkit_face_mesh_detector',
    'google_mlkit_image_labeler',
    'google_mlkit_object_detector',
  ];
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add(call);
        return call.method.contains('close') ? null : [];
      });
    }
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });

  test(
    'iOS sends BGRA with row padding and actual dimensions; never calls mesh',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(examCameraFormat, ImageFormatGroup.bgra8888);
      expect(liveCameraFormat, ImageFormatGroup.bgra8888);
      final ai = AiHandler.session();
      expect(ai.supportsFaceMesh, isFalse);
      expect(
        ai.monitoringNotice,
        contains('eye-only gaze tracking are unavailable'),
      );
      ai.setCameraRotation(90, true);
      await ai.initModel();
      final bytes = Uint8List(32);
      await ai.runInferenceMobile(
        cameraFrame(1111970369, 2, 2, [
          {'bytes': bytes, 'bytesPerRow': 16, 'bytesPerPixel': 4},
        ]),
      );
      final input = (calls.first.arguments as Map)['imageData'] as Map;
      expect(input['bytes'], orderedEquals(bytes));
      expect(input['metadata'], containsPair('image_format', 1111970369));
      expect(input['metadata'], containsPair('bytes_per_row', 16));
      expect(input['metadata'], containsPair('rotation', 0));
      expect(input['metadata'], containsPair('width', 2.0));
      expect(ai.irisGazeState.isAvailable, isFalse);
      await ai.dispose();
      expect(calls.any((call) => call.method.contains('FaceMesh')), isFalse);
      expect(
        calls.where((call) => call.method.contains('close')),
        hasLength(3),
      );
    },
  );

  test(
    'Android single-plane NV21 stays NV21, with mesh and sensor rotation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(examCameraFormat, ImageFormatGroup.nv21);
      expect(liveCameraFormat, ImageFormatGroup.yuv420);
      final ai = AiHandler.session();
      expect(ai.supportsFaceMesh, isTrue);
      ai.setCameraRotation(270, true);
      await ai.initModel();
      final bytes = Uint8List.fromList([1, 2, 3, 4, 128, 128]);
      await ai.runInferenceMobile(
        cameraFrame(17, 2, 2, [
          {'bytes': bytes, 'bytesPerRow': 2, 'bytesPerPixel': 1},
        ]),
      );
      final input = (calls.first.arguments as Map)['imageData'] as Map;
      expect(input['bytes'], orderedEquals(bytes));
      expect(input['metadata'], containsPair('image_format', 17));
      expect(input['metadata'], containsPair('rotation', 270));
      await ai.dispose();
      expect(
        calls.where((call) => call.method.contains('close')),
        hasLength(4),
      );
    },
  );

  test(
    'Android YUV420 honors independent row and chroma pixel strides',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ai = AiHandler.session();
      await ai.initModel();
      await ai.runInferenceMobile(
        cameraFrame(35, 2, 2, [
          {
            'bytes': Uint8List.fromList([1, 2, 99, 99, 3, 4]),
            'bytesPerRow': 4,
            'bytesPerPixel': 1,
          },
          {
            'bytes': Uint8List.fromList([10, 99]),
            'bytesPerRow': 2,
            'bytesPerPixel': 2,
          },
          {
            'bytes': Uint8List.fromList([20, 99]),
            'bytesPerRow': 2,
            'bytesPerPixel': 2,
          },
        ]),
      );
      final input = (calls.first.arguments as Map)['imageData'] as Map;
      expect(input['bytes'], orderedEquals([1, 2, 3, 4, 20, 10]));
      await ai.dispose();
    },
  );

  test(
    'BGRA JPEG encoding honors padded rows, color order and portrait dimensions',
    () {
      final bytes = Uint8List(16 * 24 * 4);
      // Width 8, height 24; stride 64 includes 32 padding bytes after each row.
      for (var y = 0; y < 24; y++) {
        for (var x = 0; x < 8; x++) {
          final offset = y * 64 + x * 4;
          bytes.setRange(
            offset,
            offset + 4,
            y < 12 ? [0, 0, 255, 255] : [255, 0, 0, 255],
          );
        }
      }
      final jpeg = cameraFrameToJpeg({
        'w': 8,
        'h': 24,
        'bgra': bytes,
        'stride': 64,
      });
      final decoded = img.decodeJpg(jpeg!)!;
      expect(decoded.width, 8);
      expect(decoded.height, 24);
      expect(decoded.getPixel(4, 4).r, greaterThan(220));
      expect(decoded.getPixel(4, 20).b, greaterThan(220));
    },
  );

  test('Android JPEG conversion still applies sensor rotation', () {
    final jpeg = cameraFrameToJpeg({
      'w': 4,
      'h': 2,
      'y': Uint8List.fromList(List.filled(8, 128)),
      'u': Uint8List.fromList([128, 128]),
      'v': Uint8List.fromList([128, 128]),
      'yStride': 4,
      'uvStride': 2,
      'uvPixel': 1,
      'rotation': 90,
    });
    final decoded = img.decodeJpg(jpeg!)!;
    expect(decoded.width, 2);
    expect(decoded.height, 4);
  });

  testWidgets('iPhone instructions disclose the missing eye-only tracking', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ai = AiHandler.session();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExamInstructions(
            onBegin: () {},
            monitoringNotice: ai.monitoringNotice,
          ),
        ),
      ),
    );
    expect(find.text(ai.monitoringNotice!), findsOneWidget);
    expect(tester.takeException(), isNull);
    await ai.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
