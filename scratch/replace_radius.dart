import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  final regexRadius = RegExp(r'BorderRadius\.circular\(\s*([0-9\.]+)\s*\)');
  final regexRadiusOnly = RegExp(r'Radius\.circular\(\s*([0-9\.]+)\s*\)');
  
  for (final file in files) {
    if (file.path.contains('app_theme.dart')) continue;
    
    var content = file.readAsStringSync();
    var original = content;
    
    content = content.replaceAllMapped(regexRadius, (match) {
      final val = double.tryParse(match.group(1)!);
      if (val != null && val >= 3 && val <= 40 && val != 6) {
        return 'BorderRadius.circular(6)';
      }
      return match.group(0)!;
    });
    
    content = content.replaceAllMapped(regexRadiusOnly, (match) {
      final val = double.tryParse(match.group(1)!);
      if (val != null && val >= 3 && val <= 40 && val != 6) {
        return 'Radius.circular(6)';
      }
      return match.group(0)!;
    });

    if (content != original) {
      file.writeAsStringSync(content);
      print('Updated \${file.path}');
    }
  }
}
