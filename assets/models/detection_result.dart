class DetectionResult {
  final bool violationsFound;
  final int totalDetections;
  final int totalViolations;
  final double inferenceTimeMs;
  final List<Violation> violations;
  final List<Detection> detections;
  final String? annotatedImage;

  DetectionResult({
    required this.violationsFound,
    required this.totalDetections,
    required this.totalViolations,
    required this.inferenceTimeMs,
    required this.violations,
    required this.detections,
    this.annotatedImage,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      violationsFound: json['violations_found'] ?? false,
      totalDetections: json['total_detections'] ?? 0,
      totalViolations: json['total_violations'] ?? 0,
      inferenceTimeMs: (json['inference_time_ms'] ?? 0).toDouble(),
      violations:
          (json['violations'] as List? ?? [])
              .map((v) => Violation.fromJson(v))
              .toList(),
      detections:
          (json['detections'] as List? ?? [])
              .map((d) => Detection.fromJson(d))
              .toList(),
      annotatedImage: json['annotated_image'],
    );
  }
}

class Violation {
  final String violation;
  final double confidence;

  Violation({required this.violation, required this.confidence});

  factory Violation.fromJson(Map<String, dynamic> json) {
    return Violation(
      violation: json['violation'] ?? '',
      confidence: (json['confidence'] ?? 0).toDouble(),
    );
  }

  String get emoji {
    switch (violation) {
      case 'using_mobile':
        return '📱';
      case 'peeking_around':
        return '👀';
      case 'passing_note':
        return '📝';
      case 'book_visible':
        return '📚';
      case 'showing_paper':
        return '📄';
      default:
        return '⚠️';
    }
  }
}

class Detection {
  final int classId;
  final String className;
  final double confidence;

  Detection({
    required this.classId,
    required this.className,
    required this.confidence,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      classId: json['class_id'] ?? 0,
      className: json['class_name'] ?? '',
      confidence: (json['confidence'] ?? 0).toDouble(),
    );
  }
}
