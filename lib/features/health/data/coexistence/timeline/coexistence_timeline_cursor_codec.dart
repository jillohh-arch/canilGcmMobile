import 'dart:convert';

import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_entry_codec.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Estado de uma subfonte no cursor composto.
final class CoexistenceSourceCursorState {
  const CoexistenceSourceCursorState({this.after, this.exhausted = false});

  final HealthTimelineSourceReaderCursor? after;
  final bool exhausted;

  Map<String, Object?> toJson() => {
    if (after != null)
      'after': {
        'atMs': after!.lastOccurredAt.toUtc().millisecondsSinceEpoch,
        // lastId = id **global** da entrada (ou docId bruto no avanço de lixo).
        'id': after!.lastId,
      },
    'exhausted': exhausted,
  };

  static CoexistenceSourceCursorState fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('source state inválido');
    }
    final map = Map<String, dynamic>.from(raw);
    HealthTimelineSourceReaderCursor? after;
    final a = map['after'];
    if (a != null) {
      if (a is! Map) {
        throw const FormatException('after inválido');
      }
      final atMs = a['atMs'];
      final id = a['id'];
      if (atMs is! int || id is! String || id.isEmpty) {
        throw const FormatException('posição de fonte inválida');
      }
      after = HealthTimelineSourceReaderCursor(
        lastOccurredAt: DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true),
        lastId: id,
      );
    }
    return CoexistenceSourceCursorState(
      after: after,
      exhausted: map['exhausted'] == true,
    );
  }
}

/// Estado completo do cursor de coexistência (self-contained).
///
/// Contém:
/// - posição por fonte;
/// - residual **mínimo** (já lido, ainda não emitido — sem PHI extra);
/// - decisão de fallback de vacinação;
/// - identidade de filtro (para rejeitar cursor de outra query).
final class CoexistenceTimelineCursorState {
  CoexistenceTimelineCursorState({
    required this.version,
    required this.dogId,
    required this.filterFingerprint,
    required Map<String, CoexistenceSourceCursorState> sources,
    required List<HealthTimelineEntryView> residual,
    this.vaccinationFallbackEnabled = false,
    this.vaccinationFallbackDecided = false,
  }) : sources = Map.unmodifiable(
         Map<String, CoexistenceSourceCursorState>.of(sources),
       ),
       residual = List.unmodifiable(List<HealthTimelineEntryView>.of(residual));

  /// v2: residual slim (sem PHI clínico desnecessário).
  static const int currentVersion = 2;

  final int version;
  final String dogId;
  final String filterFingerprint;
  final Map<String, CoexistenceSourceCursorState> sources;
  final List<HealthTimelineEntryView> residual;
  final bool vaccinationFallbackEnabled;
  final bool vaccinationFallbackDecided;

  CoexistenceTimelineCursorState copyWith({
    Map<String, CoexistenceSourceCursorState>? sources,
    List<HealthTimelineEntryView>? residual,
    bool? vaccinationFallbackEnabled,
    bool? vaccinationFallbackDecided,
  }) {
    return CoexistenceTimelineCursorState(
      version: version,
      dogId: dogId,
      filterFingerprint: filterFingerprint,
      sources: sources ?? this.sources,
      residual: residual ?? this.residual,
      vaccinationFallbackEnabled:
          vaccinationFallbackEnabled ?? this.vaccinationFallbackEnabled,
      vaccinationFallbackDecided:
          vaccinationFallbackDecided ?? this.vaccinationFallbackDecided,
    );
  }
}

/// Codec opaco: estado ↔ [HealthTimelineCursor.token] (base64url JSON).
///
/// Regras:
/// - cursor corrompido / de outra query → exceção controlada (nunca reinício silencioso);
/// - residual limitado (tamanho e contagem);
/// - sem PHI clínico extra no residual.
abstract final class CoexistenceTimelineCursorCodec {
  CoexistenceTimelineCursorCodec._();

  /// Limite de entradas residual no cursor (evita crescimento ilimitado).
  static const int maxResidualEntries = 250;

  /// Limite de bytes do token UTF-8 **antes** do base64 (defensivo).
  static const int maxTokenUtf8Bytes = 48 * 1024;

  static String filterFingerprint(HealthTimelineQuery query) {
    final types = query.types.map((t) => t.wireName).toList()..sort();
    final period = query.period;
    final prof = query.professional;
    return [
      query.dogId,
      types.join(','),
      period.start?.toUtc().toIso8601String() ?? '',
      period.end?.toUtc().toIso8601String() ?? '',
      query.caseId ?? '',
      prof?.name ?? '',
      prof?.registrationType?.wireName ?? '',
      prof?.registrationNumber ?? '',
      '${query.pageSize}',
    ].join('|');
  }

  static HealthTimelineCursor encode(CoexistenceTimelineCursorState state) {
    if (state.residual.length > maxResidualEntries) {
      throw const HealthTimelineSourceException(
        'Residual de paginação excedeu o limite seguro; '
        'não é possível continuar com integridade garantida.',
      );
    }
    final payload = <String, Object?>{
      'v': state.version,
      'dogId': state.dogId,
      'fp': state.filterFingerprint,
      'sources': {
        for (final e in state.sources.entries) e.key: e.value.toJson(),
      },
      'residual': [
        for (final item in state.residual)
          HealthTimelineEntryCodec.encode(item),
      ],
      'vacFb': state.vaccinationFallbackEnabled,
      'vacDecided': state.vaccinationFallbackDecided,
    };
    final json = jsonEncode(payload);
    final utf8Bytes = utf8.encode(json);
    if (utf8Bytes.length > maxTokenUtf8Bytes) {
      throw const HealthTimelineSourceException(
        'Cursor de paginação excedeu o tamanho máximo permitido.',
      );
    }
    final token = base64Url.encode(utf8Bytes);
    return HealthTimelineCursor(token);
  }

  /// Decodifica cursor opcional.
  ///
  /// - `cursor == null` → `null` (primeira página);
  /// - cursor presente mas inválido / de outra query → lança
  ///   [HealthTimelineSourceException] (nunca reinicia silenciosamente).
  static CoexistenceTimelineCursorState? decode(
    HealthTimelineCursor? cursor, {
    required HealthTimelineQuery query,
  }) {
    if (cursor == null) return null;
    try {
      final json = utf8.decode(base64Url.decode(cursor.token));
      final map = jsonDecode(json);
      if (map is! Map) {
        throw const FormatException('payload não é objeto');
      }
      final data = Map<String, dynamic>.from(map);
      final version = data['v'];
      if (version != CoexistenceTimelineCursorState.currentVersion) {
        throw FormatException('versão de cursor desconhecida: $version');
      }
      final dogId = data['dogId']?.toString();
      final fp = data['fp']?.toString();
      if (dogId == null || dogId.isEmpty || fp == null) {
        throw const FormatException('campos obrigatórios ausentes');
      }
      if (dogId != query.dogId) {
        throw const FormatException('cursor de outro cão');
      }
      if (fp != filterFingerprint(query)) {
        throw const FormatException('cursor de outra query/filtro');
      }

      final sourcesRaw = data['sources'];
      if (sourcesRaw != null && sourcesRaw is! Map) {
        throw const FormatException('sources inválido');
      }
      final sources = <String, CoexistenceSourceCursorState>{};
      if (sourcesRaw is Map) {
        for (final e in sourcesRaw.entries) {
          sources[e.key.toString()] = CoexistenceSourceCursorState.fromJson(
            e.value,
          );
        }
      }

      final residual = <HealthTimelineEntryView>[];
      final residualRaw = data['residual'];
      if (residualRaw != null && residualRaw is! List) {
        throw const FormatException('residual inválido');
      }
      if (residualRaw is List) {
        if (residualRaw.length > maxResidualEntries) {
          throw const FormatException('residual excede limite');
        }
        for (final item in residualRaw) {
          final decoded = HealthTimelineEntryCodec.tryDecode(item);
          if (decoded == null) {
            throw const FormatException('entrada residual inválida');
          }
          residual.add(decoded);
        }
      }

      return CoexistenceTimelineCursorState(
        version: CoexistenceTimelineCursorState.currentVersion,
        dogId: dogId,
        filterFingerprint: fp,
        sources: sources,
        residual: residual,
        vaccinationFallbackEnabled: data['vacFb'] == true,
        vaccinationFallbackDecided: data['vacDecided'] == true,
      );
    } on HealthTimelineSourceException {
      rethrow;
    } catch (_) {
      // Nunca expõe FormatException, token, JSON ou stack ao caller.
      throw const HealthTimelineSourceException(
        'Cursor de paginação inválido ou incompatível com a consulta atual.',
      );
    }
  }

  /// @nodoc — compatível com testes legados; preferir [decode].
  static CoexistenceTimelineCursorState? tryDecode(
    HealthTimelineCursor? cursor, {
    required HealthTimelineQuery query,
  }) {
    if (cursor == null) return null;
    try {
      return decode(cursor, query: query);
    } on HealthTimelineSourceException {
      return null;
    }
  }

  static CoexistenceTimelineCursorState initial({
    required HealthTimelineQuery query,
    required Iterable<String> sourceKeys,
    bool vaccinationFallbackEnabled = false,
    bool vaccinationFallbackDecided = false,
  }) {
    return CoexistenceTimelineCursorState(
      version: CoexistenceTimelineCursorState.currentVersion,
      dogId: query.dogId,
      filterFingerprint: filterFingerprint(query),
      sources: {
        for (final k in sourceKeys) k: const CoexistenceSourceCursorState(),
      },
      residual: const [],
      vaccinationFallbackEnabled: vaccinationFallbackEnabled,
      vaccinationFallbackDecided: vaccinationFallbackDecided,
    );
  }

  /// Tamanho do token em caracteres (base64url).
  static int tokenCharLength(HealthTimelineCursor cursor) =>
      cursor.token.length;

  /// Tamanho aproximado do JSON decodificado em bytes UTF-8.
  static int decodedUtf8ByteLength(HealthTimelineCursor cursor) {
    try {
      return utf8.decode(base64Url.decode(cursor.token)).length;
    } catch (_) {
      return cursor.token.length;
    }
  }
}
