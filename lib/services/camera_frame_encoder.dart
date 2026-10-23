import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ── Isolate: proper YUV420→RGB→JPEG with rotation fix ─────────────────────
Uint8List? cameraFrameToJpeg(Map<String, dynamic> args) {
  final int w = args['w'] as int;
  final int h = args['h'] as int;
  if (args['bgra'] != null) {
    final bytes = args['bgra'] as Uint8List;
    final image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      rowStride: args['stride'] as int,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    // AVFoundation already supplies buffers in the capture orientation.
    return img.encodeJpg(image, quality: 70);
  }
  final Uint8List yBuf = args['y'] as Uint8List;
  final Uint8List uBuf = args['u'] as Uint8List;
  final Uint8List vBuf = args['v'] as Uint8List;
  final int yStride = args['yStride'] as int;
  final int uvStride = args['uvStride'] as int;
  final int uvPixel = args['uvPixel'] as int;
  final int rotation = args['rotation'] as int; // 0,90,180,270

  final image = img.Image(width: w, height: h);

  for (int row = 0; row < h; row++) {
    for (int col = 0; col < w; col++) {
      final int yIdx = row * yStride + col;
      final int uvIdx = (row >> 1) * uvStride + (col >> 1) * uvPixel;

      final int yv = yBuf[yIdx] & 0xFF;
      final int uv = uBuf[uvIdx] & 0xFF;
      final int vv = vBuf[uvIdx] & 0xFF;

      final int r = (yv + 1.402 * (vv - 128)).round().clamp(0, 255);
      final int g = (yv - 0.344136 * (uv - 128) - 0.714136 * (vv - 128))
          .round()
          .clamp(0, 255);
      final int b = (yv + 1.772 * (uv - 128)).round().clamp(0, 255);

      image.setPixelRgb(col, row, r, g, b);
    }
  }

  // Fix rotation so image is upright before sending to model
  img.Image rotated = image;
  if (rotation == 90) {
    rotated = img.copyRotate(image, angle: 90);
  } else if (rotation == 270) {
    rotated = img.copyRotate(image, angle: -90);
  } else if (rotation == 180) {
    rotated = img.copyRotate(image, angle: 180);
  }

  return img.encodeJpg(rotated, quality: 70);
}
