import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> requestInitialPermissions() async {
    // Solicita as permissões essenciais de forma encadeada
    await [
      Permission.location,
      Permission.storage,
      Permission.photos, // Para Android 13+ (READ_MEDIA_IMAGES)
    ].request();

    // Podemos apenas aguardar, o package permission_handler trata a UI nativa
    // de acordo com as diretrizes do Android/iOS. Se precisarmos checar o status:
    // var locationStatus = await Permission.location.status;
  }
}
