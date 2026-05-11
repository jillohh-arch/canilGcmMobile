part 'occurrence_quick_update_catalog_common.dart';
part 'occurrence_quick_update_catalog_subtypes.dart';

class OccurrenceQuickUpdateShortcut {
  final String title;
  final String template;

  const OccurrenceQuickUpdateShortcut({
    required this.title,
    required this.template,
  });
}

class OccurrenceQuickUpdateCatalog {
  const OccurrenceQuickUpdateCatalog._();

  static const detection = 'Detecção';
  static const supportVehicle = 'Apoio à Viatura/Guarnição';
  static const missingPerson = 'Busca de Pessoa';
  static const serviceOrder = 'Ordem de Serviço (O.S.)';
  static const event = 'Palestra/Evento (RP)';
  static const other = 'Outros';
  static const narcoticsSearch = 'Busca de Entorpecentes';

  static List<OccurrenceQuickUpdateShortcut> forSubtype(String? subtype) {
    return _quickUpdateShortcutsForSubtype(subtype);
  }
}
