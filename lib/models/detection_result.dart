class DetectionResult {
  final bool violationsFound;
  final int totalDetections;
  final int totalViolations;
  final double inferenceTimeMs;
  final String? annotatedImage;
  final List<Violation> violations;
  final List<Map<String, dynamic>> detections;

  const DetectionResult({
    required this.violationsFound,
    required this.totalDetections,
    required this.totalViolations,
    required this.inferenceTimeMs,
    this.annotatedImage,
    required this.violations,
    this.detections = const [],
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    try {
      if (json['violations_found'] is! bool || json['violations'] is! List) {
        throw const FormatException('Missing image result fields');
      }
      final violations =
          (json['violations'] as List)
              .map((e) => Violation.fromJson(e as Map<String, dynamic>))
              .toList();
      final found = json['violations_found'] as bool;
      if (found != violations.isNotEmpty) {
        throw const FormatException('Inconsistent violation summary');
      }
      return DetectionResult(
        violationsFound: found,
        totalDetections: (json['total_detections'] as num?)?.toInt() ?? 0,
        totalViolations:
            (json['total_violations'] as num?)?.toInt() ?? violations.length,
        inferenceTimeMs: (json['inference_time_ms'] as num?)?.toDouble() ?? 0,
        annotatedImage: json['annotated_image'] as String?,
        violations: violations,
        detections:
            (json['detections'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
      );
    } on TypeError {
      throw const FormatException('Invalid image result fields');
    }
  }
}

class Violation {
  final String violation;
  final double confidence;
  final String emoji;

  const Violation({
    required this.violation,
    required this.confidence,
    required this.emoji,
  });

  factory Violation.fromJson(Map<String, dynamic> json) {
    final label = json['violation'];
    final confidence = json['confidence'];
    if (label is! String ||
        label.isEmpty ||
        confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw const FormatException('Invalid violation');
    }
    return Violation(
      violation: label,
      confidence: confidence.toDouble(),
      emoji: json['emoji'] as String? ?? '⚠️',
    );
  }
}
