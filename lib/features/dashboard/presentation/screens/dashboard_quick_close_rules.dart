part of 'dashboard_screen.dart';

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
        'BO elaborado',
        'Sem constatação',
      ];
    default:
      return const ['Apoio prestado', 'BO elaborado', 'Sem constatação'];
  }
}

String _buildQuickCloseResultSummary({
  required Set<String> selectedOutcomes,
  required bool operationalSuccess,
}) {
  if (_containsOutcome(selectedOutcomes, 'Droga apreendida')) {
    return 'Apreensão positiva';
  }
  if (_containsOutcome(selectedOutcomes, 'Pessoa localizada')) {
    return 'Sucesso';
  }
  if (_containsOutcome(selectedOutcomes, 'Indivíduo detido')) {
    return 'Indivíduo detido';
  }
  if (_containsOutcome(selectedOutcomes, 'Vítima socorrida')) {
    return 'Vítima socorrida';
  }
  if (_containsOutcome(selectedOutcomes, 'Encaminhamento médico')) {
    return 'Encaminhamento médico';
  }
  if (_containsOutcome(selectedOutcomes, 'Trânsito sinalizado')) {
    return 'Trânsito sinalizado';
  }
  if (_containsOutcome(selectedOutcomes, 'Local preservado')) {
    return 'Local preservado';
  }
  if (_containsOutcome(selectedOutcomes, 'Ação educativa concluída')) {
    return 'Ação educativa concluída';
  }
  if (_containsOutcome(selectedOutcomes, 'Apoio prestado')) {
    return 'Apoio prestado';
  }
  if (_containsOutcome(selectedOutcomes, 'BO elaborado')) {
    return 'BO elaborado';
  }
  if (_containsOutcome(selectedOutcomes, 'Sem constatação')) {
    return 'Sem constatação';
  }
  return operationalSuccess ? 'Êxito' : 'Sem êxito';
}

IconData _iconForOutcome(String outcome) {
  final normalized = _normalizeQuickCloseLabel(outcome);
  if (normalized.contains('droga') || normalized.contains('apreens')) {
    return Icons.inventory_2_rounded;
  }
  if (normalized.contains('detido') || normalized.contains('preso')) {
    return Icons.gpp_good_rounded;
  }
  if (normalized.contains('localiz')) {
    return Icons.location_searching_rounded;
  }
  if (_isSupportOutcome(normalized)) {
    return Icons.volunteer_activism_rounded;
  }
  if (normalized.contains('sem constat')) {
    return Icons.search_off_rounded;
  }
  return Icons.fact_check_rounded;
}

Color _iconColorForOutcome(String outcome) {
  final normalized = _normalizeQuickCloseLabel(outcome);
  if (normalized.contains('droga') || normalized.contains('apreens')) {
    return const Color(0xFFFBBF24);
  }
  if (normalized.contains('detido') || normalized.contains('preso')) {
    return const Color(0xFFFB7185);
  }
  if (normalized.contains('localiz')) {
    return const Color(0xFF38BDF8);
  }
  if (_isSupportOutcome(normalized)) {
    return const Color(0xFF2DD4BF);
  }
  if (normalized.contains('sem constat')) {
    return const Color(0xFF94A3B8);
  }
  return const Color(0xFFA78BFA);
}

Color _textColorForOutcome(String outcome) {
  final normalized = _normalizeQuickCloseLabel(outcome);
  if (normalized.contains('droga') || normalized.contains('apreens')) {
    return const Color(0xFFFCD34D);
  }
  if (normalized.contains('detido') || normalized.contains('preso')) {
    return const Color(0xFFFDA4AF);
  }
  if (normalized.contains('localiz')) {
    return const Color(0xFF7DD3FC);
  }
  if (_isSupportOutcome(normalized)) {
    return const Color(0xFF99F6E4);
  }
  if (normalized.contains('sem constat')) {
    return const Color(0xFFCBD5E1);
  }
  return const Color(0xFFC4B5FD);
}

Color _borderColorForOutcome(String outcome) {
  final normalized = _normalizeQuickCloseLabel(outcome);
  if (normalized.contains('droga') || normalized.contains('apreens')) {
    return const Color(0x33FBBF24);
  }
  if (normalized.contains('detido') || normalized.contains('preso')) {
    return const Color(0x33FB7185);
  }
  if (normalized.contains('localiz')) {
    return const Color(0x3338BDF8);
  }
  if (_isSupportOutcome(normalized)) {
    return const Color(0x332DD4BF);
  }
  if (normalized.contains('sem constat')) {
    return const Color(0x3394A3B8);
  }
  return const Color(0x33A78BFA);
}

Color _backgroundColorForOutcome(String outcome) {
  final normalized = _normalizeQuickCloseLabel(outcome);
  if (normalized.contains('droga') || normalized.contains('apreens')) {
    return const Color(0x14FBBF24);
  }
  if (normalized.contains('detido') || normalized.contains('preso')) {
    return const Color(0x14FB7185);
  }
  if (normalized.contains('localiz')) {
    return const Color(0x1438BDF8);
  }
  if (_isSupportOutcome(normalized)) {
    return const Color(0x142DD4BF);
  }
  if (normalized.contains('sem constat')) {
    return const Color(0x1494A3B8);
  }
  return const Color(0x14A78BFA);
}

bool _containsOutcome(Set<String> outcomes, String expected) {
  final normalizedExpected = _normalizeQuickCloseLabel(expected);
  return outcomes.any(
    (outcome) => _normalizeQuickCloseLabel(outcome) == normalizedExpected,
  );
}

bool _isSupportOutcome(String normalized) {
  return normalized.contains('apoio') ||
      normalized.contains('encaminhamento') ||
      normalized.contains('socorrida') ||
      normalized.contains('transito') ||
      normalized.contains('preservado');
}

String _normalizeQuickCloseLabel(String value) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  return value.toLowerCase().split('').map((char) {
    return accents[char] ?? char;
  }).join();
}
