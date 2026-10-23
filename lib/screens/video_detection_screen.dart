import 'package:flutter/foundation.dart' show kIsWeb;
import '../widgets/workspace_components.dart';
import '../widgets/responsive_body.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import 'live_detection_screen.dart';
import '../config/api_config.dart';
import '../services/video_preview.dart';
import '../services/camera_activity.dart';

class VideoDetectionScreen extends StatefulWidget {
  const VideoDetectionScreen({super.key, this.apiService, this.imagePicker});
  final ApiService? apiService;
  final ImagePicker? imagePicker;

  @override
  State<VideoDetectionScreen> createState() => _VideoDetectionScreenState();
}

class _VideoDetectionScreenState extends State<VideoDetectionScreen>
    with CameraActivity<VideoDetectionScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  bool _isPicking = false;
  bool _checkingHealth = false;
  int _generation = 0;
  String? _error;
  bool _wasPlaying = false;
  XFile? _videoSource;
  String? _videoFileName;
  bool _isLoading = false;
  bool _apiConnected = false;
  Map<String, dynamic>? _result;
  String _progressMsg = "Uploading video...";
  String _progressPct = "0%";
  bool _isFullscreen = false;

  VideoPlayerController? _controller;
  bool _videoReady = false;

  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  double _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return 0;
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  @override
  void dispose() {
    _generation++;
    _api.close();
    _controller?.dispose();
    // Restore platform UI only if this screen changed it.
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  @override
  void onCameraActivityChanged() {
    if (!cameraActive) _controller?.pause();
  }

  Future<void> _checkHealth() async {
    if (_checkingHealth) return;
    setState(() => _checkingHealth = true);
    final ok = await _api.checkHealth();
    if (!mounted) return;
    setState(() {
      _apiConnected = ok;
      _checkingHealth = false;
    });
  }

  void _disposePlayer() {
    final old = _controller;
    _controller = null;
    _videoReady = false;
    if (old != null) unawaited(old.dispose());
  }

  Future<void> _loadPlayer(VideoPlayerController player, int generation) async {
    _controller = player;
    try {
      await player.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      await player.setLooping(false);
      if (!mounted || generation != _generation) return;
      player.addListener(() {
        if (!mounted || generation != _generation) return;
        if (_wasPlaying != player.value.isPlaying || player.value.hasError) {
          setState(() {
            _wasPlaying = player.value.isPlaying;
            if (player.value.hasError) {
              _error = 'Video playback failed. Check the connection and retry.';
            }
          });
        }
      });
      setState(() => _videoReady = true);
    } catch (_) {
      if (mounted && generation == _generation) _disposePlayer();
      rethrow;
    }
  }

  Future<void> _pickVideo() async {
    if (_isLoading || _isPicking) return;
    setState(() => _isPicking = true);
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      final size = await video.length();
      if (!mounted) return;
      if (size == 0 || size > ApiConfig.maxVideoBytes) {
        throw const ApiException('Choose a video smaller than 250 MB.');
      }
      final generation = ++_generation;
      _disposePlayer();
      setState(() {
        _videoSource = video;
        _videoFileName = video.name;
        _result = null;
        _error = null;
      });
      try {
        await _loadPlayer(videoPreview(video.path), generation);
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(
            () =>
                _error =
                    'Preview unavailable for this format. You can still analyze the selected video.',
          );
        }
      }
    } catch (e) {
      _snack(
        e is ApiException
            ? e.message
            : 'Could not select this video. Please try again.',
        Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _detect() async {
    if (_isLoading || _isPicking || _videoSource == null) return;
    final video = _videoSource!;
    final generation = ++_generation;
    _disposePlayer();
    setState(() {
      _isLoading = true;
      _result = null;
      _error = null;
      _progressMsg = 'Uploading video...';
      _progressPct = '0%';
    });
    try {
      final jobId = await _api.submitVideoJob(
        kIsWeb ? await video.readAsBytes() : null,
        _videoFileName ?? 'video.mp4',
        path: kIsWeb ? null : video.path,
      );
      if (!mounted || generation != _generation) return;
      final result = await _api.waitForVideoJob(
        jobId,
        onProgress: (status) {
          if (!mounted || generation != _generation) return;
          final raw = status['progress'];
          final progress =
              raw is num ? raw.toDouble() : double.tryParse('$raw');
          setState(() {
            _progressMsg =
                status['message']?.toString() ?? 'Processing video...';
            if (progress != null && progress.isFinite) {
              _progressPct = '${progress.clamp(0, 100).toStringAsFixed(0)}%';
            }
          });
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() => _result = result);
      await _loadPlayer(
        VideoPlayerController.networkUrl(
          Uri.parse(_api.getVideoUrl(jobId)),
          httpHeaders: ApiConfig.headers,
        ),
        generation,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(
        () =>
            _error =
                e is ApiException
                    ? e.message
                    : 'Unable to load the video result. Check the service and try again.',
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleFullscreen() {
    _isFullscreen ? _exitFullscreen() : _enterFullscreen();
  }

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(child: _buildVideoPlayer()),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(
                  Icons.fullscreen_exit_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: _exitFullscreen,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analysis tools'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _checkHealth,
            tooltip: 'Refresh connection',
          ),
        ],
      ),
      body: ResponsiveBody(
        maxWidth: 800,
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AnalysisHeader(
                title: 'Video analysis',
                subtitle:
                    'Review a recorded session and explore the moments that need attention.',
                icon: Icons.video_library_outlined,
              ),
              ConnectionStatus(
                online: _apiConnected,
                checking: _checkingHealth,
                onRetry: _checkHealth,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.ink),
                  ),
                ),
              const SizedBox(height: 20),
              WorkspaceAction(
                title: 'Use live camera instead',
                description: 'Analyze a camera feed in real time.',
                icon: Icons.videocam_outlined,
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveDetectionScreen(),
                      ),
                    ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Recorded video',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              // ── Video player box ───────────────────────────────────────
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildVideoPlayer(),
                ),
              ),
              const SizedBox(height: 12),

              // ── Two buttons: Gallery + Analyze ─────────────────────────
              AdaptiveRow(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || _isPicking ? null : _pickVideo,
                      icon: const Icon(Icons.video_library_outlined, size: 18),
                      label: Text(
                        "Select Video",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _isLoading || _isPicking || _videoSource == null
                              ? null
                              : _detect,
                      icon: Icon(
                        _isLoading
                            ? Icons.hourglass_top_rounded
                            : Icons.analytics_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _isLoading ? "Processing..." : "Analyze",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.border,
                        disabledForegroundColor: AppColors.muted,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_isLoading) _buildLoadingCard(),

              if (_result != null && !_isLoading) ...[
                const SizedBox(height: 4),
                _buildSummaryCard(),
                const SizedBox(height: 12),
                if (_mapList(_result!['person_risk_summary']).isNotEmpty) ...[
                  _buildRiskCard(),
                  const SizedBox(height: 12),
                ],
                if (_number(_result!['total_violations']) > 0)
                  _buildTimeline()
                else
                  _buildAllClearCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Video Player ──────────────────────────────────────────────────────────
  Widget _buildVideoPlayer() {
    if (!_videoReady || _controller == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _videoSource != null
                  ? Icons.video_file_rounded
                  : Icons.video_library_outlined,
              size: 56,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              _videoSource != null
                  ? "Press Analyze to process"
                  : "Select a video to begin",
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF8CB59B),
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.replay_10_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () {
                        final pos =
                            _controller!.value.position -
                            const Duration(seconds: 10);
                        _controller!.seekTo(
                          pos < Duration.zero ? Duration.zero : pos,
                        );
                      },
                    ),
                    GestureDetector(
                      onTap:
                          () => setState(() {
                            _controller!.value.isPlaying
                                ? _controller!.pause()
                                : _controller!.play();
                          }),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () {
                        final pos =
                            _controller!.value.position +
                            const Duration(seconds: 10);
                        final end = _controller!.value.duration;
                        _controller!.seekTo(pos > end ? end : pos);
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _isFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Loading Card ──────────────────────────────────────────────────────────
  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            "Analyzing video",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _progressMsg,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _progressPct,
            style: TextStyle(
              fontSize: 28,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Reviewing frames for potential exam violations.",
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  // ── Summary Card ──────────────────────────────────────────────────────────
  Widget _buildSummaryCard() {
    final viols = _number(_result!['total_violations']);
    final hasV = _result!['violations_found'] == true || viols > 0;
    final dur = _number(_result!['video_duration_seconds']);
    final frames = _number(_result!['total_frames']);
    final rawUnique = _result!['unique_violations'];
    final unique = rawUnique is List ? rawUnique : [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            hasV
                ? Colors.red.withValues(alpha: 0.06)
                : Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hasV ? Colors.red : Colors.green, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasV ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                color: hasV ? Colors.red : Colors.green,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasV ? "Potential violations" : "No violations found",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: hasV ? Colors.red[800] : Colors.green[800],
                      ),
                    ),
                    Text(
                      "$viols event(s) in ${dur}s",
                      style: TextStyle(
                        fontSize: 11,
                        color: hasV ? Colors.red[400] : Colors.green[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statBox("Duration", "${dur}s", AppColors.accent),
              ),
              const SizedBox(width: 8),
              Expanded(child: _statBox("Frames", "$frames", AppColors.accent)),
              const SizedBox(width: 8),
              Expanded(child: _statBox("Violations", "$viols", Colors.red)),
            ],
          ),
          if (unique.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  unique
                      .map(
                        (v) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            v.toString().replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red[800],
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
          if (_videoReady) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Press ▶ to play annotated video",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Risk Card ─────────────────────────────────────────────────────────────
  Widget _buildRiskCard() {
    final persons = _mapList(_result!['person_risk_summary']);
    if (persons.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Student Risk Summary",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.night,
            ),
          ),
          const SizedBox(height: 12),
          ...persons.map((p) {
            final risk = p['risk_level']?.toString() ?? 'LOW';
            final pct = _number(p['risk_pct']).clamp(0, 100);
            final sid = p['track_id']?.toString() ?? 'S?';
            final color =
                risk == 'HIGH'
                    ? Colors.red
                    : risk == 'MEDIUM'
                    ? Colors.orange
                    : Colors.green;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Text(
                          sid,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sid,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          risk,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Risk score",
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(
                        "$pct%",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Violations Timeline ───────────────────────────────────────────────────
  Widget _buildTimeline() {
    final violations = _mapList(_result!['all_violations']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Violations Timeline",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.night,
                ),
              ),
              Text(
                "${violations.length} total",
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Tap to seek video to that moment",
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
          const SizedBox(height: 12),
          ...violations.take(30).map((v) {
            final ts = _number(v['timestamp']);
            final sid = v['track_id'];
            return GestureDetector(
              onTap: () {
                if (_controller != null) {
                  _controller!.seekTo(
                    Duration(milliseconds: (ts.toDouble() * 1000).toInt()),
                  );
                  _controller!.play();
                  setState(() {});
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red[100]!),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "${ts}s",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v['violation']
                                .toString()
                                .replaceAll('_', ' ')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          if (sid != null)
                            Text(
                              "Student S$sid",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${(_number(v['confidence']) * 100).clamp(0, 100).toStringAsFixed(0)}%",
                        style: TextStyle(
                          color: Colors.red[800],
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.touch_app_rounded,
                      size: 13,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            );
          }),
          if (violations.length > 30)
            Text(
              "+ ${violations.length - 30} more...",
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }

  // ── All Clear ─────────────────────────────────────────────────────────────
  Widget _buildAllClearCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF22C55E),
            size: 44,
          ),
          const SizedBox(height: 8),
          Text(
            "All Clear!",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: Colors.green[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "No cheating detected in this video.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.green[600]),
          ),
        ],
      ),
    );
  }

  // ── Stat Box ──────────────────────────────────────────────────────────────
  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
