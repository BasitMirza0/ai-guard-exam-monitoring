import '../services/camera_activity.dart';
import '../services/camera_lifecycle.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import '../services/media_response.dart';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/camera_frame_encoder.dart';
import '../services/camera_platform.dart';

import '../../services/api_service.dart';

class LiveDetectionScreen extends StatefulWidget {
  const LiveDetectionScreen({super.key});

  @override
  State<LiveDetectionScreen> createState() => _LiveDetectionScreenState();
}

class _LiveDetectionScreenState extends State<LiveDetectionScreen>
    with CameraActivity<LiveDetectionScreen> {
  final ApiService _api = ApiService();
  CameraController? _cam;
  bool _camReady = false;
  String? _cameraError;
  bool _frontCam = false;
  int _sensorDeg = 90;

  bool _apiOnline = false;
  bool _detecting = false;
  bool _running = false;
  final _clock = Stopwatch()..start();
  Duration _lastSent = const Duration(seconds: -1);
  int _generation = 0;
  bool _switching = false;
  Future<void> _cameraSync = Future<void>.value();
  Widget? _preview;
  int _frameCount = 0;
  int _totalViols = 0;
  double _inferMs = 0;

  static const _sendInterval = Duration(seconds: 1);

  Uint8List? _annotatedBytes;
  List<dynamic> _detections = [];
  List<dynamic> _violations = [];
  List<Map<String, dynamic>> _violationLog = [];

  @override
  void initState() {
    super.initState();
    _checkHealth();
    _initCamera();
  }

  @override
  void dispose() {
    _running = false;
    _api.close();
    _generation++;
    unawaited(releaseCamera(_cam, pending: _cameraSync));
    super.dispose();
  }

  Future<void> _checkHealth() async {
    final ok = await _api.checkHealth();
    if (mounted) setState(() => _apiOnline = ok);
  }

  Future<void> _initCamera() async {
    try {
      await waitForCameraRelease();
      if (!mounted) return;
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera is available on this device.');
        return;
      }

      final cam =
          _frontCam
              ? cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.front,
                orElse: () => cameras.first,
              )
              : cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.back,
                orElse: () => cameras.first,
              );

      // Read actual sensor orientation
      _sensorDeg = cam.sensorOrientation;

      _cam = CameraController(
        cam,
        ResolutionPreset.low, // 320x240 — fast
        enableAudio: false,
        imageFormatGroup: liveCameraFormat,
      );

      await _cam!.initialize();
      if (!mounted) return;
      _preview = RepaintBoundary(child: CameraPreview(_cam!));
      setState(() => _camReady = true);
      onCameraActivityChanged();
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        setState(
          () =>
              _cameraError =
                  'Unable to open the camera. Check camera permissions and try again.',
        );
      }
    }
  }

  @override
  void onCameraActivityChanged() {
    if (!cameraActive) _generation++;
    _cameraSync = _cameraSync
        .then<void>((_) async {
          final camera = _cam;
          if (!mounted || camera == null || !camera.value.isInitialized) return;
          await syncCameraStream(
            camera,
            enabled: cameraActive && _running,
            onFrame: _onFrame,
          );
        })
        .catchError((Object error) => debugPrint('[Camera] Activity: $error'));
  }

  Future<void> _toggleCamera() async {
    if (_switching || !_camReady) return;
    _switching = true;
    _generation++;
    final camera = _cam;
    setState(() {
      _camReady = false;
      _preview = null;
    });
    await releaseCamera(camera, pending: _cameraSync);
    if (!mounted) return;
    _cam = null;
    _frontCam = !_frontCam;
    await _initCamera();
    _switching = false;
  }

  void _toggleDetection() {
    if (_switching || !_camReady) return;
    _generation++;
    setState(() {
      _running = !_running;
      if (!_running) {
        _annotatedBytes = null;
        _violations = [];
        _detections = [];
      }
    });
    onCameraActivityChanged();
  }

  void _onFrame(CameraImage frame) {
    if (!cameraActive || _detecting || !_apiOnline || !_running) return;
    if (_clock.elapsed - _lastSent < _sendInterval) return;
    _lastSent = _clock.elapsed;
    final generation = _generation;

    if (usesIosCamera) {
      if (frame.format.group != ImageFormatGroup.bgra8888 ||
          frame.planes.length != 1) {
        return;
      }
    } else if (frame.planes.length < 2) {
      return;
    }

    _detecting = true;
    _frameCount++;

    final Map<String, dynamic> pixels =
        usesIosCamera
            ? {
              'w': frame.width,
              'h': frame.height,
              'bgra': Uint8List.fromList(frame.planes.single.bytes),
              'stride': frame.planes.single.bytesPerRow,
            }
            : {
              'w': frame.width,
              'h': frame.height,
              'y': Uint8List.fromList(frame.planes[0].bytes),
              'u': Uint8List.fromList(frame.planes[1].bytes),
              'v': Uint8List.fromList(
                frame.planes.length > 2
                    ? frame.planes[2].bytes
                    : frame.planes[1].bytes,
              ),
              'yStride': frame.planes[0].bytesPerRow,
              'uvStride': frame.planes[1].bytesPerRow,
              'uvPixel': frame.planes[1].bytesPerPixel ?? 1,
              'rotation': _sensorDeg,
            };

    compute(cameraFrameToJpeg, pixels)
        .then<void>((jpeg) async {
          if (jpeg == null ||
              !cameraActive ||
              !_running ||
              generation != _generation) {
            _detecting = false;
            return;
          }
          return _sendToApi(jpeg, generation);
        })
        .catchError((e) {
          debugPrint('YUV error: $e');
          _detecting = false;
        });
  }

  Future<void> _sendToApi(Uint8List jpeg, int generation) async {
    try {
      final result = await _api.detectImageFromBytes(
        jpeg,
        'frame_$_frameCount.jpg',
      );

      if (!cameraActive || !_running || generation != _generation) {
        return;
      }

      Uint8List? annBytes;
      if (result.annotatedImage != null && result.annotatedImage!.isNotEmpty) {
        try {
          annBytes = decodeAnnotatedImage(result.annotatedImage);
        } catch (_) {}
      }

      final newViols = result.violations;
      if (newViols.isNotEmpty) {
        _totalViols += newViols.length;
        for (final v in newViols) {
          _violationLog.insert(0, {
            'violation': v.violation,
            'confidence': v.confidence,
            'time': _now(),
          });
        }
        if (_violationLog.length > 20) {
          _violationLog = _violationLog.take(20).toList();
        }
      }

      setState(() {
        _annotatedBytes = annBytes;
        _detections = result.detections;
        _violations =
            newViols
                .map(
                  (v) => {'violation': v.violation, 'confidence': v.confidence},
                )
                .toList();
        _inferMs = result.inferenceTimeMs;
      });
    } catch (e) {
      debugPrint('API: $e');
    } finally {
      _detecting = false;
    }
  }

  String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
  }

  // How many 90° CCW turns to fix the preview display
  int _previewRotation() {
    switch (_sensorDeg) {
      case 90:
        return 3;
      case 180:
        return 2;
      case 270:
        return 1;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Live AI Detection',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: _apiOnline ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 4),
              Text(
                _apiOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 11,
                  color: _apiOnline ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white70,
                  size: 18,
                ),
                onPressed: _checkHealth,
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final camera = Expanded(
              flex: 6,
              child: RepaintBoundary(child: _buildCamera()),
            );
            final results = Expanded(
              flex: 4,
              child: RepaintBoundary(child: _buildResults()),
            );
            return constraints.maxWidth > constraints.maxHeight &&
                    constraints.maxWidth >= 600
                ? Row(children: [camera, results])
                : Column(children: [camera, results]);
          },
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return Stack(
      children: [
        // ── Live preview with rotation correction ────────────────────────────
        SizedBox.expand(
          child:
              _camReady && _cam != null
                  ? RotatedBox(
                    quarterTurns: _previewRotation(),
                    child: _preview,
                  )
                  : Center(
                    child:
                        _cameraError == null
                            ? const CircularProgressIndicator()
                            : Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _cameraError!,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: () async {
                                      final oldCamera = _cam;
                                      _cam = null;
                                      setState(() => _cameraError = null);
                                      await releaseCamera(
                                        oldCamera,
                                        pending: _cameraSync,
                                      );
                                      if (mounted) await _initCamera();
                                    },
                                    child: const Text('Retry camera'),
                                  ),
                                ],
                              ),
                            ),
                  ),
        ),

        // ── Annotated overlay — same rotation as preview ─────────────────────
        if (_annotatedBytes != null && _running)
          Positioned.fill(
            child: RotatedBox(
              quarterTurns: _previewRotation(),
              child: Image.memory(
                _annotatedBytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: _cam?.value.previewSize?.width.round(),
              ),
            ),
          ),

        // ── HUD top ──────────────────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                _pill('Frame: $_frameCount', Colors.black54, Colors.white),
                const SizedBox(width: 8),
                if (_inferMs > 0)
                  _pill(
                    '${_inferMs.toStringAsFixed(0)}ms',
                    Colors.black54,
                    Colors.greenAccent,
                  ),
                const Spacer(),
                if (_detecting)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Analyzing...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Violation banner ─────────────────────────────────────────────────
        if (_violations.isNotEmpty)
          Positioned(
            bottom: 90,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _violations
                          .map(
                            (v) =>
                                (v['violation'] as String)
                                    .replaceAll('_', ' ')
                                    .toUpperCase(),
                          )
                          .join(' • '),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Controls ─────────────────────────────────────────────────────────
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconBtn(Icons.flip_camera_ios, _toggleCamera, Colors.white24),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: _apiOnline ? _toggleDetection : null,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _running ? Colors.red : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Icon(
                    _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: _running ? Colors.white : Colors.red[700],
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              _iconBtn(
                Icons.refresh_rounded,
                () => setState(() {
                  _annotatedBytes = null;
                  _violations = [];
                  _detections = [];
                  _violationLog = [];
                  _frameCount = 0;
                  _generation++;
                  _totalViols = 0;
                }),
                Colors.white24,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(t, style: TextStyle(color: fg, fontSize: 10)),
  );

  Widget _iconBtn(IconData icon, VoidCallback fn, Color bg) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  Widget _buildResults() {
    return Container(
      color: AppColors.night,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.ink)),
            ),
            child: Row(
              children: [
                _stat('Detections', '${_detections.length}', AppColors.accent),
                const SizedBox(width: 6),
                _stat('Violations', '${_violations.length}', Colors.red),
                const SizedBox(width: 6),
                _stat('Total Alerts', '$_totalViols', Colors.orange),
                const SizedBox(width: 6),
                _stat(
                  'Speed',
                  '${_inferMs.toStringAsFixed(0)}ms',
                  Colors.green,
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!_running && _detections.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _apiOnline
                    ? Icons.play_circle_outline_rounded
                    : Icons.wifi_off_rounded,
                color: Colors.grey[600],
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                _apiOnline
                    ? 'Press ▶ and point camera at a person'
                    : 'API Offline — Start Colab first',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
                textAlign: TextAlign.center,
              ),
              if (!_apiOnline) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _checkHealth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Retry Connection',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  'Current Frame',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child:
                    _detections.isEmpty
                        ? Center(
                          child: Text(
                            'No detections',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        )
                        : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _detections.length,
                          itemBuilder: (_, i) {
                            final d = _detections[i];
                            final name =
                                (d['class_name'] as String? ?? '')
                                    .replaceAll('_', ' ')
                                    .toUpperCase();
                            final conf =
                                ((d['confidence'] as num?) ?? 0).toDouble();
                            return _detTile(
                              name,
                              conf,
                              false, // Raw boxes are not accepted backend violations.
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: AppColors.ink),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  'Alert History',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child:
                    _violationLog.isEmpty
                        ? Center(
                          child: Text(
                            'No alerts yet',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        )
                        : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _violationLog.length,
                          itemBuilder: (_, i) {
                            final v = _violationLog[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (v['violation'] as String)
                                        .replaceAll('_', ' ')
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.red[300],
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        v['time'] as String,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 8,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${((v['confidence'] as num) * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          color: Colors.red[400],
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detTile(String name, double conf, bool isV) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color:
          isV
              ? Colors.red.withValues(alpha: 0.15)
              : Colors.green.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color:
            isV
                ? Colors.red.withValues(alpha: 0.4)
                : Colors.green.withValues(alpha: 0.3),
      ),
    ),
    child: Row(
      children: [
        Icon(
          isV ? Icons.warning_rounded : Icons.check_circle_rounded,
          color: isV ? Colors.red : Colors.green,
          size: 12,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: isV ? Colors.red[300] : Colors.green[300],
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '${(conf * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: isV ? Colors.red : Colors.green,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _stat(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 7)),
        ],
      ),
    ),
  );
}
