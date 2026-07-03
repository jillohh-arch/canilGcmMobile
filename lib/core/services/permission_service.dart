import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static bool _requestInProgress = false;

  static Future<void> requestInitialPermissions() async {
    if (_requestInProgress) return;
    _requestInProgress = true;
    try {
      await [
        Permission.location,
        Permission.storage,
        Permission.photos, // READ_MEDIA_IMAGES no Android 13+
      ].request();
    } catch (e) {
      debugPrint('[PermissionService] falhou: $e');
    } finally {
      _requestInProgress = false;
    }
  }
}
