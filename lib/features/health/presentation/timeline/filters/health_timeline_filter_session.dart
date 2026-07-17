import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_selection.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

/// Sessão de filtros com **draft** vs **applied** (3D-A).
///
/// Apply semanticamente igual (query) **não** dispara reload.
/// [periodOrigin] pode atualizar a UI sem nova query se as datas forem iguais.
class HealthTimelineFilterSession extends ChangeNotifier {
  HealthTimelineFilterSession({
    required HealthTimelineController controller,
    required String dogId,
    int pageSize = HealthTimelineQuery.defaultPageSize,
    DateTime Function()? now,
    HealthTimelineFilterSelection? initialApplied,
  }) : _controller = controller,
       _dogId = dogId.trim(),
       _pageSize = pageSize,
       _now = now ?? DateTime.now,
       _applied = initialApplied ?? HealthTimelineFilterSelection.empty(),
       _draft = _defensiveCopy(
         initialApplied ?? HealthTimelineFilterSelection.empty(),
       ) {
    if (_dogId.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'não pode ser vazio');
    }
  }

  final HealthTimelineController _controller;
  final DateTime Function() _now;

  String _dogId;
  int _pageSize;
  HealthTimelineFilterSelection _applied;
  HealthTimelineFilterSelection _draft;
  bool _draftOpen = false;

  String get dogId => _dogId;
  int get pageSize => _pageSize;
  HealthTimelineFilterSelection get applied => _applied;
  HealthTimelineFilterSelection get draft => _draft;
  bool get isDraftOpen => _draftOpen;
  DateTime now() => _now();

  int get activeFilterCount => _applied.activeFilterCount;
  bool get hasActiveFilters => _applied.isNotEmpty;

  void openDraft() {
    _draft = _defensiveCopy(_applied);
    _draftOpen = true;
    notifyListeners();
  }

  void cancelDraft() {
    _draft = _defensiveCopy(_applied);
    _draftOpen = false;
    notifyListeners();
  }

  void clearDraft() {
    _draft = HealthTimelineFilterSelection.empty();
    notifyListeners();
  }

  void setDraft(HealthTimelineFilterSelection selection) {
    _draft = _defensiveCopy(selection);
    notifyListeners();
  }

  void setDraftTypes(Set<HealthTimelineType> types) {
    _draft = _draft.copyWith(types: Set<HealthTimelineType>.of(types));
    notifyListeners();
  }

  void toggleDraftType(HealthTimelineType type) {
    final next = Set<HealthTimelineType>.of(_draft.types);
    if (next.contains(type)) {
      next.remove(type);
    } else {
      next.add(type);
    }
    setDraftTypes(next);
  }

  void setDraftPeriod(
    HealthTimelinePeriod period, {
    required HealthTimelinePeriodPreset origin,
  }) {
    _draft = _draft.copyWith(period: period, periodOrigin: origin);
    notifyListeners();
  }

  void setDraftCaseId(String? caseId) {
    if (caseId == null || caseId.trim().isEmpty) {
      _draft = _draft.copyWith(clearCaseId: true);
    } else {
      _draft = _draft.copyWith(caseId: caseId);
    }
    notifyListeners();
  }

  void setDraftProfessional(HealthTimelineProfessionalFilter? professional) {
    if (professional == null) {
      _draft = _draft.copyWith(clearProfessional: true);
    } else {
      _draft = _draft.copyWith(professional: professional);
    }
    notifyListeners();
  }

  /// Aplica draft. No-op de [setQuery] se a query for semanticamente igual.
  Future<void> apply() async {
    final next = _defensiveCopy(_draft);
    final queryChanged = !_queryMatchesController(next);
    _applied = next;
    _draftOpen = false;
    notifyListeners();
    if (queryChanged) {
      await _pushApplied();
    }
  }

  Future<void> clearApplied() async {
    if (_applied.isEmpty) {
      _draft = HealthTimelineFilterSelection.empty();
      _draftOpen = false;
      notifyListeners();
      return;
    }
    _applied = HealthTimelineFilterSelection.empty();
    _draft = HealthTimelineFilterSelection.empty();
    _draftOpen = false;
    notifyListeners();
    await _pushApplied();
  }

  Future<void> removeAppliedTypes() async {
    if (!_applied.hasTypes) return;
    _applied = _applied.copyWith(types: const {});
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  /// Chip rápido “Todos”: limpa **somente** types (preserva period/case/professional).
  Future<void> applyQuickAllTypes() async {
    if (!_applied.hasTypes) {
      _draft = _defensiveCopy(_applied);
      notifyListeners();
      return;
    }
    _applied = _applied.copyWith(types: const {});
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  /// Chip rápido de tipo único (single-select). Preserva demais dimensões.
  Future<void> applyQuickType(HealthTimelineType type) async {
    final current = _applied.types;
    if (current.length == 1 && current.contains(type)) {
      _draft = _defensiveCopy(_applied);
      notifyListeners();
      return;
    }
    _applied = _applied.copyWith(types: {type});
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  /// true se a faixa rápida deve marcar “Todos” (types vazio).
  bool get isQuickAllSelected => !_applied.hasTypes;

  /// true se exatamente um tipo está aplicado e coincide com [type].
  bool isQuickTypeSelected(HealthTimelineType type) =>
      _applied.types.length == 1 && _applied.types.contains(type);

  /// Multi-type avançado: faixa rápida não finge seleção única.
  bool get hasAdvancedMultiTypeSelection => _applied.types.length > 1;

  Future<void> removeAppliedPeriod() async {
    if (!_applied.hasPeriod) return;
    _applied = _applied.copyWith(
      period: HealthTimelinePeriod(),
      periodOrigin: HealthTimelinePeriodPreset.allHistory,
    );
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  Future<void> removeAppliedCaseId() async {
    if (!_applied.hasCaseId) return;
    _applied = _applied.copyWith(clearCaseId: true);
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  Future<void> removeAppliedProfessional() async {
    if (!_applied.hasProfessional) return;
    _applied = _applied.copyWith(clearProfessional: true);
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  Future<void> applyCaseFilter(String caseId) async {
    final id = caseId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(caseId, 'caseId', 'não pode ser vazio');
    }
    if (_applied.caseId == id) {
      _draft = _defensiveCopy(_applied);
      notifyListeners();
      return;
    }
    _applied = _applied.copyWith(caseId: id);
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  Future<void> applyProfessionalFilter(
    HealthTimelineProfessionalFilter professional,
  ) async {
    if (_applied.professional == professional) {
      _draft = _defensiveCopy(_applied);
      notifyListeners();
      return;
    }
    _applied = _applied.copyWith(professional: professional);
    _draft = _defensiveCopy(_applied);
    notifyListeners();
    await _pushApplied();
  }

  void updateDogId(String dogId) {
    final n = dogId.trim();
    if (n.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'não pode ser vazio');
    }
    _dogId = n;
  }

  void updatePageSize(int pageSize) {
    if (pageSize <= 0 || pageSize > HealthTimelineQuery.maxPageSize) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    _pageSize = pageSize;
  }

  void syncFromControllerQuery() {
    final q = _controller.activeQuery;
    if (q == null) return;
    _dogId = q.dogId;
    _pageSize = q.pageSize;
    // Preserva periodOrigin se as datas da query coincidirem com applied.
    final fromQ = HealthTimelineFilterSelection.fromQuery(q);
    if (_applied.queryEquals(fromQ)) {
      _applied = _applied.copyWith(
        types: fromQ.types,
        period: fromQ.period,
        caseId: fromQ.caseId,
        professional: fromQ.professional,
      );
    } else {
      _applied = fromQ;
    }
    if (!_draftOpen) {
      _draft = _defensiveCopy(_applied);
    }
    notifyListeners();
  }

  bool _queryMatchesController(HealthTimelineFilterSelection selection) {
    final current = _controller.activeQuery;
    if (current == null) return false;
    final next = selection.toQuery(dogId: _dogId, pageSize: _pageSize);
    return current.withoutCursor().filterIdentity == next.filterIdentity;
  }

  Future<void> _pushApplied() async {
    final query = _applied.toQuery(dogId: _dogId, pageSize: _pageSize);
    await _controller.setQuery(query);
  }

  static HealthTimelineFilterSelection _defensiveCopy(
    HealthTimelineFilterSelection s,
  ) => HealthTimelineFilterSelection(
    types: Set<HealthTimelineType>.of(s.types),
    period: s.period,
    periodOrigin: s.periodOrigin,
    caseId: s.caseId,
    professional: s.professional,
  );
}
