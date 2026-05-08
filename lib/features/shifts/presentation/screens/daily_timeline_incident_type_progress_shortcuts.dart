part of 'daily_timeline_screen.dart';

const List<_IncidentQuickProgressShortcut> _searchIncidentProgressShortcuts = [
  _IncidentQuickProgressShortcut(
    title: 'Material localizado',
    template:
        'K9 indicou positivamente e o material foi localizado no ponto de busca.',
  ),
  _IncidentQuickProgressShortcut(
    title: 'Aguardando pesagem',
    template: 'Material apreendido, aguardando pesagem/quantificação oficial.',
  ),
];

const List<_IncidentQuickProgressShortcut>
_missingPersonIncidentProgressShortcuts = [
  _IncidentQuickProgressShortcut(
    title: 'Varredura em andamento',
    template: 'Varredura em andamento na área informada com apoio do K9.',
  ),
  _IncidentQuickProgressShortcut(
    title: 'Pessoa localizada',
    template:
        'Pessoa localizada e equipe seguindo para os procedimentos posteriores.',
  ),
];

const List<_IncidentQuickProgressShortcut>
_supportVehicleIncidentProgressShortcuts = [
  _IncidentQuickProgressShortcut(
    title: 'Apoio no local',
    template:
        'Equipe no local prestando apoio operacional à guarnição solicitante.',
  ),
  _IncidentQuickProgressShortcut(
    title: 'Guarnição apoiada',
    template:
        'Apoio prestado à guarnição no local, ocorrência seguindo em atendimento.',
  ),
];

const List<_IncidentQuickProgressShortcut>
_serviceOrderIncidentProgressShortcuts = [
  _IncidentQuickProgressShortcut(
    title: 'Fiscalização em andamento',
    template:
        'Fiscalização em andamento conforme Ordem de Serviço, sem desfecho final até o momento.',
  ),
];

const List<_IncidentQuickProgressShortcut> _eventIncidentProgressShortcuts = [
  _IncidentQuickProgressShortcut(
    title: 'Ação educativa em andamento',
    template:
        'Ação educativa/palestra em andamento com acompanhamento da equipe.',
  ),
];

const List<_IncidentQuickProgressShortcut> _otherIncidentProgressShortcuts = [
  _IncidentQuickProgressShortcut(
    title: 'Local preservado',
    template:
        'Local preservado pela equipe até a chegada/atuação do órgão competente.',
  ),
  _IncidentQuickProgressShortcut(
    title: 'Trânsito sinalizado',
    template: 'Trânsito sinalizado e fluxo organizado para segurança no local.',
  ),
];

List<_IncidentQuickProgressShortcut> _typeProgressShortcutsForSubtype(
  String? subtype,
) {
  switch (subtype) {
    case 'detection':
    case 'narcoticsSearch':
      return _searchIncidentProgressShortcuts;
    case 'missingPerson':
      return _missingPersonIncidentProgressShortcuts;
    case 'supportVehicle':
      return _supportVehicleIncidentProgressShortcuts;
    case 'serviceOrder':
      return _serviceOrderIncidentProgressShortcuts;
    case 'event':
      return _eventIncidentProgressShortcuts;
    case 'other':
      return _otherIncidentProgressShortcuts;
    default:
      return const [];
  }
}
