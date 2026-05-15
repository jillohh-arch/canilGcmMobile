part of 'history_screen.dart';

/// Modelo unificado para um item da timeline do histórico.
class HistoryEntry {
  final String? id;
  final String category; // 'Rotina', 'Saude', 'Treino', 'Ocorrência'
  final dynamic originalModel;
  final DateTime time;
  final String title;
  final String subtitle;
  final String location;
  final String authorId;
  final String authorName;
  final bool isInProgress;
  final DateTime? editedAt;
  final Map<String, dynamic> details;

  HistoryEntry({
    this.id,
    required this.category,
    this.originalModel,
    required this.time,
    required this.title,
    this.subtitle = '',
    this.location = '',
    this.authorId = '',
    this.authorName = '',
    this.isInProgress = false,
    this.editedAt,
    required this.details,
  });

  /// Cor do ícone baseada na categoria
  Color get categoryColor {
    switch (category) {
      case 'Rotina':
        return _purpleAccent;
      case 'Saude':
        return _redAccent;
      case 'Treino':
        return _yellowAccent;
      case 'Ocorrência':
        return _cyanAccent;
      default:
        return _textMuted;
    }
  }

  /// Ícone baseado na categoria
  String get categoryEmoji {
    switch (category) {
      case 'Rotina':
        return '🍖';
      case 'Saude':
        return '⚕';
      case 'Treino':
        return '🎯';
      case 'Ocorrência':
        return '🛡';
      default:
        return '📋';
    }
  }

  /// IconData baseado na categoria
  IconData get categoryIcon {
    switch (category) {
      case 'Rotina':
        return Icons.pets_rounded;
      case 'Saude':
        return Icons.medical_services_rounded;
      case 'Treino':
        return Icons.track_changes_rounded;
      case 'Ocorrência':
        return Icons.shield_rounded;
      default:
        return Icons.info_outline;
    }
  }

  /// Tag Hero única para animação
  String get heroTag => '${category}_${id ?? time.millisecondsSinceEpoch}';
}

/// Agrupamento de entries por dia
class HistoryDayGroup {
  final DateTime date;
  final String label; // 'HOJE', 'ONTEM', ou data formatada
  final String dateFormatted; // '14 de maio · quarta'
  final List<HistoryEntry> entries;

  HistoryDayGroup({
    required this.date,
    required this.label,
    required this.dateFormatted,
    required this.entries,
  });
}
