import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// Controller da Agenda Preventiva **global** (multi-K9).
///
/// Aditivo: não substitui [HealthScheduleController] (per-dog), que continua
/// sendo o caminho do modo K9 específico.
///
/// O catálogo autorizado é **injetado** pela camada superior — este controller
/// nunca resolve "todos os cães" e nunca duplica autorização. Catálogo vazio
/// produz estado próprio, sem emitir query.
///
/// Estados temporais são derivados na leitura pela mesma
/// [HealthScheduleTemporalPolicy] da Agenda per-dog: não existe segunda
/// implementação de lógica temporal.
class HealthScheduleGlobalController extends ChangeNotifier {
  HealthScheduleGlobalController({
    required HealthScheduleGlobalSource source,
    required HealthScheduleTemporalPolicy temporalPolicy,
    DateTime Function()? clock,
  }) : _source = source,
       _temporalPolicy = temporalPolicy,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final HealthScheduleGlobalSource _source;
  final HealthScheduleTemporalPolicy _temporalPolicy;
  final DateTime Function() _clock;

  HealthScheduleGlobalState _state = const HealthScheduleGlobalInitial();
  HealthScheduleGlobalQuery? _activeQuery;
  HealthScheduleGlobalSnapshot? _currentSnapshot;
  List<HealthScheduleItem> _domainItems = const [];
  bool _disposed = false;

  /// Invalida respostas em voo. Toda resposta carrega a geração em que nasceu;
  /// respostas de gerações antigas são descartadas.
  int _generation = 0;

  HealthScheduleGlobalState get state => _state;
  HealthScheduleGlobalQuery? get activeQuery => _activeQuery;

  @visibleForTesting
  List<HealthScheduleItem> get domainItemsForTest => _domainItems;

  @visibleForTesting
  int get generationForTest => _generation;

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  /// Define o catálogo autorizado e carrega a agenda global.
  ///
  /// Chamadas sucessivas invalidam a anterior: a resposta de um catálogo
  /// antigo nunca sobrescreve o estado de um catálogo novo.
  Future<void> setCatalog(
    Iterable<String> authorizedDogIds, {
    ScheduleLifecycleStatus lifecycleStatus = ScheduleLifecycleStatus.open,
    int? maxItems,
    int? chunkSize,
  }) async {
    if (_disposed) return;

    final query = HealthScheduleGlobalQuery(
      authorizedDogIds: authorizedDogIds,
      lifecycleStatus: lifecycleStatus,
      maxItems: maxItems ?? HealthScheduleGlobalQuery.defaultMaxItems,
      chunkSize: chunkSize ?? HealthScheduleGlobalQuery.defaultChunkSize,
    );

    final generation = ++_generation;
    _activeQuery = query;
    _currentSnapshot = null;
    _domainItems = const [];

    // Catálogo vazio: estado próprio, ZERO query. Não é "agenda em dia".
    if (query.isEmptyCatalog) {
      _setState(const HealthScheduleGlobalNoCatalog());
      return;
    }

    _setState(const HealthScheduleGlobalLoading());
    await _load(query, generation: generation, preserveOnFailure: false);
  }

  /// Recarrega o catálogo vigente.
  ///
  /// Preserva dados anteriores durante a operação (mesmo padrão do per-dog):
  /// falha de refresh não apaga a lista já exibida.
  Future<void> refresh() async {
    if (_disposed) return;
    final query = _activeQuery;
    if (query == null) {
      throw StateError('refresh exige catálogo ativo (chame setCatalog)');
    }

    final generation = ++_generation;

    if (query.isEmptyCatalog) {
      _setState(const HealthScheduleGlobalNoCatalog());
      return;
    }

    final existing = _currentSnapshot;
    if (existing != null && existing.items.isNotEmpty) {
      final refreshing = existing.copyWith(
        isRefreshing: true,
        clearLastRefreshError: true,
        lastRefreshWasOffline: false,
      );
      _currentSnapshot = refreshing;
      _setState(HealthScheduleGlobalData(snapshot: refreshing));
    } else {
      _setState(const HealthScheduleGlobalLoading());
    }

    await _load(query, generation: generation, preserveOnFailure: true);
  }

  /// Reaplica a derivação temporal com o relógio atual, sem I/O.
  ///
  /// A passagem do tempo muda `today` → `overdue` sem nova leitura: nenhum
  /// estado temporal é persistido nem consultado.
  void recomputeTemporalStates() {
    if (_disposed) return;
    final snapshot = _currentSnapshot;
    if (snapshot == null || _domainItems.isEmpty) return;

    final rebuilt = _projectAndGroup(_domainItems);
    final next = snapshot.copyWith(
      items: rebuilt.items,
      groups: rebuilt.groups,
    );
    _currentSnapshot = next;
    _setState(HealthScheduleGlobalData(snapshot: next));
  }

  Future<void> _load(
    HealthScheduleGlobalQuery query, {
    required int generation,
    required bool preserveOnFailure,
  }) async {
    try {
      final result = await _source.loadGlobal(query);
      if (!_isCurrent(generation)) return;

      _domainItems = result.items;
      final projected = _projectAndGroup(result.items);

      if (projected.items.isEmpty) {
        _currentSnapshot = null;
        _setState(
          HealthScheduleGlobalEmpty(catalogSize: query.authorizedDogIds.length),
        );
        return;
      }

      final snapshot = HealthScheduleGlobalSnapshot(
        items: projected.items,
        groups: projected.groups,
        truncated: result.truncated,
        catalogSize: query.authorizedDogIds.length,
      );
      _currentSnapshot = snapshot;
      _setState(HealthScheduleGlobalData(snapshot: snapshot));
    } on HealthScheduleSourceException catch (e) {
      if (!_isCurrent(generation)) return;
      _applyFailure(e, preserveOnFailure: preserveOnFailure);
    } catch (e) {
      if (!_isCurrent(generation)) return;
      _applyFailure(
        HealthScheduleSourceException(e.toString()),
        preserveOnFailure: preserveOnFailure,
      );
    }
  }

  /// Traduz falha preservando a natureza do erro.
  ///
  /// `permission-denied` e erro técnico permanecem estados distintos e nunca
  /// viram lista vazia.
  void _applyFailure(
    HealthScheduleSourceException error, {
    required bool preserveOnFailure,
  }) {
    final existing = _currentSnapshot;
    if (preserveOnFailure && existing != null && existing.items.isNotEmpty) {
      final preserved = existing.copyWith(
        isRefreshing: false,
        lastRefreshError: error.message,
        lastRefreshWasOffline: error.isOffline,
      );
      _currentSnapshot = preserved;
      _setState(HealthScheduleGlobalData(snapshot: preserved));
      return;
    }

    _currentSnapshot = null;
    _domainItems = const [];
    if (error.isPermissionDenied) {
      _setState(HealthScheduleGlobalPermissionDenied(message: error.message));
      return;
    }
    _setState(
      HealthScheduleGlobalError(
        message: error.message,
        isOffline: error.isOffline,
      ),
    );
  }

  _ProjectedItems _projectAndGroup(List<HealthScheduleItem> domainItems) {
    final now = _clock();
    final views = domainItems
        .map(
          (item) => HealthScheduleItemView.fromDomain(
            item,
            policy: _temporalPolicy,
            now: now,
          ),
        )
        .toList(growable: false);
    final sorted = sortScheduleItems(views);
    return _ProjectedItems(items: sorted, groups: groupScheduleItems(sorted));
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setState(HealthScheduleGlobalState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _ProjectedItems {
  const _ProjectedItems({required this.items, required this.groups});

  final List<HealthScheduleItemView> items;
  final HealthScheduleGroups groups;
}
