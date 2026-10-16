// F70 — Visual fixture writer (LOCAL ONLY, hermetic, synthetic).
// Generates real openable PDFs into build/visual_fixtures/occurrence_f70/.
// Does NOT modify any productive writer; uses synthetic bitmaps via
// memory images (no network) and amendmentsOverride injection seam.

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Generates synthetic bitmap bytes (JPEG) of given dimensions and color.
/// Used to prove actual image rendering (not just "imagem indisponível").
Uint8List syntheticJpeg({
  required int width,
  required int height,
  int r = 80,
  int g = 160,
  int b = 200,
  String? label,
}) {
  final image = img.Image(width: width, height: height);
  // Fill with solid color
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Simple gradient + border for visual proof
      final isBorder = x < 4 || x >= width - 4 || y < 4 || y >= height - 4;
      if (isBorder) {
        image.setPixelRgb(x, y, 20, 40, 60);
      } else {
        // Slight gradient
        final grad = (x / width * 30).round();
        image.setPixelRgb(
          x,
          y,
          (r + grad).clamp(0, 255),
          (g + grad).clamp(0, 255),
          (b + grad).clamp(0, 255),
        );
      }
    }
  }
  // Diagonal cross for aspect ratio proof
  final minDim = width < height ? width : height;
  final crossColor = img.ColorRgb8(255, 255, 255);
  for (var i = 8; i < minDim - 8; i++) {
    final px = (i * width / minDim).round().clamp(0, width - 1);
    final py = (i * height / minDim).round().clamp(0, height - 1);
    image.setPixel(px, py, crossColor);
    if (px + 1 < width) image.setPixel(px + 1, py, crossColor);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 82));
}

/// Writes [bytes] to [dir]/[filename], creating [dir] if needed.
/// Returns the File.
Future<File> writeFixturePdf({
  required String dir,
  required String filename,
  required Uint8List bytes,
}) async {
  final d = Directory(dir);
  await d.create(recursive: true);
  final file = File('${d.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Counts PDF pages by scanning for "/Type /Page" entries.
/// Fast, no external dependencies. Returns at least 1 for valid PDFs.
int countPdfPages(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  // Each page object contains "/Type /Page" (but not "/Type /Pages")
  // Use regex: "/Type /Page" not followed by "s"
  final re = RegExp(r'/Type\s*/Page(?!s)');
  return re.allMatches(text).length;
}

/// Returns true if [text] appears in raw PDF bytes (latin1).
bool pdfContainsText(Uint8List bytes, String text) {
  final raw = String.fromCharCodes(bytes);
  return raw.contains(text);
}
