import 'package:aicheat/screens/dashboard/camera_screen.dart';
import 'package:aicheat/services/ai_handler.dart';
import 'package:aicheat/services/camera_lifecycle.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const description = CameraDescription(
  name: 'demo',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 90,
);

class _Ai extends AiHandler {
  _Ai() : super.session();
  bool calibrated = false;
  @override
  bool get isCalibrated => calibrated;
  @override
  bool get isReady => true;
  @override
  Future<void> initModel() async {}
  @override
  Future<void> dispose() async {
    onResult = null;
  }
}

class _Clock extends Fake implements Stopwatch {
  bool running = false;
  Duration time = Duration.zero;
  @override
  bool get isRunning => running;
  @override
  Duration get elapsed => time;
  @override
  void start() {
    running = true;
  }

  @override
  void stop() {
    running = false;
  }
}

class _Camera extends Fake implements CameraController {
  bool streaming = false;
  bool disposed = false;
  @override
  CameraValue get value => CameraValue(
    isInitialized: true,
    isRecordingVideo: false,
    isTakingPicture: false,
    isStreamingImages: streaming,
    isRecordingPaused: false,
    flashMode: FlashMode.auto,
    exposureMode: ExposureMode.auto,
    focusMode: FocusMode.auto,
    exposurePointSupported: false,
    focusPointSupported: false,
    deviceOrientation: DeviceOrientation.portraitUp,
    description: description,
    previewSize: const Size(640, 480),
  );
  @override
  Future<void> initialize() async {}
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  Future<void> startImageStream(void Function(CameraImage) onAvailable) async {
    streaming = true;
  }

  @override
  Future<void> stopImageStream() async {
    streaming = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  Future<void> start(
    WidgetTester tester,
    _Ai ai,
    _Camera camera,
    _Clock clock,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CameraScreen(
          aiHandler: ai,
          cameraProvider: () async => [description],
          cameraFactory: (_) => camera,
          examClock: clock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin Exam'));
    await tester.pumpAndSettle();
    expect(clock.running, isFalse);
    ai.faceCount = 1;
    ai.calibrated = true;
    ai.onResult!();
    await tester.pump();
    expect(clock.running, isTrue);
  }

  testWidgets(
    'Final answer enables Finish and completion stops monitoring and clock',
    (tester) async {
      final ai = _Ai();
      final camera = _Camera();
      final clock = _Clock();
      await start(tester, ai, camera, clock);
      for (final answer in [
        'Using a mobile phone during the test',
        'Automatic course failure',
        'Using approved reference material',
      ]) {
        await tester.ensureVisible(find.text(answer));
        await tester.tap(find.text(answer));
        await tester.pump();
        await tester.ensureVisible(find.text('Check answer'));
        await tester.tap(find.text('Check answer'));
        await tester.pump();
        if (answer != 'Using approved reference material') {
          await tester.tap(find.text('Next question'));
          await tester.pump();
        }
      }
      await tester.tap(find.text('Finish exam'));
      await tester.pumpAndSettle();
      expect(find.text('Exam completed'), findsOneWidget);
      expect(find.textContaining('Correct answers: 3 of 3'), findsOneWidget);
      expect(clock.running, isFalse);
      expect(camera.streaming, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await waitForCameraRelease();
      expect(camera.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
