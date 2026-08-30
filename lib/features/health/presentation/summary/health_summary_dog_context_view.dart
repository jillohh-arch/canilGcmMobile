/// Contexto de apresentação do K9 para o card de identidade do Resumo.
///
/// Separado de [HealthSummaryViewData] de propósito: dados cadastrais
/// (nome, foto, raça, sexo, idade) **não** pertencem ao contrato de saúde 2B.
///
/// A 2C **não** busca o cão em Firestore; o caller fornece este VO.
final class HealthSummaryDogContextView {
  HealthSummaryDogContextView({
    required String dogId,
    required String name,
    this.breed,
    this.sexLabel,
    this.ageLabel,
    this.photoUrl,
  }) : dogId = dogId.trim(),
       name = name.trim() {
    if (this.dogId.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'dogId não pode ser vazio');
    }
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'name não pode ser vazio');
    }
  }

  final String dogId;
  final String name;
  final String? breed;
  final String? sexLabel;
  final String? ageLabel;

  /// URL de foto opcional. Ausente → avatar com fallback local.
  final String? photoUrl;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryDogContextView &&
      other.dogId == dogId &&
      other.name == name &&
      other.breed == breed &&
      other.sexLabel == sexLabel &&
      other.ageLabel == ageLabel &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode =>
      Object.hash(dogId, name, breed, sexLabel, ageLabel, photoUrl);
}
