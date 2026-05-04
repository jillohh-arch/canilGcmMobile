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
    const common = [
      OccurrenceQuickUpdateShortcut(
        title: 'Conduzido à Santa Casa',
        template: 'Conduzido à Santa Casa para avaliação/perícia médica.',
      ),
      OccurrenceQuickUpdateShortcut(
        title: 'Apresentado no DP',
        template:
            'Ocorrência apresentada no Distrito Policial para as providências cabíveis.',
      ),
      OccurrenceQuickUpdateShortcut(
        title: 'Aguardando perícia',
        template: 'Equipe aguardando perícia para continuidade da ocorrência.',
      ),
      OccurrenceQuickUpdateShortcut(
        title: 'Aguardando vaga',
        template:
            'Equipe aguardando vaga/recepção para prosseguimento da apresentação.',
      ),
      OccurrenceQuickUpdateShortcut(
        title: 'Encerrada apresentação',
        template:
            'Apresentação encerrada, aguardando consolidação do desfecho final.',
      ),
    ];

    switch (subtype) {
      case detection:
      case narcoticsSearch:
        return const [
          OccurrenceQuickUpdateShortcut(
            title: 'Material localizado',
            template:
                'K9 indicou positivamente e o material foi localizado no ponto de busca.',
          ),
          OccurrenceQuickUpdateShortcut(
            title: 'Aguardando pesagem',
            template:
                'Material apreendido, aguardando pesagem/quantificação oficial.',
          ),
          ...common,
        ];
      case missingPerson:
        return const [
          OccurrenceQuickUpdateShortcut(
            title: 'Varredura em andamento',
            template:
                'Varredura em andamento na área informada com apoio do K9.',
          ),
          OccurrenceQuickUpdateShortcut(
            title: 'Pessoa localizada',
            template:
                'Pessoa localizada e equipe seguindo para os procedimentos posteriores.',
          ),
          ...common,
        ];
      case supportVehicle:
        return const [
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
          ...common,
        ];
      case serviceOrder:
        return const [
          OccurrenceQuickUpdateShortcut(
            title: 'Fiscalização em andamento',
            template:
                'Fiscalização em andamento conforme Ordem de Serviço, sem desfecho final até o momento.',
          ),
          ...common,
        ];
      case event:
        return const [
          OccurrenceQuickUpdateShortcut(
            title: 'Ação educativa em andamento',
            template:
                'Ação educativa/palestra em andamento com acompanhamento da equipe.',
          ),
          ...common,
        ];
      case other:
        return const [
          OccurrenceQuickUpdateShortcut(
            title: 'Local preservado',
            template:
                'Local preservado pela equipe até a chegada/atuação do órgão competente.',
          ),
          OccurrenceQuickUpdateShortcut(
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
