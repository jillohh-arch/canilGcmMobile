import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';

/// Resultado da Agenda Preventiva **global** (bounded, sem paginação).
///
/// Esta foundation (HW-4B) entrega uma janela explicitamente limitada: não há
/// cursor. Paginação multi-chunk exige cursor por chunk e desempate estável na
/// própria query Firestore, o que mudaria a shape aprovada — decisão registrada
/// para o gate seguinte.
///
/// [truncated] existe para não confundir "cabe no limite" com "há mais dados":
/// a UI global completa depende de paginação real e deve tratar `truncated`
/// como bloqueio, não como lista completa.
final class HealthScheduleGlobalResult {
  HealthScheduleGlobalResult({
    required List<HealthScheduleItem> items,
    required this.truncated,
    required this.queriedChunks,
  }) : items = List.unmodifiable(List<HealthScheduleItem>.of(items));

  /// Agregados canônicos, ordenados globalmente e deduplicados.
  ///
  /// Sem estado temporal: a derivação é da policy de apresentação.
  final List<HealthScheduleItem> items;

  /// `true` quando o limite explícito cortou o conjunto.
  final bool truncated;

  /// Quantas queries bounded foram emitidas (0 = catálogo vazio, nenhuma I/O).
  final int queriedChunks;

  bool get isEmpty => items.isEmpty;

  factory HealthScheduleGlobalResult.empty() => HealthScheduleGlobalResult(
    items: const [],
    truncated: false,
    queriedChunks: 0,
  );
}
