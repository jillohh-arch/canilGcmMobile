import 'dart:convert';

class FormMetadataReader {
  final Map<String, dynamic> metadata;

  const FormMetadataReader(this.metadata);

  dynamic value(String key) {
    return metadata[key] ?? metadata[_legacyMojibakeKey(key)];
  }

  String _legacyMojibakeKey(String value) {
    return latin1.decode(utf8.encode(value));
  }
}
