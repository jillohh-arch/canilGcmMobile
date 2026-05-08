part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentRules on _DailyTimelineScreenState {
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

  List<String> _quickCloseOutcomeOptionsForSubtype(String? subtype) {
    switch (subtype) {
      case 'detection':
      case 'narcoticsSearch':
        return const [
          'Droga apreendida',
          'Indivíduo detido',
          'Apoio prestado',
          'BO elaborado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case 'supportVehicle':
        return const [
          'Apoio prestado',
          'Indivíduo detido',
          'Encaminhamento médico',
          'BO elaborado',
          'Local preservado',
          'Sem constatação',
        ];
      case 'missingPerson':
        return const [
          'Pessoa localizada',
          'Objeto localizado',
          'Apoio prestado',
          'Encaminhamento médico',
          'BO elaborado',
          'Sem constatação',
        ];
      case 'serviceOrder':
        return const [
          'Apoio prestado',
          'BO elaborado',
          'Local preservado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case 'event':
        return const [
          'Apoio prestado',
          'Ação educativa concluída',
          'BO elaborado',
          'Sem constatação',
        ];
      case 'other':
        return const [
          'Apoio prestado',
          'Vítima socorrida',
          'Encaminhamento médico',
          'Trânsito sinalizado',
          'Local preservado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
      default:
        return const [
          'Apoio prestado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
    }
  }

  String? _prioritizedQuickCloseOutcomeSummary(
    Set<String> outcomes,
    String? subtype,
  ) {
    if (outcomes.contains('Droga apreendida')) {
      return 'Apreensão Positiva';
    }
    if (subtype == 'missingPerson' && outcomes.contains('Pessoa localizada')) {
      return 'Sucesso';
    }
    if (outcomes.contains('Indivíduo detido')) {
      return 'Indivíduo detido';
    }
    if (outcomes.contains('Vítima socorrida')) {
      return 'Vítima socorrida';
    }
    if (outcomes.contains('Encaminhamento médico')) {
      return 'Encaminhamento médico';
    }
    if (outcomes.contains('Trânsito sinalizado')) {
      return 'Trânsito sinalizado';
    }
    if (outcomes.contains('Local preservado')) {
      return 'Local preservado';
    }
    if (outcomes.contains('Ação educativa concluída')) {
      return 'Ação educativa concluída';
    }
    if (outcomes.contains('Apoio prestado')) {
      return 'Apoio prestado';
    }
    if (outcomes.contains('BO elaborado')) {
      return 'BO elaborado';
    }
    if (outcomes.contains('Sem constatação')) {
      return 'Sem constatação';
    }

    return null;
  }

  String _buildQuickCloseResultSummary({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
  }) {
    final summary = _prioritizedQuickCloseOutcomeSummary(
      selectedOutcomes,
      incident.type,
    );
    if (summary != null) {
      return summary;
    }
    return operationalSuccess ? 'Êxito' : 'Sem êxito';
  }

  _IncidentProgressStyle _resolveIncidentProgressStyle(
    String? title,
    String? description,
  ) {
    final normalizedTitle = (title ?? '').toLowerCase();
    final normalizedDescription = (description ?? '').toLowerCase();

    if (normalizedTitle.contains('encerramento')) {
      return const _IncidentProgressStyle(
        icon: Icons.task_alt_rounded,
        iconColor: Color(0xFF4ADE80),
        iconBackground: Color(0x1F4ADE80),
        titleColor: Color(0xFF86EFAC),
        backgroundColor: Color(0x1418241C),
        borderColor: Color(0x334ADE80),
      );
    }

    if (normalizedTitle.contains('apreens') ||
        normalizedTitle.contains('resultado') ||
        normalizedTitle.contains('detido') ||
        normalizedTitle.contains('localizada') ||
        normalizedDescription.contains('resultados parciais')) {
      return const _IncidentProgressStyle(
        icon: Icons.fact_check_rounded,
        iconColor: Color(0xFFFBBF24),
        iconBackground: Color(0x1FFBBF24),
        titleColor: Color(0xFFFCD34D),
        backgroundColor: Color(0x14FBBF24),
        borderColor: Color(0x33FBBF24),
      );
    }

    return const _IncidentProgressStyle(
      icon: Icons.timeline_rounded,
      iconColor: Color(0xFF38BDF8),
      iconBackground: Color(0x1F38BDF8),
      titleColor: Color(0xFF7DD3FC),
      backgroundColor: Color(0x1438BDF8),
      borderColor: Color(0x3338BDF8),
    );
  }

  _IncidentBadgeStyle _resolveIncidentStatusBadgeStyle(String status) {
    final normalized = status.toLowerCase();

    if (normalized.contains('concl')) {
      return const _IncidentBadgeStyle(
        icon: Icons.task_alt_rounded,
        iconColor: Color(0xFF4ADE80),
        textColor: Color(0xFF86EFAC),
        backgroundColor: Color(0x144ADE80),
        borderColor: Color(0x334ADE80),
      );
    }

    if (normalized.contains('cancel')) {
      return const _IncidentBadgeStyle(
        icon: Icons.cancel_rounded,
        iconColor: Color(0xFFF87171),
        textColor: Color(0xFFFCA5A5),
        backgroundColor: Color(0x14F87171),
        borderColor: Color(0x33F87171),
      );
    }

    return const _IncidentBadgeStyle(
      icon: Icons.radar_rounded,
      iconColor: Color(0xFFFBBF24),
      textColor: Color(0xFFFCD34D),
      backgroundColor: Color(0x14FBBF24),
      borderColor: Color(0x33FBBF24),
    );
  }

  _IncidentBadgeStyle _resolveIncidentOutcomeBadgeStyle(String outcome) {
    final normalized = outcome.toLowerCase();

    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const _IncidentBadgeStyle(
        icon: Icons.inventory_2_rounded,
        iconColor: Color(0xFFFBBF24),
        textColor: Color(0xFFFCD34D),
        backgroundColor: Color(0x14FBBF24),
        borderColor: Color(0x33FBBF24),
      );
    }

    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const _IncidentBadgeStyle(
        icon: Icons.gpp_good_rounded,
        iconColor: Color(0xFFFB7185),
        textColor: Color(0xFFFDA4AF),
        backgroundColor: Color(0x14FB7185),
        borderColor: Color(0x33FB7185),
      );
    }

    if (normalized.contains('localiz')) {
      return const _IncidentBadgeStyle(
        icon: Icons.location_searching_rounded,
        iconColor: Color(0xFF38BDF8),
        textColor: Color(0xFF7DD3FC),
        backgroundColor: Color(0x1438BDF8),
        borderColor: Color(0x3338BDF8),
      );
    }

    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return const _IncidentBadgeStyle(
        icon: Icons.volunteer_activism_rounded,
        iconColor: Color(0xFF2DD4BF),
        textColor: Color(0xFF99F6E4),
        backgroundColor: Color(0x142DD4BF),
        borderColor: Color(0x332DD4BF),
      );
    }

    if (normalized.contains('sem constat')) {
      return const _IncidentBadgeStyle(
        icon: Icons.search_off_rounded,
        iconColor: Color(0xFF94A3B8),
        textColor: Color(0xFFCBD5E1),
        backgroundColor: Color(0x1494A3B8),
        borderColor: Color(0x3394A3B8),
      );
    }

    return const _IncidentBadgeStyle(
      icon: Icons.fact_check_rounded,
      iconColor: Color(0xFFA78BFA),
      textColor: Color(0xFFC4B5FD),
      backgroundColor: Color(0x14A78BFA),
      borderColor: Color(0x33A78BFA),
    );
  }

  String _formatIncidentRelative(DateTime startedAt) {
    final diff = DateTime.now().difference(startedAt);
    if (diff.inDays > 0) {
      return '${diff.inDays}d';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return '${diff.inMinutes.clamp(0, 59)}m';
  }

  String _formatIncidentTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
