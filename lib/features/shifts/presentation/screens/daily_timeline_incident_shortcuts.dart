part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentShortcuts on _DailyTimelineScreenState {
  Set<String> _quickCloseDefaultOutcomesForSubtype(String? subtype) {
    switch (subtype) {
      case 'supportVehicle':
      case 'serviceOrder':
      case 'event':
      case 'other':
        return {'Apoio prestado'};
      default:
        return <String>{};
    }
  }

  List<_IncidentQuickProgressShortcut> _quickProgressShortcutsForSubtype(
    String? subtype,
  ) {
    const common = [
      _IncidentQuickProgressShortcut(
        title: 'Conduzido a Santa Casa',
        template: 'Conduzido à Santa Casa para avaliação/perícia médica.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Apresentado no DP',
        template:
            'Ocorrência apresentada no Distrito Policial para as providências cabíveis.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Aguardando perícia',
        template: 'Equipe aguardando perícia para continuidade da ocorrência.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Aguardando vaga',
        template:
            'Equipe aguardando vaga/recepção para prosseguimento da apresentação.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Encerrada apresentação',
        template:
            'Apresentação encerrada, aguardando consolidação do desfecho final.',
      ),
    ];

    switch (subtype) {
      case 'detection':
      case 'narcoticsSearch':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Material localizado',
            template:
                'K9 indicou positivamente e o material foi localizado no ponto de busca.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Aguardando pesagem',
            template:
                'Material apreendido, aguardando pesagem/quantificação oficial.',
          ),
          ...common,
        ];
      case 'missingPerson':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Varredura em andamento',
            template:
                'Varredura em andamento na área informada com apoio do K9.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Pessoa localizada',
            template:
                'Pessoa localizada e equipe seguindo para os procedimentos posteriores.',
          ),
          ...common,
        ];
      case 'supportVehicle':
        return const [
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
          ...common,
        ];
      case 'serviceOrder':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Fiscalização em andamento',
            template:
                'Fiscalização em andamento conforme Ordem de Serviço, sem desfecho final até o momento.',
          ),
          ...common,
        ];
      case 'event':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Ação educativa em andamento',
            template:
                'Ação educativa/palestra em andamento com acompanhamento da equipe.',
          ),
          ...common,
        ];
      case 'other':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Local preservado',
            template:
                'Local preservado pela equipe até a chegada/atuação do órgão competente.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Trânsito sinalizado',
            template:
                'Trânsito sinalizado e fluxo organizado para segurança no local.',
          ),
          ...common,
        ];
      default:
        return common;
    }
  }
}
