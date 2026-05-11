part of 'occurrence_quick_update_catalog.dart';

const _detectionQuickUpdateShortcuts = [
  OccurrenceQuickUpdateShortcut(
    title: 'Material localizado',
    template:
        'K9 indicou positivamente e o material foi localizado no ponto de busca.',
  ),
  OccurrenceQuickUpdateShortcut(
    title: 'Aguardando pesagem',
    template: 'Material apreendido, aguardando pesagem/quantificação oficial.',
  ),
  ..._commonQuickUpdateShortcuts,
];

const _missingPersonQuickUpdateShortcuts = [
  OccurrenceQuickUpdateShortcut(
    title: 'Varredura em andamento',
    template: 'Varredura em andamento na área informada com apoio do K9.',
  ),
  OccurrenceQuickUpdateShortcut(
    title: 'Pessoa localizada',
    template:
        'Pessoa localizada e equipe seguindo para os procedimentos posteriores.',
  ),
  ..._commonQuickUpdateShortcuts,
];

const _supportVehicleQuickUpdateShortcuts = [
  OccurrenceQuickUpdateShortcut(
    title: 'Apoio no local',
    template:
        'Equipe no local prestando apoio operacional à guarnição solicitante.',
  ),
  OccurrenceQuickUpdateShortcut(
    title: 'Guarnição apoiada',
    template:
        'Apoio prestado à guarnição no local, ocorrência seguindo em atendimento.',
  ),
  ..._commonQuickUpdateShortcuts,
];

const _serviceOrderQuickUpdateShortcuts = [
  OccurrenceQuickUpdateShortcut(
    title: 'Fiscalização em andamento',
    template:
        'Fiscalização em andamento conforme Ordem de Serviço, sem desfecho final até o momento.',
  ),
  ..._commonQuickUpdateShortcuts,
];

const _eventQuickUpdateShortcuts = [
  OccurrenceQuickUpdateShortcut(
    title: 'Ação educativa em andamento',
    template:
        'Ação educativa/palestra em andamento com acompanhamento da equipe.',
  ),
  ..._commonQuickUpdateShortcuts,
];

const _otherQuickUpdateShortcuts = [
  OccurrenceQuickUpdateShortcut(
    title: 'Local preservado',
    template:
        'Local preservado pela equipe até a chegada/atuação do órgão competente.',
  ),
  OccurrenceQuickUpdateShortcut(
    title: 'Trânsito sinalizado',
    template: 'Trânsito sinalizado e fluxo organizado para segurança no local.',
  ),
  ..._commonQuickUpdateShortcuts,
];

List<OccurrenceQuickUpdateShortcut> _quickUpdateShortcutsForSubtype(
  String? subtype,
) {
  switch (subtype) {
    case OccurrenceQuickUpdateCatalog.detection:
    case OccurrenceQuickUpdateCatalog.narcoticsSearch:
      return _detectionQuickUpdateShortcuts;
    case OccurrenceQuickUpdateCatalog.missingPerson:
      return _missingPersonQuickUpdateShortcuts;
    case OccurrenceQuickUpdateCatalog.supportVehicle:
      return _supportVehicleQuickUpdateShortcuts;
    case OccurrenceQuickUpdateCatalog.serviceOrder:
      return _serviceOrderQuickUpdateShortcuts;
    case OccurrenceQuickUpdateCatalog.event:
      return _eventQuickUpdateShortcuts;
    case OccurrenceQuickUpdateCatalog.other:
      return _otherQuickUpdateShortcuts;
    default:
      return _commonQuickUpdateShortcuts;
  }
}
