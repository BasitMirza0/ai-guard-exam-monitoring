// Historical implementation retained for reference; not imported by the app.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

// =============================================================================
// Enums
// =============================================================================
enum GazeDirection { center, left, right, up, down, unknown }

enum HeadPose {
  forward,
  lookingLeft,
  lookingRight,
  tiltedLeft,
  tiltedRight,
  lookingUp,
  lookingDown,
}

// =============================================================================
// ViolationLog
// =============================================================================
class ViolationLog {
  final String reason;
  final DateTime timestamp;
  final GazeDirection? gaze;
  final HeadPose? headPose;

  const ViolationLog({
    required this.reason,
    required this.timestamp,
    this.gaze,
    this.headPose,
  });

  @override
  String toString() =>
      '[${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}] $reason';
}

// =============================================================================
// IrisGazeState — published every frame alongside BehaviorState
// =============================================================================
class IrisGazeState {
  /// Normalized ratio 0.0–1.0
  /// 0.0 = iris fully left in eye
  /// 0.5 = iris centered
  /// 1.0 = iris fully right in eye
  final double ratioX;

  /// Normalized ratio 0.0–1.0
  /// 0.0 = iris at top of eye
  /// 0.5 = iris centered
  /// 1.0 = iris at bottom of eye
  final double ratioY;

  final GazeDirection direction;
  final bool isAvailable; // false if Face Mesh did not return iris points

  const IrisGazeState({
    this.ratioX = 0.5,
    this.ratioY = 0.5,
    this.direction = GazeDirection.unknown,
    this.isAvailable = false,
  });

  String get directionLabel {
    switch (direction) {
      case GazeDirection.left:
        return '👈 Eyes Left';
      case GazeDirection.right:
        return '👉 Eyes Right';
      case GazeDirection.up:
        return '👆 Eyes Up';
      case GazeDirection.down:
        return '👇 Eyes Down';
      case GazeDirection.center:
        return '✅ Eyes Forward';
      case GazeDirection.unknown:
        return '';
    }
  }
}

// =============================================================================
// BehaviorState — published every frame
// =============================================================================
class BehaviorState {
  final GazeDirection gazeDirection;
  final HeadPose headPose;
  final bool eyesClosed;
  final double headYaw;
  final double headPitch;
  final double headRoll;

  final int gazeAwayFrames;
  final int headTurnFrames;

  // ── Advanced fields ────────────────────────────────────────────────────────
  final int attentionScore;
  final bool isSuspicious;
  final double blinkRate;
  final String attentionLabel;
  final bool eyesVisible;

  // ── NEW: iris-specific violation counter ───────────────────────────────────
  final int irisAwayFrames;

  // Thresholds
  static const int gazeViolationThreshold = 8; // 8 × 150ms = 1.2s
  static const int headViolationThreshold = 5; // 5 × 150ms = 0.75s
  static const int irisViolationThreshold = 6; // 6 × 150ms = 0.9s

  const BehaviorState({
    this.gazeDirection = GazeDirection.unknown,
    this.headPose = HeadPose.forward,
    this.eyesClosed = false,
    this.headYaw = 0,
    this.headPitch = 0,
    this.headRoll = 0,
    this.gazeAwayFrames = 0,
    this.headTurnFrames = 0,
    this.attentionScore = 100,
    this.isSuspicious = false,
    this.blinkRate = 0,
    this.attentionLabel = 'Attentive',
    this.eyesVisible = true,
    this.irisAwayFrames = 0,
  });

  bool get isGazeViolation => gazeAwayFrames >= gazeViolationThreshold;
  bool get isHeadViolation => headTurnFrames >= headViolationThreshold;
  bool get isIrisViolation => irisAwayFrames >= irisViolationThreshold;
  bool get isEyeViolation => eyesClosed;

  String get violationReason {
    if (isIrisViolation) {
      return _irisViolationLabel;
    }
    if (isGazeViolation) {
      return _gazeViolationLabel;
    }
    if (isHeadViolation) {
      return _headViolationLabel;
    }
    if (isEyeViolation) {
      return 'Eyes Closed';
    }
    return '';
  }

  String get _irisViolationLabel {
    switch (gazeDirection) {
      case GazeDirection.left:
        return 'Eyes Looking Left';
      case GazeDirection.right:
        return 'Eyes Looking Right';
      case GazeDirection.up:
        return 'Eyes Looking Up';
      case GazeDirection.down:
        return 'Eyes Looking Down';
      default:
        return 'Suspicious Eye Movement';
    }
  }

  String get _gazeViolationLabel {
    switch (gazeDirection) {
      case GazeDirection.left:
        return 'Looking Left';
      case GazeDirection.right:
        return 'Looking Right';
      case GazeDirection.up:
        return 'Looking Up';
      case GazeDirection.down:
        return 'Looking Down';
      default:
        return 'Gaze Away';
    }
  }

  String get _headViolationLabel {
    switch (headPose) {
      case HeadPose.lookingLeft:
        return 'Head Turned Left';
      case HeadPose.lookingRight:
        return 'Head Turned Right';
      case HeadPose.lookingUp:
        return 'Head Turned Up';
      case HeadPose.lookingDown:
        return 'Head Turned Down';
      case HeadPose.tiltedLeft:
      case HeadPose.tiltedRight:
        return 'Head Tilted';
      default:
        return 'Head Moved';
    }
  }

  String get gazeLabel {
    switch (gazeDirection) {
      case GazeDirection.left:
        return '👈 Looking Left';
      case GazeDirection.right:
        return '👉 Looking Right';
      case GazeDirection.up:
        return '👆 Looking Up';
      case GazeDirection.down:
        return '👇 Looking Down';
      case GazeDirection.center:
        return '✅ Looking Forward';
      case GazeDirection.unknown:
        return '';
    }
  }

  String get headLabel {
    switch (headPose) {
      case HeadPose.lookingLeft:
        return 'Head Left';
      case HeadPose.lookingRight:
        return 'Head Right';
      case HeadPose.tiltedLeft:
      case HeadPose.tiltedRight:
        return 'Head Tilted';
      case HeadPose.lookingUp:
        return 'Head Up';
      case HeadPose.lookingDown:
        return 'Head Down';
      case HeadPose.forward:
        return '';
    }
  }
}

// =============================================================================
// DetectedObject
// =============================================================================
class DetectedObject {
  final String label;
  final double confidence;
  final Rect rect;
  final bool isViolation;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.rect,
    required this.isViolation,
  });
}

// =============================================================================
// AiHandler — singleton
// =============================================================================
class AiHandler {
  static final AiHandler _instance = AiHandler._internal();
  factory AiHandler() => _instance;
  AiHandler._internal();

  // Detectors
  FaceDetector? _faceDetector;
  FaceMeshDetector? _meshDetector;
  ImageLabeler? _imageLabeler;
  ObjectDetector? _objectDetector;

  bool _mlReady = false;
  bool _mlBusy = false;

  InputImageRotation _rotation = InputImageRotation.rotation90deg;
  bool _swapWH = true;

  // ── Calibration ─────────────────────────────────────────────────────────────
  static const int _calibFrames = 15;
  int _calibCount = 0;
  double _yawBaseline = 0;
  double _pitchBaseline = 0;
  bool _isCalibrated = false;
  final List<double> _calibYaw = [];
  final List<double> _calibPitch = [];

  // ── Device stability ─────────────────────────────────────────────────────────
  String? _lastDeviceLabel;
  int _deviceConsecutiveCount = 0;
  static const int _deviceStabilityFrames = 3;

  // ── Behavioral counters ──────────────────────────────────────────────────────
  int _gazeAwayFrames = 0;
  int _headTurnFrames = 0;

  // ── NEW: Iris violation counter ──────────────────────────────────────────────
  int _irisAwayFrames = 0;

  // ── Smoothing histories ──────────────────────────────────────────────────────
  final List<GazeDirection> _gazeHistory = [];
  static const int _gazeHistSize = 3;
  final List<double> _yawHistory = [];
  final List<double> _pitchHistory = [];
  static const int _poseHistSize = 3;

  // ── NEW: Iris ratio smoothing ────────────────────────────────────────────────
  final List<double> _irisXHistory = [];
  final List<double> _irisYHistory = [];
  static const int _irisHistSize = 4;

  // ── Advanced: attention scoring ─────────────────────────────────────────────
  final List<GazeDirection> _gazeWindow = [];
  static const int _gazeWindowSize = 30;
  int _attentionScore = 100;
  bool _isSuspicious = false;

  // ── Advanced: blink rate ────────────────────────────────────────────────────
  int _blinkCount = 0;
  bool _wasEyesClosed = false;
  DateTime _sessionStart = DateTime.now();
  double _blinkRate = 0.0;

  // ── Violation log ────────────────────────────────────────────────────────────
  final List<ViolationLog> _violationLog = [];
  List<ViolationLog> get violationLog => List.unmodifiable(_violationLog);

  // ── Public state ─────────────────────────────────────────────────────────────
  bool isViolationDetected = false;
  List<DetectedObject> detectedObjects = [];
  int faceCount = 0;
  BehaviorState behaviorState = const BehaviorState();
  IrisGazeState irisGazeState = const IrisGazeState();

  bool get isCalibrated => _isCalibrated;
  int get calibProgress =>
      (_calibCount / _calibFrames * 100).clamp(0, 100).toInt();

  VoidCallback? onResult;

  // ── Camera rotation ──────────────────────────────────────────────────────────
  void setCameraRotation(int sensorOrientation, bool isFront) {
    switch (sensorOrientation) {
      case 0:
        _rotation = InputImageRotation.rotation0deg;
        _swapWH = false;
        break;
      case 90:
        _rotation = InputImageRotation.rotation90deg;
        _swapWH = true;
        break;
      case 180:
        _rotation = InputImageRotation.rotation180deg;
        _swapWH = false;
        break;
      case 270:
        _rotation = InputImageRotation.rotation270deg;
        _swapWH = true;
        break;
      default:
        _rotation = InputImageRotation.rotation90deg;
        _swapWH = true;
        break;
    }
    debugPrint('[AiHandler] rotation=$_rotation');
  }

  // ── Init ─────────────────────────────────────────────────────────────────────
  Future<void> initModel() async {
    if (_mlReady) {
      return;
    }
    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableTracking: true,
          enableClassification: true,
          enableLandmarks: true,
          minFaceSize: 0.08,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
      _meshDetector = FaceMeshDetector(
        option: FaceMeshDetectorOptions.faceMesh,
      );
      _imageLabeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.30),
      );
      _objectDetector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
      _mlReady = true;
      debugPrint('[AiHandler] ✅ All 4 engines ready (v9.0 — Iris Gaze)');
    } catch (e) {
      debugPrint('[AiHandler] ❌ Init failed: $e');
    }
  }

  // ── Reset for new session ────────────────────────────────────────────────────
  void resetForNewSession() {
    _gazeAwayFrames = 0;
    _headTurnFrames = 0;
    _irisAwayFrames = 0;
    _deviceConsecutiveCount = 0;
    _lastDeviceLabel = null;
    _gazeHistory.clear();
    _yawHistory.clear();
    _pitchHistory.clear();
    _irisXHistory.clear();
    _irisYHistory.clear();
    _gazeWindow.clear();
    isViolationDetected = false;
    detectedObjects = [];
    faceCount = 0;
    behaviorState = const BehaviorState();
    irisGazeState = const IrisGazeState();
    _calibCount = 0;
    _isCalibrated = false;
    _calibYaw.clear();
    _calibPitch.clear();
    _yawBaseline = 0;
    _pitchBaseline = 0;
    _attentionScore = 100;
    _isSuspicious = false;
    _blinkCount = 0;
    _wasEyesClosed = false;
    _sessionStart = DateTime.now();
    _blinkRate = 0.0;
    _violationLog.clear();
    debugPrint('[AiHandler] 🔄 Session reset (v9.0)');
  }

  // ── Frame entry ──────────────────────────────────────────────────────────────
  Future<void> runInferenceMobile(CameraImage img) async {
    if (_mlReady && !_mlBusy) {
      _mlBusy = true;
      _runPipeline(img);
    }
  }

  // ── Main pipeline ─────────────────────────────────────────────────────────────
  Future<void> _runPipeline(CameraImage img) async {
    try {
      final inputImage = _toInputImage(img);
      if (inputImage == null) {
        _mlBusy = false;
        return;
      }

      final fresh = <DetectedObject>[];
      final frameW = _swapWH ? img.height.toDouble() : img.width.toDouble();
      final frameH = _swapWH ? img.width.toDouble() : img.height.toDouble();

      // ══════════════════════════════════════════════════════════════════
      // ENGINE 1: Face Detection
      // ══════════════════════════════════════════════════════════════════
      Rect? faceNorm;
      double rawYaw = 0;
      double rawPitch = 0;
      double headRoll = 0;
      bool eyesClosed = false;
      bool eyesVisible = true;

      if (_faceDetector != null) {
        final faces = await _faceDetector!.processImage(inputImage);
        faceCount = faces.length;

        if (faces.isNotEmpty) {
          final face = faces.reduce(
            (a, b) =>
                (a.boundingBox.width * a.boundingBox.height) >
                        (b.boundingBox.width * b.boundingBox.height)
                    ? a
                    : b,
          );

          final b = face.boundingBox;
          faceNorm = Rect.fromLTWH(
            (b.left / frameW).clamp(0.0, 1.0),
            (b.top / frameH).clamp(0.0, 1.0),
            (b.width / frameW).clamp(0.01, 1.0),
            (b.height / frameH).clamp(0.01, 1.0),
          );
          fresh.add(
            DetectedObject(
              label: 'Person',
              confidence: 0.95,
              rect: faceNorm,
              isViolation: false,
            ),
          );

          rawYaw = face.headEulerAngleY ?? 0;
          rawPitch = face.headEulerAngleX ?? 0;
          headRoll = face.headEulerAngleZ ?? 0;

          final leftEye = face.leftEyeOpenProbability ?? 1.0;
          final rightEye = face.rightEyeOpenProbability ?? 1.0;
          eyesClosed = leftEye < 0.3 && rightEye < 0.3;
          eyesVisible = leftEye != 1.0 || rightEye != 1.0;

          if (!_wasEyesClosed && eyesClosed) {
            _blinkCount++;
          }
          _wasEyesClosed = eyesClosed;

          final elapsed = DateTime.now().difference(_sessionStart).inSeconds;
          if (elapsed > 0) {
            _blinkRate = (_blinkCount / elapsed) * 60.0;
          }
        }
      }

      // ── Calibration phase ────────────────────────────────────────────────────
      if (!_isCalibrated && faceNorm != null) {
        _calibYaw.add(rawYaw);
        _calibPitch.add(rawPitch);
        _calibCount++;
        if (_calibCount >= _calibFrames) {
          _calibYaw.sort();
          _calibPitch.sort();
          _yawBaseline = _calibYaw[_calibYaw.length ~/ 2];
          _pitchBaseline = _calibPitch[_calibPitch.length ~/ 2];
          _isCalibrated = true;
          debugPrint(
            '[AiHandler] 📐 Calibrated: '
            'yawBase=$_yawBaseline pitchBase=$_pitchBaseline',
          );
        }
        _mlBusy = false;
        onResult?.call();
        return;
      }

      // ── Axis correction ──────────────────────────────────────────────────────
      final correctedYaw = -(rawYaw - _yawBaseline);
      final correctedPitch = (rawPitch - _pitchBaseline);

      _yawHistory.add(correctedYaw);
      if (_yawHistory.length > _poseHistSize) {
        _yawHistory.removeAt(0);
      }
      final smoothedYaw =
          _yawHistory.reduce((a, b) => a + b) / _yawHistory.length;

      _pitchHistory.add(correctedPitch);
      if (_pitchHistory.length > _poseHistSize) {
        _pitchHistory.removeAt(0);
      }
      final smoothedPitch =
          _pitchHistory.reduce((a, b) => a + b) / _pitchHistory.length;

      // ══════════════════════════════════════════════════════════════════
      // GAZE from head pose (primary)
      // ══════════════════════════════════════════════════════════════════
      GazeDirection rawGaze = GazeDirection.center;

      if (faceNorm != null) {
        if (smoothedYaw > 20.0) {
          rawGaze = GazeDirection.right;
        } else if (smoothedYaw < -20.0) {
          rawGaze = GazeDirection.left;
        } else if (smoothedPitch > 15.0) {
          rawGaze = GazeDirection.up;
        } else if (smoothedPitch < -20.0) {
          rawGaze = GazeDirection.down;
        } else {
          rawGaze = GazeDirection.center;
        }

        // ══════════════════════════════════════════════════════════════════
        // ENGINE 2: Face Mesh — Iris Gaze (secondary)
        // ══════════════════════════════════════════════════════════════════
        if (_meshDetector != null) {
          try {
            final meshes = await _meshDetector!.processImage(inputImage);
            if (meshes.isNotEmpty) {
              // Compute true iris gaze
              final irisResult = _computeIrisGaze(meshes.first);

              // Update public iris state
              irisGazeState = irisResult;

              if (irisResult.isAvailable &&
                  irisResult.direction != GazeDirection.unknown) {
                // When head is mostly forward — fully trust iris gaze
                // This is the KEY change — detects eye-only movement
                if (smoothedYaw.abs() < 15.0 && smoothedPitch.abs() < 15.0) {
                  rawGaze = irisResult.direction;
                  debugPrint(
                    '[IrisGaze] Head forward → iris override: '
                    '${irisResult.direction.name} '
                    'X=${irisResult.ratioX.toStringAsFixed(2)} '
                    'Y=${irisResult.ratioY.toStringAsFixed(2)}',
                  );
                }
                // Head is also moving same direction — stronger signal
                else if (irisResult.direction != GazeDirection.center) {
                  rawGaze = irisResult.direction;
                  debugPrint(
                    '[IrisGaze] Head+iris → ${irisResult.direction.name}',
                  );
                }

                // Update iris violation counter
                final irisAway =
                    irisResult.direction != GazeDirection.center &&
                    irisResult.direction != GazeDirection.unknown;

                if (irisAway) {
                  _irisAwayFrames++;
                } else {
                  _irisAwayFrames = 0;
                }
              } else {
                // Iris not available — reset iris counter
                _irisAwayFrames = 0;
                irisGazeState = const IrisGazeState(isAvailable: false);
              }
            }
          } catch (e) {
            debugPrint('[FaceMesh] Error: $e');
          }
        }
      } else {
        rawGaze = GazeDirection.unknown;
        _irisAwayFrames = 0;
        irisGazeState = const IrisGazeState(isAvailable: false);
      }

      // ── Smooth gaze ───────────────────────────────────────────────────────────
      _gazeHistory.add(rawGaze);
      if (_gazeHistory.length > _gazeHistSize) {
        _gazeHistory.removeAt(0);
      }
      final smoothedGaze = _majorityVote(_gazeHistory);

      debugPrint(
        '[Gaze v9.0] '
        'corrYaw=${correctedYaw.toStringAsFixed(1)} '
        'corrPitch=${correctedPitch.toStringAsFixed(1)} '
        'iris=${irisGazeState.direction.name} '
        'final=${smoothedGaze.name}',
      );

      // ── Gaze counter ──────────────────────────────────────────────────────────
      final gazeIsAway =
          smoothedGaze == GazeDirection.left ||
          smoothedGaze == GazeDirection.right ||
          smoothedGaze == GazeDirection.up ||
          smoothedGaze == GazeDirection.down;

      if (gazeIsAway && faceCount > 0) {
        _gazeAwayFrames++;
      } else if (smoothedGaze == GazeDirection.center) {
        _gazeAwayFrames = 0;
      }

      // ── Head pose ─────────────────────────────────────────────────────────────
      HeadPose pose = HeadPose.forward;
      if (smoothedYaw > 20) {
        pose = HeadPose.lookingRight;
      } else if (smoothedYaw < -20) {
        pose = HeadPose.lookingLeft;
      } else if (smoothedPitch > 15) {
        pose = HeadPose.lookingUp;
      } else if (smoothedPitch < -20) {
        pose = HeadPose.lookingDown;
      } else if (headRoll.abs() > 25) {
        pose = headRoll > 0 ? HeadPose.tiltedRight : HeadPose.tiltedLeft;
      }

      final headTurned =
          smoothedYaw.abs() > 25.0 ||
          smoothedPitch.abs() > 25.0 ||
          headRoll.abs() > 25.0;

      if (headTurned && faceCount > 0) {
        _headTurnFrames++;
      } else if (!headTurned) {
        _headTurnFrames = 0;
      }

      // ══════════════════════════════════════════════════════════════════
      // Attention score
      // ══════════════════════════════════════════════════════════════════
      _gazeWindow.add(smoothedGaze);
      if (_gazeWindow.length > _gazeWindowSize) {
        _gazeWindow.removeAt(0);
      }

      int switches = 0;
      for (int i = 1; i < _gazeWindow.length; i++) {
        if (_gazeWindow[i] != _gazeWindow[i - 1] &&
            (_gazeWindow[i] != GazeDirection.center ||
                _gazeWindow[i - 1] != GazeDirection.center)) {
          switches++;
        }
      }
      _isSuspicious = switches > 6 && _gazeWindow.length >= 20;

      int score = 100;
      if (gazeIsAway) {
        score -= math.min(40, _gazeAwayFrames * 5);
      }
      if (headTurned) {
        score -= math.min(30, _headTurnFrames * 4);
      }
      if (eyesClosed) {
        score -= 25;
      }
      if (_isSuspicious) {
        score -= 20;
      }
      if (faceCount == 0) {
        score -= 50;
      }
      if (faceCount > 1) {
        score -= 30;
      }
      // NEW: iris violations reduce attention score
      if (_irisAwayFrames > 0) {
        score -= math.min(20, _irisAwayFrames * 3);
      }
      _attentionScore = score.clamp(0, 100);

      final attnLabel =
          _attentionScore >= 80
              ? 'Attentive'
              : _attentionScore >= 60
              ? 'Distracted'
              : _attentionScore >= 40
              ? 'Suspicious'
              : 'Violation Risk';

      // ── Build BehaviorState ───────────────────────────────────────────────────
      behaviorState = BehaviorState(
        gazeDirection: smoothedGaze,
        headPose: pose,
        eyesClosed: eyesClosed,
        headYaw: smoothedYaw,
        headPitch: smoothedPitch,
        headRoll: headRoll,
        gazeAwayFrames: _gazeAwayFrames,
        headTurnFrames: _headTurnFrames,
        attentionScore: _attentionScore,
        isSuspicious: _isSuspicious,
        blinkRate: _blinkRate,
        attentionLabel: attnLabel,
        eyesVisible: eyesVisible,
        irisAwayFrames: _irisAwayFrames,
      );

      // ── Log violations ────────────────────────────────────────────────────────
      if (behaviorState.isIrisViolation ||
          behaviorState.isGazeViolation ||
          behaviorState.isHeadViolation) {
        final reason = behaviorState.violationReason;
        if (_violationLog.isEmpty || _violationLog.last.reason != reason) {
          _violationLog.add(
            ViolationLog(
              reason: reason,
              timestamp: DateTime.now(),
              gaze: smoothedGaze,
              headPose: pose,
            ),
          );
          debugPrint('[ViolationLog] ${_violationLog.last}');
        }
      }

      // ══════════════════════════════════════════════════════════════════
      // ENGINE 3: Image Labeler
      // ══════════════════════════════════════════════════════════════════
      String? rawDevice;
      double rawDeviceConf = 0.0;

      if (_imageLabeler != null) {
        final labels = await _imageLabeler!.processImage(inputImage);
        final Map<String, double> lm = {};
        for (final l in labels) {
          lm[l.label.toLowerCase()] = l.confidence;
        }

        double phoneScore = _scorePhone(lm);
        double laptopScore = _scoreLaptop(lm);
        double monitorScore = _scoreMonitor(lm);
        final bookScore = _scoreBook(lm);

        final kbConf = lm['keyboard'] ?? 0.0;
        if (kbConf > 0.45) {
          laptopScore = (laptopScore + kbConf * 0.5).clamp(0.0, 1.0);
          monitorScore *= 0.35;
        }
        final tvConf = lm['television'] ?? (lm['television set'] ?? 0.0);
        final hasContext = (lm['room'] ?? 0) > 0.45 || (lm['desk'] ?? 0) > 0.45;
        if (tvConf > 0 && !hasContext) {
          monitorScore *= 0.5;
        }

        if (phoneScore >= 0.55 &&
            phoneScore >= laptopScore &&
            phoneScore >= monitorScore &&
            phoneScore >= bookScore) {
          rawDevice = 'Phone';
          rawDeviceConf = phoneScore;
        } else if (laptopScore >= 0.45 &&
            laptopScore >= monitorScore &&
            laptopScore >= bookScore) {
          rawDevice = 'Laptop';
          rawDeviceConf = laptopScore;
        } else if (monitorScore >= 0.45 && monitorScore >= bookScore) {
          rawDevice = 'Monitor';
          rawDeviceConf = monitorScore;
        } else if (bookScore >= 0.45) {
          rawDevice = 'Book';
          rawDeviceConf = bookScore;
        }
      }

      // ── Device stability ─────────────────────────────────────────────────────
      String? stableDevice;
      double stableConf = 0.0;

      if (rawDevice != null) {
        if (rawDevice == _lastDeviceLabel) {
          _deviceConsecutiveCount++;
        } else {
          _lastDeviceLabel = rawDevice;
          _deviceConsecutiveCount = 1;
        }
        if (_deviceConsecutiveCount >= _deviceStabilityFrames) {
          stableDevice = rawDevice;
          stableConf = rawDeviceConf;
        }
      } else {
        _lastDeviceLabel = null;
        _deviceConsecutiveCount = 0;
      }

      // ══════════════════════════════════════════════════════════════════
      // ENGINE 4: Object Detector
      // ══════════════════════════════════════════════════════════════════
      if (_objectDetector != null) {
        final objects = await _objectDetector!.processImage(inputImage);
        bool addedBox = false;

        if (stableDevice != null) {
          for (final obj in objects) {
            Label? bestLabel;
            for (final lbl in obj.labels) {
              if (bestLabel == null || lbl.confidence > bestLabel.confidence) {
                bestLabel = lbl;
              }
            }
            if (bestLabel == null || bestLabel.confidence < 0.25) {
              continue;
            }

            final lower = bestLabel.text.toLowerCase();
            final isElec =
                lower.contains('electronic') ||
                lower.contains('computer') ||
                lower.contains('home good') ||
                lower.contains('fashion');
            if (!isElec) {
              continue;
            }

            final b = obj.boundingBox;
            final bL = (b.left / frameW).clamp(0.0, 1.0);
            final bT = (b.top / frameH).clamp(0.0, 1.0);
            final bW = (b.width / frameW).clamp(0.01, 1.0);
            final bH = (b.height / frameH).clamp(0.01, 1.0);
            final area = bW * bH;
            final ar = bH / (bW == 0 ? 0.001 : bW);

            if (stableDevice == 'Phone' && area > 0.30) {
              continue;
            }
            if (stableDevice == 'Phone' && ar < 0.3) {
              continue;
            }
            if ((stableDevice == 'Monitor' || stableDevice == 'Laptop') &&
                area < 0.08) {
              continue;
            }
            if (bW < 0.04 || bH < 0.04) {
              continue;
            }

            fresh.add(
              DetectedObject(
                label: stableDevice,
                confidence: stableConf,
                rect: Rect.fromLTWH(bL, bT, bW, bH),
                isViolation: true,
              ),
            );
            addedBox = true;
          }

          if (!addedBox) {
            fresh.add(
              DetectedObject(
                label: stableDevice,
                confidence: stableConf,
                rect: _estimateRect(stableDevice, faceNorm),
                isViolation: true,
              ),
            );
          }
        }
      }

      detectedObjects = fresh;
      isViolationDetected =
          fresh.any((o) => o.isViolation) ||
          behaviorState.isGazeViolation ||
          behaviorState.isHeadViolation ||
          behaviorState.isIrisViolation ||
          behaviorState.isEyeViolation;

      onResult?.call();
    } catch (e) {
      debugPrint('[AiHandler] ⚠ Pipeline: $e');
    } finally {
      _mlBusy = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: TRUE IRIS GAZE TRACKING
  // Uses MediaPipe Face Mesh iris landmarks:
  //   Point 468 = left iris center
  //   Point 473 = right iris center
  //
  // How it works:
  //   1. Get eye boundary (corners + top + bottom)
  //   2. Get iris center (actual iris position)
  //   3. Calculate ratio: where iris is inside eye boundary
  //   4. Ratio 0.0 = far left/top, 0.5 = center, 1.0 = far right/bottom
  //   5. Classify into gaze direction
  // ═══════════════════════════════════════════════════════════════════════════
  IrisGazeState _computeIrisGaze(FaceMesh mesh) {
    final points = mesh.points;

    // Check if iris landmarks are available
    // Face Mesh returns 468 base points + 10 iris points = 478 total
    // If only 468 returned — iris tracking not available
    if (points.length < 478) {
      debugPrint(
        '[IrisGaze] Points=${points.length} — iris not available '
        '(need 478)',
      );
      return const IrisGazeState(isAvailable: false);
    }

    try {
      // ════════════════════════════════════════
      // LEFT EYE BOUNDARY LANDMARKS
      // ════════════════════════════════════════
      final leftOuter = points[33]; // outer corner (ear side)
      final leftInner = points[133]; // inner corner (nose side)
      final leftTop = points[159]; // top eyelid center
      final leftBottom = points[145]; // bottom eyelid center

      // ════════════════════════════════════════
      // RIGHT EYE BOUNDARY LANDMARKS
      // ════════════════════════════════════════
      final rightOuter = points[263]; // outer corner (ear side)
      final rightInner = points[362]; // inner corner (nose side)
      final rightTop = points[386]; // top eyelid center
      final rightBottom = points[374]; // bottom eyelid center

      // ════════════════════════════════════════
      // IRIS CENTER LANDMARKS
      // These are the REAL iris positions
      // NOT estimated from lid midpoints
      // ════════════════════════════════════════
      final leftIris = points[468]; // left iris center
      final rightIris = points[473]; // right iris center

      // ════════════════════════════════════════
      // EYE DIMENSIONS
      // ════════════════════════════════════════
      final leftEyeW = (leftOuter.x - leftInner.x).abs();
      final leftEyeH = (leftTop.y - leftBottom.y).abs();
      final rightEyeW = (rightOuter.x - rightInner.x).abs();
      final rightEyeH = (rightTop.y - rightBottom.y).abs();

      // Safety — if eye too small or closed skip
      if (leftEyeW < 2 || rightEyeW < 2) {
        return const IrisGazeState(isAvailable: false);
      }
      if (leftEyeH < 1 || rightEyeH < 1) {
        return const IrisGazeState(isAvailable: false);
      }

      // ════════════════════════════════════════
      // HORIZONTAL RATIO (left / right)
      // Formula: (irisX - eyeLeftEdge) / eyeWidth
      // Result:  0.0 = looking far left
      //          0.5 = looking straight
      //          1.0 = looking far right
      // ════════════════════════════════════════
      final leftMinX = math.min(leftOuter.x, leftInner.x);
      final rightMinX = math.min(rightOuter.x, rightInner.x);

      final leftRatioX = (leftIris.x - leftMinX) / leftEyeW;
      final rightRatioX = (rightIris.x - rightMinX) / rightEyeW;
      final rawRatioX = (leftRatioX + rightRatioX) / 2.0;

      // ════════════════════════════════════════
      // VERTICAL RATIO (up / down)
      // Formula: (irisY - eyeTopEdge) / eyeHeight
      // Result:  0.0 = looking up
      //          0.5 = looking straight
      //          1.0 = looking down
      // ════════════════════════════════════════
      final leftMinY = math.min(leftTop.y, leftBottom.y);
      final rightMinY = math.min(rightTop.y, rightBottom.y);

      final leftRatioY = (leftIris.y - leftMinY) / leftEyeH;
      final rightRatioY = (rightIris.y - rightMinY) / rightEyeH;
      final rawRatioY = (leftRatioY + rightRatioY) / 2.0;

      // ════════════════════════════════════════
      // SMOOTH IRIS RATIOS
      // Prevents jitter from single frame noise
      // ════════════════════════════════════════
      _irisXHistory.add(rawRatioX);
      if (_irisXHistory.length > _irisHistSize) {
        _irisXHistory.removeAt(0);
      }
      final smoothRatioX =
          _irisXHistory.reduce((a, b) => a + b) / _irisXHistory.length;

      _irisYHistory.add(rawRatioY);
      if (_irisYHistory.length > _irisHistSize) {
        _irisYHistory.removeAt(0);
      }
      final smoothRatioY =
          _irisYHistory.reduce((a, b) => a + b) / _irisYHistory.length;

      debugPrint(
        '[IrisGaze] '
        'L_ratioX=${leftRatioX.toStringAsFixed(2)} '
        'R_ratioX=${rightRatioX.toStringAsFixed(2)} '
        'smoothX=${smoothRatioX.toStringAsFixed(2)} '
        'smoothY=${smoothRatioY.toStringAsFixed(2)}',
      );

      // ════════════════════════════════════════
      // CLASSIFY GAZE DIRECTION
      //
      // Thresholds tuned for 30-50cm phone distance
      // Adjust if too sensitive or not sensitive enough:
      //   More sensitive  → lower the threshold (e.g. 0.35 → 0.40)
      //   Less sensitive  → raise the threshold (e.g. 0.35 → 0.30)
      // ════════════════════════════════════════

      // Check vertical first — looking down is most common exam cheat
      // (phone in lap, notes on desk)
      if (smoothRatioY > 0.72) {
        return IrisGazeState(
          ratioX: smoothRatioX,
          ratioY: smoothRatioY,
          direction: GazeDirection.down,
          isAvailable: true,
        );
      }

      if (smoothRatioY < 0.28) {
        return IrisGazeState(
          ratioX: smoothRatioX,
          ratioY: smoothRatioY,
          direction: GazeDirection.up,
          isAvailable: true,
        );
      }

      // Check horizontal — looking at neighbor's paper
      if (smoothRatioX < 0.32) {
        return IrisGazeState(
          ratioX: smoothRatioX,
          ratioY: smoothRatioY,
          direction: GazeDirection.left,
          isAvailable: true,
        );
      }

      if (smoothRatioX > 0.68) {
        return IrisGazeState(
          ratioX: smoothRatioX,
          ratioY: smoothRatioY,
          direction: GazeDirection.right,
          isAvailable: true,
        );
      }

      // Iris is centered — student looking forward
      return IrisGazeState(
        ratioX: smoothRatioX,
        ratioY: smoothRatioY,
        direction: GazeDirection.center,
        isAvailable: true,
      );
    } catch (e) {
      debugPrint('[IrisGaze] Error: $e');
      return const IrisGazeState(isAvailable: false);
    }
  }

  // ── Majority vote for smoothing ──────────────────────────────────────────────
  GazeDirection _majorityVote(List<GazeDirection> history) {
    if (history.isEmpty) {
      return GazeDirection.unknown;
    }
    final counts = <GazeDirection, int>{};
    for (final g in history) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ── Device scoring ───────────────────────────────────────────────────────────
  double _scorePhone(Map<String, double> m) {
    double s = 0.0;
    for (final k in [
      'mobile phone',
      'smartphone',
      'cell phone',
      'iphone',
      'android phone',
      'feature phone',
      'telephone',
    ]) {
      s = math.max(s, m[k] ?? 0.0);
    }
    if ((m['television'] ?? 0) > 0.40) {
      s *= 0.15;
    }
    if ((m['computer monitor'] ?? 0) > 0.35) {
      s *= 0.15;
    }
    if ((m['display device'] ?? 0) > 0.35) {
      s *= 0.25;
    }
    if ((m['laptop'] ?? 0) > 0.40) {
      s *= 0.35;
    }
    if ((m['room'] ?? 0) > 0.50) {
      s *= 0.60;
    }
    if ((m['desk'] ?? 0) > 0.50) {
      s *= 0.70;
    }
    return s.clamp(0.0, 1.0);
  }

  double _scoreLaptop(Map<String, double> m) {
    double s = 0.0;
    for (final k in [
      'laptop',
      'laptop computer',
      'notebook',
      'notebook computer',
      'macbook',
      'chromebook',
      'keyboard',
    ]) {
      s = math.max(s, m[k] ?? 0.0);
    }
    if ((m['desk'] ?? 0) > 0.45) {
      s = (s + 0.15).clamp(0.0, 1.0);
    }
    if ((m['office'] ?? 0) > 0.45) {
      s = (s + 0.10).clamp(0.0, 1.0);
    }
    return s.clamp(0.0, 1.0);
  }

  double _scoreMonitor(Map<String, double> m) {
    double s = 0.0;
    for (final k in [
      'computer monitor',
      'monitor',
      'display device',
      'television',
      'television set',
      'flat panel display',
      'flat screen',
      'screen',
    ]) {
      s = math.max(s, m[k] ?? 0.0);
    }
    final hasCtx = (m['desk'] ?? 0) > 0.40 || (m['room'] ?? 0) > 0.45;
    if ((m['television'] ?? 0) > 0 && !hasCtx && s < 0.50) {
      s *= 0.50;
    }
    if ((m['keyboard'] ?? 0) > 0.45) {
      s *= 0.40;
    }
    return s.clamp(0.0, 1.0);
  }

  double _scoreBook(Map<String, double> m) {
    double s = 0.0;
    for (final k in ['book', 'paper', 'document', 'textbook', 'notebook']) {
      s = math.max(s, m[k] ?? 0.0);
    }
    return s.clamp(0.0, 1.0);
  }

  Rect _estimateRect(String label, Rect? face) {
    switch (label) {
      case 'Phone':
        if (face != null) {
          final l = (face.right + 0.02).clamp(0.0, 0.70);
          final t = (face.top - 0.03).clamp(0.0, 0.75);
          return Rect.fromLTWH(l, t, 0.22, 0.32);
        }
        return const Rect.fromLTWH(0.35, 0.15, 0.30, 0.45);
      case 'Laptop':
        if (face != null) {
          final t = (face.bottom + 0.02).clamp(0.0, 0.80);
          return Rect.fromLTWH(0.05, t, 0.90, (0.95 - t).clamp(0.05, 0.50));
        }
        return const Rect.fromLTWH(0.05, 0.45, 0.90, 0.50);
      case 'Monitor':
        return const Rect.fromLTWH(0.02, 0.02, 0.96, 0.70);
      case 'Book':
        if (face != null) {
          final t = (face.bottom + 0.02).clamp(0.0, 0.80);
          return Rect.fromLTWH(0.10, t, 0.80, (0.95 - t).clamp(0.05, 0.45));
        }
        return const Rect.fromLTWH(0.10, 0.45, 0.80, 0.45);
      default:
        return const Rect.fromLTWH(0.05, 0.05, 0.90, 0.90);
    }
  }

  // ── InputImage assembly ──────────────────────────────────────────────────────
  InputImage? _toInputImage(CameraImage img) {
    try {
      if (img.planes.length == 1) {
        return InputImage.fromBytes(
          bytes: img.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(img.width.toDouble(), img.height.toDouble()),
            rotation: _rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: img.planes[0].bytesPerRow,
          ),
        );
      }

      final W = img.width, H = img.height;
      final yRaw = img.planes[0].bytes;
      final yStr = img.planes[0].bytesPerRow;
      final yPacked = Uint8List(W * H);
      for (int r = 0; r < H; r++) {
        yPacked.setRange(r * W, r * W + W, yRaw, r * yStr);
      }

      final uvH = H ~/ 2, uvW = W ~/ 2;
      final uvPacked = Uint8List(uvW * uvH * 2);
      int di = 0;

      if (img.planes.length >= 3) {
        final uR = img.planes[1].bytes, vR = img.planes[2].bytes;
        final uStr = img.planes[1].bytesPerRow;
        final vStr = img.planes[2].bytesPerRow;
        final uStp = img.planes[1].bytesPerPixel ?? 1;
        final vStp = img.planes[2].bytesPerPixel ?? 1;
        for (int r = 0; r < uvH; r++) {
          for (int c = 0; c < uvW; c++) {
            uvPacked[di++] = vR[r * vStr + c * vStp];
            uvPacked[di++] = uR[r * uStr + c * uStp];
          }
        }
      } else {
        final uvR = img.planes[1].bytes;
        final uvStr = img.planes[1].bytesPerRow;
        for (int r = 0; r < uvH; r++) {
          for (int c = 0; c < uvW; c++) {
            final s = r * uvStr + c * 2;
            uvPacked[di++] = uvR[s + 1];
            uvPacked[di++] = uvR[s];
          }
        }
      }

      final nv21 = Uint8List(yPacked.length + uvPacked.length);
      nv21.setAll(0, yPacked);
      nv21.setAll(yPacked.length, uvPacked);

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(W.toDouble(), H.toDouble()),
          rotation: _rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: W,
        ),
      );
    } catch (e) {
      debugPrint('[AiHandler] InputImage failed: $e');
      return null;
    }
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────
  void dispose() {
    _faceDetector?.close();
    _meshDetector?.close();
    _imageLabeler?.close();
    _objectDetector?.close();
    _faceDetector = null;
    _meshDetector = null;
    _imageLabeler = null;
    _objectDetector = null;
    _mlReady = false;
    _mlBusy = false;
    onResult = null;
    debugPrint('[AiHandler] 🛑 Detectors closed');
  }
}
