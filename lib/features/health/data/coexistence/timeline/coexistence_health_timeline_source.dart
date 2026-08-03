import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_timeline_cursor_codec.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/firestore_timeline_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_mappers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/multi_source_timeline_paginator.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Source concreta temporária de coexistência read-only da timeline Health v1.
///
/// Ponte até a projeção canônica `health_timeline` (server-side).
/// Não escreve, não migra, não conecta shell nesta fase.
class CoexistenceHealthTimelineSource implements HealthTimelineSource {
  CoexistenceHealthTimelineSource({
    FirebaseFirestore? firestore,
    List<HealthTimelineSourceReader>? readers,
    HealthTimelineSourceReader? vaccinationFallbackReader,
    Future<bool> Function(String dogId)? resolveVaccinationFallback,
  }) : _firestore = firestore,
       _injectedReaders = readers,
       _vaccinationFallbackReader = vaccinationFallbackReader,
       _resolveVaccinationFallback = resolveVaccinationFallback;

  final FirebaseFirestore? _firestore;
  final List<HealthTimelineSourceReader>? _injectedReaders;
  final HealthTimelineSourceReader? _vaccinationFallbackReader;
  final Future<bool> Function(String dogId)? _resolveVaccinationFallback;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    try {
      final setup = await _setupReaders(query);
      final paginator = MultiSourceTimelinePaginator(readers: setup.readers);
      return await paginator.loadPage(
        query,
        vaccinationFallbackEnabled: setup.vacEnabled,
        vaccinationFallbackDecided: setup.vacDecided,
      );
    } on HealthTimelineSourceException {
      rethrow;
    } on FirebaseException catch (e) {
      throw HealthTimelineSourceException(
        TimelineErrorSanitizer.publicMessage(e, code: e.code),
        isOffline: TimelineErrorSanitizer.looksLikeOffline(e, code: e.code),
      );
    } catch (e) {
      if (e is HealthTimelineSourceException) rethrow;
      throw HealthTimelineSourceException(
        TimelineErrorSanitizer.publicMessage(e),
      );
    }
  }

  Future<
    ({
      List<HealthTimelineSourceReader> readers,
      bool vacEnabled,
      bool vacDecided,
    })
  >
  _setupReaders(HealthTimelineQuery query) async {
    if (_injectedReaders != null) {
      return (
        readers: List<HealthTimelineSourceReader>.of(_injectedReaders),
        vacEnabled: false,
        vacDecided: true,
      );
    }

    final fs = _firestore ?? FirebaseFirestore.instance;
    final base = <HealthTimelineSourceReader>[
      FirestoreTimelineReaders.healthEvents(firestore: fs),
      FirestoreTimelineReaders.weightRecords(firestore: fs),
      FirestoreTimelineReaders.mealLogs(firestore: fs),
      FirestoreTimelineReaders.supplementLogs(firestore: fs),
      FirestoreTimelineReaders.feedingEvents(firestore: fs),
      FirestoreTimelineReaders.feedings(firestore: fs),
    ];

    // decode lança se cursor inválido — não decide fallback com cursor podre.
    final decoded = CoexistenceTimelineCursorCodec.decode(
      query.cursor,
      query: query,
    );

    late final bool vacEnabled;
    late final bool vacDecided;
    if (decoded != null && decoded.vaccinationFallbackDecided) {
      vacEnabled = decoded.vaccinationFallbackEnabled;
      vacDecided = true;
    } else {
      vacEnabled = await _shouldEnableVaccinationFallback(query.dogId);
      vacDecided = true;
    }

    if (vacEnabled) {
      base.add(
        _vaccinationFallbackReader ??
            FirestoreTimelineReaders.legacyVacinas(firestore: fs),
      );
    }

    return (
      readers: _filterReadersByTypes(base, query),
      vacEnabled: vacEnabled,
      vacDecided: vacDecided,
    );
  }

  List<HealthTimelineSourceReader> _filterReadersByTypes(
    List<HealthTimelineSourceReader> readers,
    HealthTimelineQuery query,
  ) {
    if (query.types.isEmpty) return readers;
    final types = query.types;
    return readers
        .where((r) {
          switch (r.sourceKey) {
            case HealthTimelineMappers.sourceWeightRecords:
              return types.contains(HealthTimelineType.weight);
            case HealthTimelineMappers.sourceFeedingEvents:
            case HealthTimelineMappers.sourceFeedings:
            case HealthTimelineMappers.sourceMealLogs:
              return types.contains(HealthTimelineType.meal);
            case HealthTimelineMappers.sourceSupplementLogs:
              return types.contains(HealthTimelineType.supplement);
            case HealthTimelineMappers.sourceVacinas:
              return types.contains(HealthTimelineType.vaccination);
            case HealthTimelineMappers.sourceHealthEvents:
              return true;
            default:
              return true;
          }
        })
        .toList(growable: false);
  }

  Future<bool> _shouldEnableVaccinationFallback(String dogId) async {
    if (_resolveVaccinationFallback != null) {
      return _resolveVaccinationFallback(dogId);
    }
    // Conservador: sem resolver injetado, não aciona fallback.
    // Evita dual-count vacinas ↔ health_events sem prova conclusiva.
    // Ausência de vacina "nesta página" de health_events NÃO é prova.
    return false;
  }
}

/// Factories de conveniência.
abstract final class CoexistenceHealthTimelineSourceFactory {
  CoexistenceHealthTimelineSourceFactory._();

  static CoexistenceHealthTimelineSource forReaders(
    List<HealthTimelineSourceReader> readers,
  ) {
    return CoexistenceHealthTimelineSource(readers: readers);
  }

  static CoexistenceHealthTimelineSource forFirestore({
    FirebaseFirestore? firestore,
    bool enableVaccinationFallback = false,
  }) {
    return CoexistenceHealthTimelineSource(
      firestore: firestore,
      resolveVaccinationFallback: (_) async => enableVaccinationFallback,
    );
  }
}
