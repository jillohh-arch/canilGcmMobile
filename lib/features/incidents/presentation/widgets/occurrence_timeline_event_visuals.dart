part of 'occurrence_timeline_preview.dart';

class _OccurrenceEventVisual {
  final Color color;
  final IconData icon;
  final String? assetPath;

  const _OccurrenceEventVisual({
    required this.color,
    required this.icon,
    this.assetPath,
  });
}

_OccurrenceEventVisual _visualForTimelineTitle(String title, Color fallback) {
  final value = _normalizeTimelineTitle(title);

  if (_matchesTimelineTitle(value, const ['inicio', 'registro inicial'])) {
    return const _OccurrenceEventVisual(
      color: AppTheme.primary,
      icon: Icons.play_arrow_rounded,
    );
  }

  if (_matchesTimelineTitle(value, const [
    'sem alteracao',
    'sem constatacao',
    'nao constatado',
    'nada ilicito',
    'nada localizado',
  ])) {
    return const _OccurrenceEventVisual(
      color: Color(0xFFCFD8DC),
      icon: Icons.highlight_off_rounded,
      assetPath: 'assets/images/actions/k9_naoConstatado_timeline.png',
    );
  }

  if (value.contains('abordagem')) {
    return const _OccurrenceEventVisual(
      color: Color(0xFFFFB300),
      icon: Icons.person_search_rounded,
      assetPath: 'assets/images/actions/k9_abordagem_timeline.png',
    );
  }

  if (_matchesTimelineTitle(value, const ['cao em acao', 'k9', 'emprego'])) {
    return const _OccurrenceEventVisual(
      color: Color(0xFF00A8FF),
      icon: Icons.pets_rounded,
      assetPath: 'assets/images/actions/k9_emprego_timeline.png',
    );
  }

  if (value.contains('busca')) {
    return const _OccurrenceEventVisual(
      color: Color(0xFF44D62C),
      icon: Icons.search_rounded,
      assetPath: 'assets/images/actions/k9_busca_timeline.png',
    );
  }

  if (_matchesTimelineTitle(value, const [
    'material',
    'entorpecente',
    'droga',
    'arma',
    'municao',
    'objeto',
  ])) {
    return const _OccurrenceEventVisual(
      color: Color(0xFFB388FF),
      icon: Icons.inventory_2_rounded,
      assetPath: 'assets/images/actions/k9_materialEncontrado_timeline.png',
    );
  }

  if (_matchesTimelineTitle(value, const ['parte', 'conduz', 'detido'])) {
    return const _OccurrenceEventVisual(
      color: Color(0xFFFF8A3D),
      icon: Icons.person_rounded,
      assetPath: 'assets/images/actions/k9_parteConduzida_timeline.png',
    );
  }

  if (value.contains('encerr')) {
    return const _OccurrenceEventVisual(
      color: AppTheme.primary,
      icon: Icons.flag_rounded,
    );
  }

  return _OccurrenceEventVisual(color: fallback, icon: Icons.timeline_rounded);
}

bool _matchesTimelineTitle(String value, List<String> tokens) {
  return tokens.any(value.contains);
}

String _normalizeTimelineTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');
}
