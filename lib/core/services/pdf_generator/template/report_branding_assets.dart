import 'dart:io';
import 'package:flutter/services.dart';

/// Carregador do asset oficial do K9 Ops ProductMark existente no projeto.
class ReportBrandingAssets {
  ReportBrandingAssets._();

  static const String officialLogoAssetPath = 'assets/images/logo-app.png';
  static const String appIconAssetPath = 'assets/app_icon.png';

  static Uint8List? _cachedLogo;

  /// Retorna os bytes do asset oficial homologado do K9 Ops ProductMark.
  static Future<Uint8List?> loadOfficialLogo({AssetBundle? bundle}) async {
    if (_cachedLogo != null) return _cachedLogo;
    final b = bundle ?? rootBundle;
    try {
      final data = await b.load(officialLogoAssetPath);
      _cachedLogo = data.buffer.asUint8List();
      return _cachedLogo;
    } catch (_) {
      try {
        final data = await b.load(appIconAssetPath);
        _cachedLogo = data.buffer.asUint8List();
        return _cachedLogo;
      } catch (_) {
        try {
          final file = File(officialLogoAssetPath);
          if (file.existsSync()) {
            _cachedLogo = file.readAsBytesSync();
            return _cachedLogo;
          }
        } catch (_) {}
        try {
          final file = File(appIconAssetPath);
          if (file.existsSync()) {
            _cachedLogo = file.readAsBytesSync();
            return _cachedLogo;
          }
        } catch (_) {}
      }
    }
    return _cachedLogo;
  }
}
