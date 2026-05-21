abstract final class ActivityFormLabels {
  static String descriptionLabel({
    required String category,
    required String? subtype,
  }) {
    if (category == 'Treino') return 'Descrição do treino';
    if (category == 'Saude') return 'Detalhes';
    return 'Descrição';
  }

  static String saveButtonLabel({required String category}) {
    if (category == 'Treino') return 'SALVAR TREINO';
    if (category == 'Saude') return 'SALVAR PRONTUÁRIO';
    return 'SALVAR REGISTRO';
  }

  static String successSaveMessage({required String category}) {
    if (category == 'Treino') return 'Treino salvo no Firebase.';
    if (category == 'Saude') return 'Prontuário salvo no Firebase.';
    return 'Registro salvo no Firebase.';
  }
}
