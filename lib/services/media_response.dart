import 'dart:convert';
import 'dart:typed_data';

/// Supports plain base64 and the image data URI used by some Colab versions.
Uint8List? decodeAnnotatedImage(String? value) {
  if (value == null || value.isEmpty) return null;
  if (value.length > 28 * 1024 * 1024) {
    throw const FormatException('Annotated image is too large.');
  }
  if (value.startsWith('data:')) {
    final comma = value.indexOf(',');
    if (comma < 0 || !value.substring(0, comma).endsWith(';base64')) {
      throw const FormatException('Invalid annotated image.');
    }
    value = value.substring(comma + 1);
  }
  return base64Decode(value);
}
