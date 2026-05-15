import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:canil_gcm/features/nutrition/data/nutrition_service.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

/// ViewModel de nutrição — gerencia prescrição vigente, refeições do dia,
/// histórico de refeições, conformidade alimentar e prescrições.
class NutritionViewModel extends ChangeNotifier {
  final NutritionService _service = NutritionService();

  // ─── Estado base ───────────────────────────────────────────────────
  NutritionPrescription? _prescription;
  NutritionPrescription? get prescription => _prescription;

  List<Feeding> _todayFeedings = [];
  List<Feeding> get todayFeedings => _todayFeedings;

  double _conformityPercent = 0.0;
  double get conformityPercent => _conformityPercent;

  bool _loading = false;
  bool get loading => _loading;

  String? _activeDogId;
  String? get activeDogId => _activeDogId;

  StreamSubscription<List<Feeding>>? _feedingsSub;

  // ─── Estado tela completa ──────────────────────────────────────────
  List<Feeding> _historyFeedings = [];
  List<Feeding> get historyFeedings => _historyFeedings;

  List<Feeding> _filteredFeedings = [];
  List<Feeding> get filteredFeedings => _filteredFeedings;

  List<NutritionPrescription> _prescriptionHistory = [];
  List<NutritionPrescription> get prescriptionHistory => _prescriptionHistory;

  bool _historyLoading = false;
  bool get historyLoading => _historyLoading;

  // Filtros
  String _filterType = 'todas'; // 'todas' | 'conformes' | 'divergencias'
  String get filterType => _filterType;

  String _filterPeriod = 'mes'; // 'semana' | 'mes'
  String get filterPeriod => _filterPeriod;

  // Conformidade detalhada (90 dias)
  int _totalFeedings90d = 0;
  int get totalFeedings90d => _totalFeedings90d;

  int _conformFeedings90d = 0;
  int get conformFeedings90d => _conformFeedings90d;

  int _divergentFeedings90d = 0;
  int get divergentFeedings90d => _divergentFeedings90d;

  double _conformity90d = 0.0;
  double get conformity90d => _conformity90d;

  // ─── Lifecycle ─────────────────────────────────────────────────────

  /// Inicializa o ViewModel para um cão específico.
  Future<void> loadForDog(String dogId) async {
    if (_activeDogId == dogId && !_loading) return;
    _activeDogId = dogId;
    _loading = true;
    notifyListeners();

    try {
      // Carrega prescrição vigente
      _prescription = await _service.getActivePrescription(dogId);
    } catch (e) {
      _prescription = null;
      debugPrint('[NutritionVM] Erro ao carregar prescrição: $e');
    }

    // Inicia stream de refeições do dia
    _feedingsSub?.cancel();
    _feedingsSub = _service.watchTodayFeedings(dogId).listen(
      (feedings) {
        _todayFeedings = feedings;
        _calculateConformity();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[NutritionVM] Erro no stream de refeições: $e');
        _todayFeedings = [];
        notifyListeners();
      },
    );

    _loading = false;
    notifyListeners();
  }

  /// Carrega dados completos para a tela de nutrição (histórico 90 dias).
  Future<void> loadFullHistory(String dogId) async {
    _historyLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final from90d = now.subtract(const Duration(days: 90));

      // Carrega em paralelo
      final results = await Future.wait([
        _service.getFeedings(dogId, from: from90d),
        _service.getPrescriptionHistory(dogId),
      ]);

      _historyFeedings = results[0] as List<Feeding>;
      _prescriptionHistory = results[1] as List<NutritionPrescription>;

      // Calcula conformidade 90 dias
      _totalFeedings90d = _historyFeedings.length;
      _conformFeedings90d =
          _historyFeedings.where((f) => f.divergencePercent.abs() <= 10.0).length;
      _divergentFeedings90d = _totalFeedings90d - _conformFeedings90d;
      _conformity90d =
          _totalFeedings90d > 0 ? (_conformFeedings90d / _totalFeedings90d) * 100 : 0.0;

      // Aplica filtros
      _applyFilters();
    } catch (e) {
      debugPrint('[NutritionVM] Erro ao carregar histórico: $e');
      _historyFeedings = [];
      _prescriptionHistory = [];
      _filteredFeedings = [];
    }

    _historyLoading = false;
    notifyListeners();
  }

  /// Registra uma nova refeição.
  Future<void> addFeeding(String dogId, Feeding feeding) async {
    await _service.addFeeding(dogId, feeding);
    // O stream atualiza automaticamente
  }

  /// Registra refeição com upload de foto da balança.
  Future<void> addFeedingWithPhoto(String dogId, Feeding feeding, File? photo) async {
    final feedingId = await _service.addFeeding(dogId, feeding);
    if (photo != null) {
      try {
        final url = await _service.uploadFeedingPhoto(dogId, photo);
        if (url != null) {
          await _service.updateFeedingPhoto(dogId, feedingId, url);
        }
      } catch (e) {
        debugPrint('[NutritionVM] Erro upload foto (feeding salvo): $e');
        // Feeding já foi salvo, foto falhou — não propaga erro
      }
    }
  }

  // ─── Filtros ───────────────────────────────────────────────────────

  void setFilterType(String type) {
    _filterType = type;
    _applyFilters();
    notifyListeners();
  }

  void setFilterPeriod(String period) {
    _filterPeriod = period;
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    final now = DateTime.now();
    final periodStart = _filterPeriod == 'semana'
        ? now.subtract(const Duration(days: 7))
        : now.subtract(const Duration(days: 30));

    var filtered = _historyFeedings
        .where((f) => f.fedAt.isAfter(periodStart))
        .toList();

    switch (_filterType) {
      case 'conformes':
        filtered = filtered.where((f) => f.divergencePercent.abs() <= 10.0).toList();
        break;
      case 'divergencias':
        filtered = filtered.where((f) => f.divergencePercent.abs() > 10.0).toList();
        break;
    }

    _filteredFeedings = filtered;
  }

  // ─── Dados para gráfico ────────────────────────────────────────────

  /// Retorna consumo diário dos últimos 14 dias (para gráfico de barras).
  /// Cada entry: {date, totalGrams, isConform}.
  List<DailyConsumption> get dailyConsumption14d {
    final now = DateTime.now();
    final days = <DailyConsumption>[];

    for (int i = 13; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final nextDate = date.add(const Duration(days: 1));

      final dayFeedings = _historyFeedings.where((f) =>
          f.fedAt.isAfter(date) && f.fedAt.isBefore(nextDate)).toList();

      final totalGrams =
          dayFeedings.fold<int>(0, (sum, f) => sum + f.amountGrams);
      final allConform =
          dayFeedings.isEmpty || dayFeedings.every((f) => f.divergencePercent.abs() <= 10.0);

      days.add(DailyConsumption(
        date: date,
        totalGrams: totalGrams,
        isConform: allConform,
        feedingCount: dayFeedings.length,
      ));
    }

    return days;
  }

  // ─── Cálculos base ─────────────────────────────────────────────────

  /// Calcula conformidade: % de refeições dentro da tolerância (±10%).
  void _calculateConformity() {
    if (_todayFeedings.isEmpty) {
      _conformityPercent = 0.0;
      return;
    }
    final conformCount =
        _todayFeedings.where((f) => f.divergencePercent.abs() <= 10.0).length;
    _conformityPercent = (conformCount / _todayFeedings.length) * 100;
  }

  /// Quantidade total consumida hoje (gramas).
  int get totalConsumedToday =>
      _todayFeedings.fold(0, (sum, f) => sum + f.amountGrams);

  /// Quantidade prescrita por dia.
  int get prescribedPerDay => _prescription?.amountGramsPerDay ?? 0;

  /// Refeições esperadas por dia.
  int get mealsExpected => _prescription?.mealsPerDay ?? 2;

  /// Refeições realizadas hoje.
  int get mealsCompleted => _todayFeedings.length;

  /// Progresso do dia (0.0 a 1.0+).
  double get dayProgress {
    if (prescribedPerDay == 0) return 0.0;
    return totalConsumedToday / prescribedPerDay;
  }

  /// Label do período para exibição.
  static String periodLabel(String period) {
    switch (period) {
      case 'manha':
        return 'Manhã';
      case 'almoco':
        return 'Almoço';
      case 'noite':
        return 'Noite';
      default:
        return period;
    }
  }

  @override
  void dispose() {
    _feedingsSub?.cancel();
    super.dispose();
  }
}

/// Modelo auxiliar para dados do gráfico diário.
class DailyConsumption {
  final DateTime date;
  final int totalGrams;
  final bool isConform;
  final int feedingCount;

  const DailyConsumption({
    required this.date,
    required this.totalGrams,
    required this.isConform,
    required this.feedingCount,
  });
}
