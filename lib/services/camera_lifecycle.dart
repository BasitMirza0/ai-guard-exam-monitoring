import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Keep the native preview bound. CameraX rebinding a paused preview while
/// attaching image analysis can time out on some Android camera drivers.
Future<void> syncCameraStream(
  CameraController? controller, {
  required bool enabled,
  required void Function(CameraImage) onFrame,
}) async {
  if (controller == null || !controller.value.isInitialized) return;
  if (enabled && !controller.value.isStreamingImages) {
    await controller.startImageStream(onFrame);
  } else if (!enabled && controller.value.isStreamingImages) {
    await controller.stopImageStream();
  }
}

/// A route can close before camera initialization or stream startup finishes.
Future<void> _cameraRelease = Future<void>.value();

Future<void> waitForCameraRelease() => _cameraRelease;

Future<void> releaseCamera(
  CameraController? controller, {
  Future<void>? pending,
}) {
  if (controller == null) return _cameraRelease;
  return _cameraRelease = _cameraRelease.then((_) async {
    try {
      await pending;
    } catch (_) {
      // A failed start/stop operation must not poison the global release chain.
    } finally {
      await _release(controller);
    }
  });
}

Future<void> _release(CameraController? controller) async {
  if (controller == null) return;
  try {
    if (controller.value.isInitialized && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  } catch (error) {
    debugPrint('[Camera] Stream cleanup: $error');
  } finally {
    try {
      await controller.dispose();
    } catch (error) {
      debugPrint('[Camera] Camera cleanup: $error');
    }
  }
}
