/// Tipo de destino real (honestidade semântica 3D).
///
/// - [relatedHistory]: abre histórico/contexto do cão, **sem** foco unitário
///   garantido no registro clicado;
/// - não há [exactDetail] na v1 para as fontes legadas mapeadas.
enum HealthTimelineDestinationKind {
  /// Tela de histórico/lista relacionada ao cão (não detalhe unitário).
  relatedHistory,
}

/// Destinos tipados de navegação da timeline (allowlist 3D-C).
///
/// Não são rotas raw nem collection paths públicos.
/// Apenas targets com tela real existente no app.
///
/// **Importante:** os targets atuais são históricos relacionados, não
/// “detalhe exato” do documento clicado.
sealed class HealthTimelineDetailTarget {
  const HealthTimelineDetailTarget({
    required this.dogId,
    required this.sourceId,
  });

  final String dogId;

  /// Id do registro de origem (pode ser usado para highlight futuro; a tela
  /// atual pode ignorá-lo).
  final String sourceId;

  HealthTimelineDestinationKind get kind;

  /// Label de ação para semantics (honesta: histórico, não “detalhe”).
  String get navigationActionLabel;
}

/// Histórico de pesagens do cão ([WeightHistoryScreen]).
final class WeightHistoryTarget extends HealthTimelineDetailTarget {
  const WeightHistoryTarget({required super.dogId, required super.sourceId});

  @override
  HealthTimelineDestinationKind get kind =>
      HealthTimelineDestinationKind.relatedHistory;

  @override
  String get navigationActionLabel => 'Abrir histórico de peso';
}

/// Fluxo de nutrição / alimentação (tela de nutrição existente).
final class NutritionHistoryTarget extends HealthTimelineDetailTarget {
  const NutritionHistoryTarget({
    required super.dogId,
    required super.sourceId,
    required this.sourceCollection,
  });

  /// `feeding_events` ou `feedings` (identidade interna, não rota pública).
  final String sourceCollection;

  @override
  HealthTimelineDestinationKind get kind =>
      HealthTimelineDestinationKind.relatedHistory;

  @override
  String get navigationActionLabel => 'Abrir histórico de alimentação';
}

/// Histórico de vacinação do cão ([VaccinationHistoryScreen]).
final class VaccinationHistoryTarget extends HealthTimelineDetailTarget {
  const VaccinationHistoryTarget({
    required super.dogId,
    required super.sourceId,
  });

  @override
  HealthTimelineDestinationKind get kind =>
      HealthTimelineDestinationKind.relatedHistory;

  @override
  String get navigationActionLabel => 'Abrir histórico de vacinação';
}

// Aliases legados da implementação inicial 3D (mesma classe).
typedef WeightHistoryDetailTarget = WeightHistoryTarget;
typedef NutritionHistoryDetailTarget = NutritionHistoryTarget;
typedef VaccinationHistoryDetailTarget = VaccinationHistoryTarget;
