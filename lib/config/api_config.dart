/// Public endpoint configuration only. Never put tokens in dart-defines.
class ApiConfig {
  static const baseUrl = String.fromEnvironment('API_BASE_URL');
  static const maxImageBytes = 20 * 1024 * 1024;
  static const maxVideoBytes = 250 * 1024 * 1024;
  static const headers = {
    'Accept': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  static Uri endpoint(String base, List<String> segments) {
    final uri = Uri.tryParse(base.trim());
    if (uri == null ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Configure a valid API_BASE_URL before using analysis tools.',
      );
    }
    return uri.replace(
      pathSegments: [
        ...uri.pathSegments.where((part) => part.isNotEmpty),
        ...segments,
      ],
    );
  }
}
