import '../widgets/workspace_components.dart';
import '../widgets/responsive_body.dart';
import '../theme/app_theme.dart';
import '../config/api_config.dart';
import '../services/media_response.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../models/detection_result.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key, this.apiService, this.imagePicker});
  final ApiService? apiService;
  final ImagePicker? imagePicker;

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  Uint8List? _imageBytes;
  String? _imageFileName;
  bool _isLoading = false;
  bool _isCheckingHealth = false;
  bool _apiConnected = false;
  DetectionResult? _result;
  Uint8List? _annotatedImage;

  late final ApiService _api = widget.apiService ?? ApiService();
  int _selection = 0;

  @override
  void dispose() {
    _selection++;
    _api.close();
    super.dispose();
  }

  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  // ── Health Check ──────────────────────────────────────────────────────────
  Future<void> _checkHealth() async {
    if (_isCheckingHealth) return;
    if (mounted) setState(() => _isCheckingHealth = true);
    try {
      final ok = await _api.checkHealth();
      if (mounted) {
        setState(() {
          _apiConnected = ok == true;
          _isCheckingHealth = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiConnected = false;
          _isCheckingHealth = false;
        });
      }
    }
  }

  Future<void> _pickImage() => _chooseImage(ImageSource.gallery);

  Future<void> _captureImage() =>
      _chooseImage(kIsWeb ? ImageSource.gallery : ImageSource.camera);

  Future<void> _chooseImage(ImageSource source) async {
    if (_isLoading || _isPicking) return;
    setState(() => _isPicking = true);
    final selection = ++_selection;
    try {
      final img = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (img == null) return;
      if (await img.length() > ApiConfig.maxImageBytes) {
        throw const ApiException('Choose an image smaller than 20 MB.');
      }
      final bytes = await img.readAsBytes();
      if (!mounted || selection != _selection) return;
      setState(() {
        _imageBytes = bytes;
        _imageFileName = img.name;
        _result = null;
        _annotatedImage = null;
      });
    } catch (error) {
      _snack(
        error is ApiException
            ? error.message
            : 'Could not select this image. Check permissions and try again.',
        Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  // ── Detect ────────────────────────────────────────────────────────────────
  Future<void> _detect() async {
    if (_isLoading || _isPicking) return;
    if (_imageBytes == null) {
      _snack("Please select an image first!", Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
      _result = null;
      _annotatedImage = null;
    });

    try {
      final result = await _api.detectImageFromBytes(
        _imageBytes!,
        _imageFileName ?? 'image.jpg',
      );

      final annotated = decodeAnnotatedImage(result.annotatedImage);
      if (!mounted) return;
      setState(() {
        _result = result;
        _annotatedImage = annotated;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _snack("Error: $e", Colors.red);
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  void _reset() {
    if (_isLoading || _isPicking) return;
    _selection++;
    setState(() {
      _imageBytes = null;
      _imageFileName = null;
      _result = null;
      _annotatedImage = null;
    });
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analysis tools'),
        actions: [
          if (_imageBytes != null || _result != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _isLoading || _isPicking ? null : _reset,
              tooltip: 'Reset image',
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
                title: 'Image analysis',
                subtitle:
                    'Upload a photo or take a picture to review potential exam violations.',
                icon: Icons.image_outlined,
              ),
              ConnectionStatus(
                online: _apiConnected,
                checking: _isCheckingHealth,
                onRetry: _checkHealth,
              ),
              const SizedBox(height: 20),
              // ── Image Preview ──────────────────────────────────────────
              _buildImagePreview(),
              const SizedBox(height: 16),

              // ── Buttons ────────────────────────────────────────────────
              _buildButtons(),
              const SizedBox(height: 20),

              // ── Loading ────────────────────────────────────────────────
              if (_isLoading)
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 12),
                      Text(
                        "Analyzing your image…",
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Your results will appear here when ready.",
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),

              // ── Results ────────────────────────────────────────────────
              if (_result != null && !_isLoading) ...[
                _buildAlert(),
                const SizedBox(height: 12),
                _buildStats(),
                const SizedBox(height: 12),
                if (_result!.violations.isNotEmpty) _buildViolationsList(),
                if (_result!.violations.isEmpty) _buildAllClearCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Image Preview ─────────────────────────────────────────────────────────
  int _previewDecodeWidth(BuildContext context) =>
      ((MediaQuery.sizeOf(context).width - 40) *
              MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(320, 1600);

  Widget _buildImagePreview() {
    Widget content;

    if (_annotatedImage != null) {
      content = Stack(
        children: [
          Image.memory(
            _annotatedImage!,
            cacheWidth: _previewDecodeWidth(context),
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder:
                (_, __, ___) => const Center(
                  child: Text(
                    'The service returned an image that could not be previewed.',
                  ),
                ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Annotated Result",
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      );
    } else if (_imageBytes != null) {
      content = Stack(
        children: [
          Image.memory(
            _imageBytes!,
            cacheWidth: _previewDecodeWidth(context),
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder:
                (_, __, ___) => const Center(
                  child: Text(
                    'This image could not be previewed. Try another file.',
                  ),
                ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Ready to detect",
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      );
    } else {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 64,
              color: AppColors.muted,
            ),
            const SizedBox(height: 8),
            Text(
              kIsWeb
                  ? "Select an image from gallery"
                  : "Select or capture an image",
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              "Supported: JPG, PNG",
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: content),
    );
  }

  // ── Buttons ───────────────────────────────────────────────────────────────
  Widget _buildButtons() {
    return AdaptiveRow(
      minItemWidth: 95,
      children: [
        Expanded(
          child: _actionButton(
            icon: Icons.photo_library_outlined,
            label: "Gallery",
            onTap: _isLoading || _isPicking ? null : _pickImage,
            color: AppColors.primary,
          ),
        ),
        if (!kIsWeb) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _actionButton(
              icon: Icons.camera_alt_outlined,
              label: "Camera",
              onTap: _isLoading || _isPicking ? null : _captureImage,
              color: AppColors.primary,
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            icon:
                _isLoading ? Icons.hourglass_top_rounded : Icons.search_rounded,
            label: _isLoading ? "..." : "Detect",
            onTap:
                _isLoading || _isPicking || _imageBytes == null
                    ? null
                    : _detect,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Alert ─────────────────────────────────────────────────────────────────
  Widget _buildAlert() {
    final has = _result!.violationsFound;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            has
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: has ? Colors.red : Colors.green, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            has ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            color: has ? Colors.red : Colors.green,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  has ? "⚠️ CHEATING DETECTED!" : "✅ No Violations",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: has ? Colors.red[800] : Colors.green[800],
                  ),
                ),
                Text(
                  has
                      ? "${_result!.totalViolations} violation(s) found"
                      : "Student appears to be studying normally",
                  style: TextStyle(
                    fontSize: 11,
                    color: has ? Colors.red[400] : Colors.green[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "📊 Detection Stats",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statBox(
                  "Detections",
                  "${_result!.totalDetections}",
                  AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statBox(
                  "Violations",
                  "${_result!.totalViolations}",
                  Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statBox(
                  "Time",
                  "${_result!.inferenceTimeMs.toStringAsFixed(0)}ms",
                  AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ── Violations List ───────────────────────────────────────────────────────
  Widget _buildViolationsList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "🚨 Violations Detected",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Colors.red[800],
            ),
          ),
          const SizedBox(height: 10),
          ..._result!.violations.map(
            (v) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[100]!),
              ),
              child: Row(
                children: [
                  Text(v.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      v.violation.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${(v.confidence * 100).toStringAsFixed(1)}%",
                      style: TextStyle(
                        color: Colors.red[800],
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
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

  // ── All Clear Card ────────────────────────────────────────────────────────
  Widget _buildAllClearCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF22C55E),
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            "All Clear!",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Colors.green[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "No accepted violations returned for this image. Human review is still important.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.green[600]),
          ),
        ],
      ),
    );
  }
}
