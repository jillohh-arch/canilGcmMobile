part of 'dashboard_screen.dart';

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
