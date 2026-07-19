import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';

/// Escopo de sessão para pending intents de Nutrição (5D Gate 3).
///
/// Owner real em produção: [MainRootScreen] State (sobrevive a:
/// troca de aba IndexedStack, remount de [HealthV1EntryScreen] por
/// ValueKey de dog, e desmonte temporário da aba Saúde sem cão ativo).
///
/// - **Keyed por dogId**: intenção de dog A nunca é reutilizada em dog B.
/// - **Uma pending por dog** (single slot): intenção incompatível no mesmo
///   dog exige [HealthNutritionMutationController.discardIntent] explícito
///   (não overwrite silencioso no controller).
///
/// Não é outbox offline nem fila persistente.
final class HealthNutritionPendingIntentSession {
  HealthNutritionPendingIntentSession();

  final Map<String, HealthNutritionPendingIntentHolder> _byDog =
      <String, HealthNutritionPendingIntentHolder>{};

  /// Holder estável para [dogId] durante a vida da sessão.
  HealthNutritionPendingIntentHolder holderFor(String dogId) {
    final id = dogId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'dogId vazio');
    }
    return _byDog.putIfAbsent(id, HealthNutritionPendingIntentHolder.new);
  }

  /// Remove holder do dog (raro; preferir discard semântico da intent).
  void clearDog(String dogId) {
    _byDog.remove(dogId.trim());
  }

  /// Testes / diagnóstico.
  int get dogCountForTest => _byDog.length;

  bool hasPendingForDog(String dogId) =>
      _byDog[dogId.trim()]?.hasPending ?? false;
}
