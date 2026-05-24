import 'package:printing/printing.dart';

void main() async {
  try {
    final font1 = await PdfGoogleFonts.iBMPlexSansRegular();
    final font2 = await PdfGoogleFonts.iBMPlexSansMedium();
    final font3 = await PdfGoogleFonts.iBMPlexSansBold();
    final font4 = await PdfGoogleFonts.iBMPlexSansSemiBold();
    final font5 = await PdfGoogleFonts.iBMPlexMonoRegular();
    final font6 = await PdfGoogleFonts.iBMPlexMonoBold();
    print('Fonts loaded successfully!');
  } catch (e) {
    print('Error loading fonts: $e');
  }
}

