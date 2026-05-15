import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:canil_gcm/features/nutrition/data/nutrition_service.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

/// ViewModel de nutrição — gerencia prescrição vigente, refeições do dia
/// e cálculo de conformidade alimentar.
class NutritionViewModel extends ChangeNotifier {
  final NutritionService _service = NutritionService();

  // ─── Estado ────────────────────────────────────────────────────────
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

  // ─── Lifecycle ─────────────────────────────────────────────────────

  /// Inicializa o ViewModel para um cão específico.
  Future<void> loadForDog(String dogId) async {
    if (_activeDogId == dogId && _prescription != null) return;
    _activeDogId = dogId;
    _loading = true;
    notifyListeners();

    // Carrega prescrição vigente
    _prescription = await _service.getActivePrescription(dogId);

    // Inicia stream de refeições do dia
    _feedingsSub?.cancel();
    _feedingsSub = _service.watchTodayFeedings(dogId).listen((feedings) {
      _todayFeedings = feedings;
      _calculateConformity();
      notifyListeners();
    });

    _loading = false;
    notifyListeners();
  }

  /// Registra uma nova refeição.
  Future<void> addFeeding(String dogId, Feeding feeding) async {
    await _service.addFeeding(dogId, feeding);
    // O stream atualiza automaticamente
  }

  /// Calcula conformidade: % de refeições dentro da tolerância (±5%).
  void _calculateConformity() {
    if (_todayFeedings.isEmpty) {
      _conformityPercent = 0.0;
      return;
    }
    final conformCount =
        _todayFeedings.where((f) => f.divergencePercent.abs() <= 5.0).length;
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
