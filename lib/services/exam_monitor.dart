import 'ai_handler.dart';

enum ExamWarningType {
  none,
  lookingAway,
  headTurn,
  noFace,
  multiPerson,
  phone,
  device,
}

class ExamWarning {
  const ExamWarning({
    required this.type,
    required this.title,
    required this.detail,
    required this.progress,
    this.critical = false,
    this.terminate = false,
  });

  final ExamWarningType type;
  final String title;
  final String detail;
  final double progress;
  final bool critical;
  final bool terminate;
}

/// Evaluates every signal in a frame before choosing what the exam displays.
/// Behavior counters belong to AiHandler; presence/device counters live here.
class ExamMonitor {
  int _noFaceFrames = 0;
  int _multiFrames = 0;
  final Map<String, int> _deviceFrames = {};

  List<ExamWarning> evaluate({
    required List<DetectedObject> detections,
    required BehaviorState behavior,
    required int faceCount,
    required bool isCalibrated,
  }) {
    final warnings = <ExamWarning>[];
    final devices =
        detections.where((d) => d.isViolation).map((d) => d.label).toSet();

    // A confirmed phone keeps the existing instant-termination policy,
    // including during calibration, independent of face/head/gaze signals.
    if (devices.contains('Phone')) {
      warnings.add(
        const ExamWarning(
          type: ExamWarningType.phone,
          title: 'Mobile Phone Detected',
          detail: 'Mobile phones are prohibited during the exam',
          progress: 1,
          critical: true,
          terminate: true,
        ),
      );
    }

    if (!isCalibrated) {
      _noFaceFrames = 0;
      _multiFrames = 0;
      _deviceFrames.clear();
      return warnings;
    }

    // Each device has its own counter. Switching devices cannot carry a
    // previous object's frames into the new object's termination threshold.
    _deviceFrames.removeWhere((label, _) => !devices.contains(label));
    for (final label in devices.where((label) => label != 'Phone')) {
      final frames = (_deviceFrames[label] ?? 0) + 1;
      _deviceFrames[label] = frames;
      warnings.add(
        ExamWarning(
          type: ExamWarningType.device,
          title: '$label Detected',
          detail: 'Remove the prohibited item to continue',
          progress: (frames / 3).clamp(0.0, 1.0),
          critical: frames >= 2,
          terminate: frames >= 3,
        ),
      );
    }

    _noFaceFrames = faceCount == 0 ? _noFaceFrames + 1 : 0;
    _multiFrames = faceCount > 1 ? _multiFrames + 1 : 0;
    if (_noFaceFrames >= 4) {
      warnings.add(
        ExamWarning(
          type: ExamWarningType.noFace,
          title: 'Face Not Visible',
          detail: 'Please move in front of the camera',
          progress: (_noFaceFrames / 38).clamp(0.0, 1.0),
          critical: _noFaceFrames / 38 > 0.6,
          terminate: _noFaceFrames >= 38,
        ),
      );
    }
    if (_multiFrames > 0) {
      warnings.add(
        ExamWarning(
          type: ExamWarningType.multiPerson,
          title: 'Multiple People Detected',
          detail: 'Only you should be visible on camera',
          progress: (_multiFrames / 12).clamp(0.0, 1.0),
          critical: true,
          terminate: _multiFrames >= 12,
        ),
      );
    }

    // Pose/gaze are meaningful only for a single visible examinee. Devices
    // and face presence above continue independently in every frame.
    if (faceCount == 1) {
      if (behavior.headTurnFrames >= 1) {
        warnings.add(
          ExamWarning(
            type: ExamWarningType.headTurn,
            title: behavior.headWarning,
            detail: 'Keep your head facing the camera',
            progress: (behavior.headTurnFrames /
                    BehaviorState.headViolationThreshold)
                .clamp(0.0, 1.0),
            critical: behavior.headTurnFrames >= 2,
            terminate: behavior.isHeadViolation,
          ),
        );
      }
      if (behavior.gazeAwayFrames >= 2) {
        warnings.add(
          ExamWarning(
            type: ExamWarningType.lookingAway,
            title: behavior.gazeWarning,
            detail: 'Keep your eyes on the screen',
            progress: (behavior.gazeAwayFrames /
                    BehaviorState.gazeViolationThreshold)
                .clamp(0.0, 1.0),
            critical: behavior.gazeAwayFrames >= 3,
            terminate: behavior.isGazeViolation,
          ),
        );
      }
      if (behavior.irisAwayFrames >= 3) {
        warnings.add(
          ExamWarning(
            type: ExamWarningType.lookingAway,
            title: behavior.irisWarning,
            detail: 'Keep your eyes on the screen',
            progress: (behavior.irisAwayFrames /
                    BehaviorState.irisViolationThreshold)
                .clamp(0.0, 1.0),
            critical: behavior.irisAwayFrames >= 3,
            terminate: behavior.isIrisViolation,
          ),
        );
      }
    }

    // Termination always takes precedence over a warning. Preserve the
    // category order on ties (phone, device, presence, head, gaze, iris).
    final ordered = <ExamWarning>[
      ...warnings.where((w) => w.terminate),
      ...warnings.where((w) => !w.terminate && w.critical),
      ...warnings.where((w) => !w.terminate && !w.critical),
    ];
    return ordered;
  }
}
