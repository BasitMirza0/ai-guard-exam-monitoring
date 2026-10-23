import '../../widgets/exam_instructions.dart';
import '../../services/camera_activity.dart';
import '../../services/frame_processor.dart';
import '../../services/camera_lifecycle.dart';
import '../../services/camera_platform.dart';
import '../../widgets/responsive_body.dart';
import '../../theme/app_theme.dart';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/ai_handler.dart';
import '../../services/exam_monitor.dart';

// ── Violation stage & type ─────────────────────────────────────────────────────
enum _Stage { none, warning, critical }

typedef _VType = ExamWarningType;

// =============================================================================
// CameraScreen
// =============================================================================
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.aiHandler,
    this.cameraProvider,
    this.cameraFactory,
    this.examClock,
  });

  // Optional dependencies allow lifecycle/quiz tests without native hardware.
  final AiHandler? aiHandler;
  final Future<List<CameraDescription>> Function()? cameraProvider;
  final CameraController Function(CameraDescription)? cameraFactory;
  final Stopwatch? examClock;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin, CameraActivity<CameraScreen> {
  // ── Camera ─────────────────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _cameraReady = false;
  String? _cameraError;
  Widget? _cameraPreview;

  // ── AI ─────────────────────────────────────────────────────────────────────
  late final AiHandler _ai = widget.aiHandler ?? AiHandler.session();
  final _frames = FrameProcessor();
  final _monitor = ExamMonitor();
  Future<void> _cameraSync = Future<void>.value();
  List<DetectedObject> _detections = [];

  // ── Exam state ─────────────────────────────────────────────────────────────
  bool _showInstructions = true;
  final ValueNotifier<int> _remaining = ValueNotifier(1800);
  int get _secondsRemaining => _remaining.value;
  late final Stopwatch _examClock = widget.examClock ?? Stopwatch();
  Timer? _examTimer;
  int _violationCount = 0;
  bool _examTerminated = false;
  int _currentQuestion = 0;
  int _correctAnswers = 0;
  int _answeredCount = 0;
  int? _selectedOption;
  bool _answered = false;

  // ── Warning system ─────────────────────────────────────────────────────────
  _Stage _stage = _Stage.none;
  _VType _activeType = _VType.none;
  String _warningTitle = '';
  String _warningDetail = '';
  double _violationProgress = 0.0;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  late AnimationController _warnPulseCtrl;
  late Animation<double> _warnPulseAnim;

  // ── Questions ─────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _questions = [
    {
      'q':
          'Which of the following is considered a violation of academic integrity?',
      'options': [
        'Citing your sources correctly',
        'Using a mobile phone during the test',
        'Completing work independently',
      ],
      'answer': 1,
    },
    {
      'q': 'What is the penalty for plagiarism in most institutions?',
      'options': [
        'A written warning only',
        'Automatic course failure',
        'No penalty if first offence',
      ],
      'answer': 1,
    },
    {
      'q': 'Which behaviour is allowed during a supervised exam?',
      'options': [
        'Communicating with other students',
        'Using approved reference material',
        'Browsing the internet',
      ],
      'answer': 1,
    },
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initCamera();
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    _examClock.stop();
    _remaining.dispose();
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _warnPulseCtrl.dispose();
    _frames.close();
    unawaited(releaseCamera(_camCtrl, pending: _cameraSync));
    unawaited(_ai.dispose());
    super.dispose();
  }

  void _setupAnimations() {
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));

    _warnPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _warnPulseAnim = Tween<double>(
      begin: 0.96,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _warnPulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDecorativeAnimations();
  }

  void _syncDecorativeAnimations() {
    final enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.of(context) &&
        cameraActive &&
        !_showInstructions &&
        !_examTerminated;
    void sync(
      AnimationController controller,
      bool active, {
      bool reverse = false,
    }) {
      if (enabled && active) {
        if (!controller.isAnimating) controller.repeat(reverse: reverse);
      } else {
        controller.stop();
        controller.value = 0;
      }
    }

    sync(_pulseCtrl, _stage != _Stage.none, reverse: true);
    sync(_warnPulseCtrl, _stage != _Stage.none, reverse: true);
  }

  Future<void> _initCamera() async {
    try {
      _ai.onResult = _onAiResult;
      _ai.resetForNewSession();
      await _ai.initModel();
      if (!_ai.isReady) {
        throw StateError(
          'Exam monitoring could not be initialized on this device.',
        );
      }

      await waitForCameraRelease();
      if (!mounted) return;
      final cameras = await (widget.cameraProvider ?? availableCameras)();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera is available on this device.');
        return;
      }

      final chosen = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _ai.setCameraRotation(
        chosen.sensorOrientation,
        chosen.lensDirection == CameraLensDirection.front,
      );

      _camCtrl =
          widget.cameraFactory?.call(chosen) ??
          CameraController(
            chosen,
            ResolutionPreset.medium,
            enableAudio: false,
            imageFormatGroup: examCameraFormat,
          );

      await _camCtrl!.initialize();
      if (!mounted) return;
      _cameraPreview = RepaintBoundary(child: CameraPreview(_camCtrl!));
      if (mounted) setState(() => _cameraReady = true);
      onCameraActivityChanged();
    } catch (e) {
      debugPrint('[Camera] $e');
      final failedCamera = _camCtrl;
      _camCtrl = null;
      await releaseCamera(failedCamera, pending: _cameraSync);
      if (mounted) {
        setState(
          () =>
              _cameraError =
                  e is CameraException &&
                          e.code.toLowerCase().contains('accessdenied')
                      ? 'Allow camera access to start your exam.'
                      : e is StateError
                      ? e.message.toString()
                      : 'Unable to open the camera. Please try again.',
        );
      }
    }
  }

  @override
  void onCameraActivityChanged() {
    if (mounted) _syncDecorativeAnimations();
    _cameraSync = _cameraSync
        .then<void>((_) async {
          final camera = _camCtrl;
          if (!mounted || camera == null || !camera.value.isInitialized) return;
          await syncCameraStream(
            camera,
            enabled: cameraActive && !_examTerminated && !_showInstructions,
            onFrame: _onCameraFrame,
          );
        })
        .catchError((Object error) => debugPrint('[Camera] Activity: $error'));
  }

  void _onCameraFrame(CameraImage image) {
    if (!cameraActive || _showInstructions || _examTerminated) return;
    unawaited(_frames.process(() => _ai.runInferenceMobile(image)));
  }

  // ── AI result handler ───────────────────────────────────────────────────────
  void _onAiResult() {
    if (!cameraActive || _examTerminated || _showInstructions) return;

    if (_ai.isCalibrated && !_examClock.isRunning) _startExamTimer();
    final detections = List<DetectedObject>.from(_ai.detectedObjects);
    final warnings = _monitor.evaluate(
      detections: detections,
      behavior: _ai.behaviorState,
      faceCount: _ai.faceCount,
      isCalibrated: _ai.isCalibrated,
    );
    if (mounted) setState(() => _detections = detections);

    if (warnings.isEmpty) {
      _clearViolation();
      return;
    }

    final active = warnings.first;
    if (active.terminate) {
      _violationCount++;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _shakeCtrl.forward(from: 0);
      }
      _terminate(active.title, active.type);
      return;
    }

    // Keep concurrent activities visible without repeating the same direction
    // reported by both the head-pose and gaze engines.
    final additional =
        warnings
            .map((warning) => warning.title)
            .where((title) => title != active.title)
            .toSet();
    _setStage(
      stage: active.critical ? _Stage.critical : _Stage.warning,
      type: active.type,
      title: active.title,
      detail: [active.detail, ...additional].join('\n'),
      progress: active.progress,
    );
  }

  // ── Stage helpers ───────────────────────────────────────────────────────────
  void _setStage({
    required _Stage stage,
    required _VType type,
    required String title,
    required String detail,
    required double progress,
  }) {
    final wasNone = _stage == _Stage.none;
    if (wasNone &&
        stage != _Stage.none &&
        !MediaQuery.disableAnimationsOf(context)) {
      _shakeCtrl.forward(from: 0);
    }
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _activeType = type;
      _warningTitle = title;
      _warningDetail = detail;
      _violationProgress = progress;
    });
  }

  void _clearViolation() {
    if (_stage == _Stage.none) return;
    if (!mounted) return;
    setState(() {
      _stage = _Stage.none;
      _activeType = _VType.none;
      _warningTitle = '';
      _warningDetail = '';
      _violationProgress = 0.0;
    });
  }

  // ── Terminate exam ──────────────────────────────────────────────────────────
  void _terminate(String reason, _VType type) {
    if (_examTerminated) return;
    setState(() {
      _examTerminated = true;
      onCameraActivityChanged();
      _stage = _Stage.none;
    });
    _examTimer?.cancel();
    _logViolation(reason);
    _showTerminationDialog(reason, type);
  }

  void _showTerminationDialog(String reason, _VType type) {
    final (IconData icon, Color color) = switch (type) {
      _VType.phone => (Icons.phone_android_rounded, const Color(0xFFFF4B4B)),
      _VType.device => (Icons.devices_rounded, const Color(0xFFFF4B4B)),
      _VType.noFace => (
        Icons.face_retouching_off_rounded,
        const Color(0xFFF59E0B),
      ),
      _VType.multiPerson => (Icons.group_rounded, const Color(0xFFEF4444)),
      _VType.lookingAway => (
        Icons.visibility_off_rounded,
        const Color(0xFFFF4B4B),
      ),
      _VType.headTurn => (
        Icons.do_not_disturb_alt_rounded,
        const Color(0xFFFF4B4B),
      ),
      _VType.none => (Icons.gavel_rounded, const Color(0xFFFF4B4B)),
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            title: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 40),
                ),
                const SizedBox(height: 14),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'EXAM TERMINATED',
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _statBadge(
                          'Violations',
                          '$_violationCount',
                          const Color(0xFFFF4B4B),
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: AppColors.border,
                        ),
                        _statBadge(
                          'Time Left',
                          '${_secondsRemaining ~/ 60}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                          AppColors.primary,
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: AppColors.border,
                        ),
                        _statBadge(
                          'Question',
                          '${_currentQuestion + 1}/${_questions.length}',
                          const Color(0xFF22C55E),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4B4B).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFF4B4B).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFFFF4B4B),
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This session was stopped for review. Incident saving requires an authenticated connection; this observation is not proof of misconduct.',
                            style: TextStyle(
                              color: const Color(0xFFFF4B4B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'RETURN TO DASHBOARD',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _logViolation(String reason) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final behavior = _ai.behaviorState;
      final iris = _ai.irisGazeState;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('violations').add({
        'studentId': user.uid,
        'studentEmail': user.email ?? '',
        'reason': reason,
        'violationCount': _violationCount,
        'attentionScore': behavior.attentionScore,
        'gazeDirection': behavior.gazeDirection.name,
        'headPose': behavior.headPose.name,
        'eyesClosed': behavior.eyesClosed,
        'irisDirection': iris.direction.name,
        'irisAvailable': iris.isAvailable,
        'faceMeshSupported': _ai.supportsFaceMesh,
        'questionNumber': _currentQuestion + 1,
        'timeRemaining': _secondsRemaining,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Firestore] ❌ $e');
    }
  }

  void _startExamTimer() {
    _examTimer?.cancel();
    _examClock.start();
    _examTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _secondsRemaining > 0 && !_examTerminated) {
        _remaining.value = (1800 - _examClock.elapsed.inSeconds).clamp(0, 1800);
        if (_remaining.value == 0) _finishExam(timedOut: true);
      }
    });
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    _syncDecorativeAnimations();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Only mount one preview: instructions or the exam, never both.
            if (!_showInstructions)
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxHeight < 520 ||
                      constraints.maxWidth < 320 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.4;
                  if (compact) {
                    return Stack(
                      children: [
                        SingleChildScrollView(
                          child: Column(
                            children: [
                              ValueListenableBuilder<int>(
                                valueListenable: _remaining,
                                builder:
                                    (_, value, child) => _buildProctoringBar(),
                              ),
                              if (!_ai.isCalibrated && !_showInstructions)
                                _buildCalibrationBanner(),
                              _buildQuestionCard(embedded: true),
                              _buildBottomBar(),
                            ],
                          ),
                        ),
                        if (_stage != _Stage.none &&
                            !_examTerminated &&
                            _ai.isCalibrated &&
                            !_showInstructions)
                          Positioned.fill(child: _buildViolationOverlay()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: _remaining,
                        builder: (_, value, child) => _buildProctoringBar(),
                      ),
                      if (!_ai.isCalibrated && !_showInstructions)
                        _buildCalibrationBanner(),
                      Expanded(
                        child: Stack(
                          children: [
                            _buildQuestionCard(),
                            // Duolingo-style violation overlay
                            if (_stage != _Stage.none &&
                                !_examTerminated &&
                                _ai.isCalibrated &&
                                !_showInstructions)
                              _buildViolationOverlay(),
                          ],
                        ),
                      ),
                      _buildBottomBar(),
                    ],
                  );
                },
              ),

            // ── Pre-exam instructions (full screen) ──
            if (_showInstructions) _buildInstructionsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsOverlay() => Positioned.fill(
    child: ExamInstructions(
      error: _cameraError,
      monitoringNotice: _ai.monitoringNotice,
      onRetry: () async {
        final oldCamera = _camCtrl;
        _camCtrl = null;
        setState(() {
          _cameraError = null;
          _cameraReady = false;
          _cameraPreview = null;
        });
        await releaseCamera(oldCamera, pending: _cameraSync);
        if (mounted) await _initCamera();
      },
      onBegin:
          !_cameraReady || _cameraError != null
              ? null
              : () {
                setState(() => _showInstructions = false);
                onCameraActivityChanged();
              },
    ),
  );

  // ── CALIBRATION BANNER ─────────────────────────────────────────────────────
  Widget _buildCalibrationBanner() {
    final p = _ai.calibProgress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Calibrating — look straight at the camera  ($p%)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: p / 100.0,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── PROCTORING BAR ─────────────────────────────────────────────────────────
  Widget _buildProctoringBar() {
    final min = _secondsRemaining ~/ 60;
    final sec = (_secondsRemaining % 60).toString().padLeft(2, '0');
    final urgent = _secondsRemaining < 60;
    final isAlert = _stage != _Stage.none;
    final camBorder =
        isAlert
            ? (_stage == _Stage.critical
                ? const Color(0xFFFF4B4B)
                : const Color(0xFFF59E0B))
            : const Color(0xFF22C55E);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: AdaptiveRow(
          minItemWidth: 95,
          children: [
            // Question progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    children: [
                      Text(
                        'Q${_currentQuestion + 1}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        ' of ${_questions.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (_currentQuestion + 1) / _questions.length,
                      minHeight: 5,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Attention indicator (clean, no frame counts)
                  _buildAttentionChip(),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Timer pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: urgent ? const Color(0xFFFF4B4B) : AppColors.primary,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: (urgent
                            ? const Color(0xFFFF4B4B)
                            : AppColors.primary)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$min:$sec',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Camera feed bubble
            AnimatedBuilder(
              animation: _pulseAnim,
              builder:
                  (_, child) => Transform.scale(
                    scale: isAlert ? _pulseAnim.value : 1.0,
                    child: child,
                  ),
              child: Container(
                width: 72,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: camBorder, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: camBorder.withValues(alpha: isAlert ? 0.55 : 0.2),
                      blurRadius: isAlert ? 16 : 6,
                      spreadRadius: isAlert ? 2 : 0,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreview(),
                      CustomPaint(
                        painter: _BBoxPainter(
                          _detections,
                          compact: true,
                          controller: _camCtrl,
                        ),
                      ),
                      // Scan line when all good
                      if (!isAlert && _cameraReady)
                        AnimatedBuilder(
                          animation: const AlwaysStoppedAnimation<double>(0.5),
                          builder:
                              (_, __) => Positioned(
                                top: 45,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 1.5,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        camBorder.withValues(alpha: 0.8),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      CustomPaint(painter: _CornerPainter(camBorder)),
                      // LIVE / ALERT label
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.75),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: camBorder,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: camBorder.withValues(alpha: 0.9),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isAlert ? 'ALERT' : 'LIVE',
                                style: TextStyle(
                                  color: camBorder,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttentionChip() {
    if (!_ai.isCalibrated || _showInstructions) {
      return const SizedBox(height: 14);
    }
    final score = _ai.behaviorState.attentionScore;
    final (Color chipColor, String label) =
        score >= 80
            ? (const Color(0xFF22C55E), 'Attentive')
            : score >= 60
            ? (const Color(0xFFF59E0B), 'Distracted')
            : (const Color(0xFFFF4B4B), 'At Risk');

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: chipColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$score%',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    if (!_cameraReady || _camCtrl == null) {
      return Container(
        color: AppColors.night,
        child: const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.onNight,
            ),
          ),
        ),
      );
    }
    return _cameraPreview!;
  }

  // ── VIOLATION OVERLAY (Duolingo-style) ────────────────────────────────────
  Widget _buildViolationOverlay() {
    final isCrit = _stage == _Stage.critical;
    final color = isCrit ? const Color(0xFFFF4B4B) : const Color(0xFFF59E0B);
    final bgAlpha = isCrit ? 0.82 : 0.72;

    final icon = switch (_activeType) {
      _VType.lookingAway => Icons.visibility_off_rounded,
      _VType.headTurn => Icons.face_retouching_off_rounded,
      _VType.noFace => Icons.face_retouching_off_rounded,
      _VType.multiPerson => Icons.group_rounded,
      _VType.phone => Icons.phone_android_rounded,
      _VType.device => Icons.devices_rounded,
      _VType.none => Icons.warning_amber_rounded,
    };

    return AnimatedBuilder(
      animation: _warnPulseAnim,
      builder: (_, child) {
        return Container(
          color: Colors.black.withValues(alpha: bgAlpha),
          child: Center(
            child: SingleChildScrollView(
              child: Transform.scale(
                scale: isCrit ? _warnPulseAnim.value : 1.0,
                child: child,
              ),
            ),
          ),
        );
      },
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder:
            (_, child) => Transform.translate(
              offset: Offset(
                10 *
                    (0.5 - _shakeAnim.value).abs() *
                    (_shakeAnim.value > 0.5 ? 1 : -1),
                0,
              ),
              child: child,
            ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 8,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 40),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                _warningTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),

              // Detail
              Text(
                _warningDetail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Progress bar toward termination
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isCrit ? 'Terminating soon...' : 'Correct to continue',
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isCrit ? 'CRITICAL' : 'WARNING',
                          style: TextStyle(
                            fontSize: 9,
                            color: color,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _violationProgress,
                      minHeight: 9,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),

              // Violation count
              if (_violationCount > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4B4B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_violationCount warning${_violationCount == 1 ? '' : 's'} recorded',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFFFF4B4B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── QUESTION CARD ─────────────────────────────────────────────────────────
  Object? _questionKey;
  Widget? _questionWidget;
  Widget _buildQuestionCard({bool embedded = false}) {
    final key = (
      _currentQuestion,
      _selectedOption,
      _answered,
      _examTerminated,
      embedded,
    );
    if (_questionKey != key) {
      _questionKey = key;
      _questionWidget = RepaintBoundary(
        child: _createQuestionCard(embedded: embedded),
      );
    }
    return _questionWidget!;
  }

  Widget _createQuestionCard({bool embedded = false}) {
    final q = _questions[_currentQuestion];
    return SingleChildScrollView(
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'QUESTION ${_currentQuestion + 1}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              q['q'] as String,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...(q['options'] as List<String>).asMap().entries.map(
            (e) => _buildOption(e.key, e.value, q['answer'] as int),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(int idx, String text, int correct) {
    Color bg = Colors.white;
    Color border = AppColors.border;
    Color fg = AppColors.ink;
    Widget? trailing;
    Gradient? gradient;

    if (_answered) {
      if (idx == correct) {
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFF22C55E);
        fg = const Color(0xFF15803D);
        trailing = Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
        );
      } else if (idx == _selectedOption) {
        bg = const Color(0xFFFFF5F5);
        border = const Color(0xFFFF4B4B);
        fg = const Color(0xFFDC2626);
        trailing = Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFFF4B4B),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
        );
      }
    } else if (idx == _selectedOption) {
      bg = AppColors.subtle;
      border = AppColors.primary;
      fg = AppColors.primary;
      gradient = const LinearGradient(
        colors: [AppColors.subtle, AppColors.primarySoft],
      );
    }

    return GestureDetector(
      onTap:
          (_answered || _examTerminated)
              ? null
              : () => setState(() => _selectedOption = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: gradient == null ? bg : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: border,
            width: idx == _selectedOption && !_answered ? 2.0 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color:
                    idx == _selectedOption && !_answered
                        ? AppColors.primary
                        : _answered && idx == correct
                        ? const Color(0xFF22C55E)
                        : _answered && idx == _selectedOption
                        ? const Color(0xFFFF4B4B)
                        : AppColors.border,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + idx),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color:
                        (idx == _selectedOption && !_answered) ||
                                (_answered &&
                                    (idx == correct || idx == _selectedOption))
                            ? Colors.white
                            : AppColors.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14.5,
                  color: fg,
                  fontWeight:
                      idx == _selectedOption
                          ? FontWeight.w600
                          : FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  // ── BOTTOM BAR ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final isLast = _currentQuestion == _questions.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: AdaptiveRow(
        children: [
          // Violation badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  _violationCount > 0
                      ? const Color(0xFFFF4B4B).withValues(alpha: 0.1)
                      : AppColors.subtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    _violationCount > 0
                        ? const Color(0xFFFF4B4B).withValues(alpha: 0.3)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _violationCount > 0
                      ? Icons.shield_rounded
                      : Icons.shield_outlined,
                  size: 15,
                  color:
                      _violationCount > 0
                          ? const Color(0xFFFF4B4B)
                          : AppColors.muted,
                ),
                const SizedBox(width: 5),
                Text(
                  '$_violationCount ${_violationCount == 1 ? 'warning' : 'warnings'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color:
                        _violationCount > 0
                            ? const Color(0xFFFF4B4B)
                            : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                _answered
                    ? ElevatedButton(
                      onPressed:
                          _examTerminated
                              ? null
                              : (isLast ? _finishExam : _nextQuestion),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              isLast ? 'Finish exam' : 'Next question',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            isLast
                                ? Icons.check_circle_rounded
                                : Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ],
                      ),
                    )
                    : ElevatedButton(
                      onPressed:
                          (_selectedOption == null ||
                                  _examTerminated ||
                                  !_ai.isCalibrated)
                              ? null
                              : _checkAnswer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.border,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _examTerminated
                                ? Icons.lock_rounded
                                : Icons.check_rounded,
                            color:
                                _examTerminated
                                    ? AppColors.muted
                                    : Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _examTerminated
                                  ? 'Exam terminated'
                                  : 'Check answer',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    _examTerminated
                                        ? AppColors.muted
                                        : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  void _checkAnswer() {
    if (_selectedOption == null ||
        _answered ||
        _examTerminated ||
        !_ai.isCalibrated) {
      return;
    }
    _answeredCount++;
    if (_selectedOption == _questions[_currentQuestion]['answer']) {
      _correctAnswers++;
    }
    setState(() => _answered = true);
  }

  void _finishExam({bool timedOut = false}) {
    if (!mounted || _examTerminated) return;
    setState(() {
      _examTerminated = true;
      _stage = _Stage.none;
    });
    _examTimer?.cancel();
    _examClock.stop();
    onCameraActivityChanged();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text(timedOut ? 'Time is up' : 'Exam completed'),
              content: Text(
                'Answered $_answeredCount of ${_questions.length} questions.\n'
                'Correct answers: $_correctAnswers of ${_questions.length}.\n\n'
                'This demonstration result is shown locally and is not an official grade.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Return to dashboard'),
                ),
              ],
            ),
          ),
    );
  }

  void _nextQuestion() {
    if (_currentQuestion < _questions.length - 1) {
      setState(() {
        _currentQuestion++;
        _selectedOption = null;
        _answered = false;
      });
    }
  }
}

// =============================================================================
// Corner painter
// =============================================================================
class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const double len = 9.0, m = 5.0;
    final p =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(m, m), Offset(m + len, m), p);
    canvas.drawLine(Offset(m, m), Offset(m, m + len), p);
    canvas.drawLine(
      Offset(size.width - m, m),
      Offset(size.width - m - len, m),
      p,
    );
    canvas.drawLine(
      Offset(size.width - m, m),
      Offset(size.width - m, m + len),
      p,
    );
    canvas.drawLine(
      Offset(m, size.height - m),
      Offset(m + len, size.height - m),
      p,
    );
    canvas.drawLine(
      Offset(m, size.height - m),
      Offset(m, size.height - m - len),
      p,
    );
    canvas.drawLine(
      Offset(size.width - m, size.height - m),
      Offset(size.width - m - len, size.height - m),
      p,
    );
    canvas.drawLine(
      Offset(size.width - m, size.height - m),
      Offset(size.width - m, size.height - m - len),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter o) => o.color != color;
}

// =============================================================================
// Bounding box painter
// =============================================================================
class _BBoxPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final bool compact;
  final CameraController? controller;

  _BBoxPainter(this.detections, {this.compact = false, this.controller});

  static const Map<String, Color> _clr = {
    'Person': Color(0xFF22C55E),
    'Phone': Color(0xFFFF4B4B),
    'Laptop': Color(0xFFF59E0B),
    'Monitor': Color(0xFFEF4444),
    'Book': Color(0xFFF97316),
    'Device': Color(0xFFFF4B4B),
  };

  @override
  void paint(Canvas canvas, Size widgetSize) {
    if (detections.isEmpty || controller == null) return;
    final previewSize = controller!.value.previewSize;
    if (previewSize == null) return;

    final double previewAR = previewSize.height / previewSize.width;
    final double widgetAR = widgetSize.width / widgetSize.height;

    Rect imageRect;
    if (previewAR < widgetAR) {
      final double scaledH = widgetSize.width / previewAR;
      final double dy = (scaledH - widgetSize.height) / 2;
      imageRect = Rect.fromLTWH(0, -dy, widgetSize.width, scaledH);
    } else {
      final double scaledW = widgetSize.height * previewAR;
      final double dx = (scaledW - widgetSize.width) / 2;
      imageRect = Rect.fromLTWH(-dx, 0, scaledW, widgetSize.height);
    }

    for (final obj in detections) {
      final color = _clr[obj.label] ?? const Color(0xFFFF4B4B);
      final double l = imageRect.left + obj.rect.left * imageRect.width;
      final double t = imageRect.top + obj.rect.top * imageRect.height;
      final double r = l + obj.rect.width * imageRect.width;
      final double b = t + obj.rect.height * imageRect.height;

      final screenRect = Rect.fromLTRB(
        l.clamp(0.0, widgetSize.width),
        t.clamp(0.0, widgetSize.height),
        r.clamp(0.0, widgetSize.width),
        b.clamp(0.0, widgetSize.height),
      );
      if (screenRect.width < 6 || screenRect.height < 6) continue;

      canvas.drawRect(
        screenRect,
        Paint()
          ..color = color.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        screenRect,
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 1.8 : 2.5,
      );

      _corners(canvas, screenRect, color, compact ? 7.0 : 12.0);
      _label(canvas, screenRect, obj, color, widgetSize);
    }
  }

  void _corners(Canvas canvas, Rect r, Color c, double len) {
    final p =
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 2.0 : 3.0
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(r.topLeft, r.topLeft.translate(len, 0), p);
    canvas.drawLine(r.topLeft, r.topLeft.translate(0, len), p);
    canvas.drawLine(r.topRight, r.topRight.translate(-len, 0), p);
    canvas.drawLine(r.topRight, r.topRight.translate(0, len), p);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(len, 0), p);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(0, -len), p);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(-len, 0), p);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(0, -len), p);
  }

  void _label(
    Canvas canvas,
    Rect rect,
    DetectedObject obj,
    Color color,
    Size size,
  ) {
    final text = '${obj.label} ${(obj.confidence * 100).toStringAsFixed(0)}%';
    final fs = compact ? 7.0 : 10.0;
    final padH = compact ? 3.0 : 6.0;
    final padV = compact ? 2.0 : 3.0;
    final rad = compact ? 3.0 : 5.0;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fs,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    final pw = tp.width + padH * 2;
    final ph = tp.height + padV * 2;
    double px = rect.left, py = rect.top - ph - 2;
    if (py < 0) py = rect.top + 2;
    if (px + pw > size.width) px = size.width - pw;
    if (px < 0) px = 0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(px + 1, py + 1, pw, ph),
        Radius.circular(rad),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(px, py, pw, ph),
        Radius.circular(rad),
      ),
      Paint()..color = color,
    );
    tp.paint(canvas, Offset(px + padH, py + padV));
  }

  @override
  bool shouldRepaint(covariant _BBoxPainter o) =>
      o.detections != detections ||
      o.compact != compact ||
      o.controller != controller;
}
