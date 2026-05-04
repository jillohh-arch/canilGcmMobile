class OccurrenceExtraFieldsSnapshot {
  final Map<String, dynamic> source;

  const OccurrenceExtraFieldsSnapshot(this.source);

  String get team => _text('equipe');
  String get reportNumber => _text('bo');
  String get supportedGarrison => _text('guarnicao');
  String get situation => _text('situacao');
  String get interventionOutcome => _text('desfecho');
  String get odorSource => _text('odor_inicial');
  String get missingTime => _text('tempo_desaparecimento');
  String get searchDuration => _text('duracao_busca');
  String get terrainCondition => _text('condicao_terreno');
  String get serviceOrderNumber => _text('numero_os');
  String get publicEstimate => _text('publico_estimado');
  String get eventTheme => _text('tema');
  String get manualNature => _text('natureza_manual');
  String get nature => _text('natureza');

  dynamic get searchType => source['tipo_busca'];
  dynamic get legacyDrugRows => source['drogas'];

  double? get locationLat => _doubleValue('locationLat');
  double? get locationLng => _doubleValue('locationLng');

  Map<String, dynamic>? get detailedResults {
    final value = source['resultadosDetalhados'];
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  String manualNatureOrNature() {
    return manualNature.isNotEmpty ? manualNature : nature;
  }

  String _text(String key) {
    return source[key]?.toString() ?? '';
  }

  double? _doubleValue(String key) {
    final value = source[key];
    if (value is! num) return null;
    return value.toDouble();
  }
}
