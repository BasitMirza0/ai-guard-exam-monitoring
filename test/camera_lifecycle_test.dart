import 'dart:async';
import 'package:aicheat/services/camera_lifecycle.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  test(
    'Failed pending startup still releases camera and allows next session',
    () async {
      final camera = _Camera(initialized: true, streaming: false);
      final pending = Completer<void>();
      final release = releaseCamera(camera, pending: pending.future);
      pending.completeError(StateError('startup failed'));
      await release;
      await waitForCameraRelease();
      expect(camera.disposed, isTrue);
    },
  );
  test(
    'Closing before initialization does not stop a nonexistent stream',
    () async {
      final camera = _Camera(initialized: false, streaming: false);
      await releaseCamera(camera);
      expect(camera.stopped, isFalse);
      expect(camera.disposed, isTrue);
    },
  );
  test(
    'The next route waits until camera operations and disposal finish',
    () async {
      final pending = Completer<void>();
      final camera = _Camera(initialized: true, streaming: true);
      final release = releaseCamera(camera, pending: pending.future);
      var nextReady = false;
      final next = waitForCameraRelease().then((_) => nextReady = true);
      await Future<void>.delayed(Duration.zero);
      expect(nextReady, isFalse);
      expect(camera.disposed, isFalse);
      pending.complete();
      await release;
      await next;
      expect(camera.calls, ['stop', 'dispose']);
      expect(nextReady, isTrue);
    },
  );
  test(
    'Instructions leave preview bound and Begin enables inference exactly once',
    () async {
      final camera = _Camera(initialized: true, streaming: false);
      await syncCameraStream(camera, enabled: false, onFrame: (_) {});
      expect(camera.calls, isEmpty);
      await syncCameraStream(camera, enabled: true, onFrame: (_) {});
      await syncCameraStream(camera, enabled: true, onFrame: (_) {});
      expect(camera.calls, ['start']);
      await syncCameraStream(camera, enabled: false, onFrame: (_) {});
      expect(camera.calls, ['start', 'stop']);
      expect(camera.disposed, isFalse);
      expect(camera.previewPaused, isFalse);
      await releaseCamera(camera);
    },
  );

  test('Closing an active camera stops the stream before disposal', () async {
    final camera = _Camera(initialized: true, streaming: true);
    await releaseCamera(camera);
    expect(camera.calls, ['stop', 'dispose']);
  });
  test(
    'Stream cleanup failure still releases the camera without throwing',
    () async {
      final camera = _Camera(
        initialized: true,
        streaming: true,
        failStop: true,
      );
      await releaseCamera(camera);
      expect(camera.disposed, isTrue);
    },
  );
}

class _Camera extends Fake implements CameraController {
  _Camera({
    required this.initialized,
    required this.streaming,
    this.failStop = false,
  });
  final bool initialized, failStop;
  bool streaming;
  bool previewPaused = false;
  bool stopped = false, disposed = false;
  final calls = <String>[];
  @override
  CameraValue get value => CameraValue(
    isInitialized: initialized,
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
    description: const CameraDescription(
      name: 'test',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 90,
    ),
  );
  @override
  Future<void> stopImageStream() async {
    stopped = true;
    streaming = false;
    calls.add('stop');
    if (failStop) {
      throw CameraException(
        'Uninitialized CameraController',
        'Closed while initializing',
      );
    }
  }

  @override
  Future<void> startImageStream(void Function(CameraImage) onAvailable) async {
    calls.add('start');
    streaming = true;
  }

  @override
  Future<void> pausePreview() async {
    calls.add('pausePreview');
    previewPaused = true;
  }

  @override
  Future<void> resumePreview() async {
    calls.add('resumePreview');
    previewPaused = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    calls.add('dispose');
  }
}
