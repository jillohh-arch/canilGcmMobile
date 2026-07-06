/// Configuração de exibição da composição de guarnição.
///
/// Centraliza num único ponto a definição de:
/// - quais postos são exibidos (e em qual ordem/posição)
/// - quais são obrigatórios para o status OPERACIONAL
/// - posição do cão na grade (layout)
/// - quais postos são condicionais (ex: Auxiliar 2 só aparece se ocupado)
///
/// Hoje reflete a composição de Limeira (4 humanos + cão, cão embarcado).
/// No futuro, vira dado da corporação lido no boot — este arquivo é o ponto
/// de troca: nenhum widget tem listas de roles hardcoded.
abstract final class CrewComposition {
  /// Postos exibidos na grade/planta do card (ordem visual).
  /// Posição 0 = topo-esquerda, 1 = topo-direita, 2 = baixo-esquerda,
  /// 3 = baixo-direita (K9).
  static const List<CrewPost> gridPosts = [
    CrewPost.motorista,
    CrewPost.encarregado,
    CrewPost.auxiliar1,
    CrewPost.k9,
  ];

  /// Postos que podem aparecer como linha compacta abaixo da grade.
  /// Appears only when occupied; hidden when vacant.
  static const List<CrewPost> compactPosts = [
    CrewPost.auxiliar2,
  ];

  /// Postos obrigatórios para o status OPERACIONAL.
  /// Se algum faltar, o status da guarnição é INCOMPLETA.
  static const Set<CrewPost> requiredForOperational = {
    CrewPost.motorista,
    CrewPost.encarregado,
  };

  /// Postos condicionais: só exibidos quando ocupados.
  static const Set<CrewPost> conditionalPosts = {
    CrewPost.auxiliar2,
  };

  /// Retorna todos os postos da guarnição em ordem canônica (sheet vertical).
  static List<CrewPost> get allPostsOrdered => [
        CrewPost.motorista,
        CrewPost.encarregado,
        CrewPost.auxiliar1,
        CrewPost.auxiliar2,
      ];
}

/// Enum canônico dos postos de guarnição.
///
/// O domain (VehicleCrewMember.role) usa strings ('motorista', 'encarregado',
/// 'auxiliar_1', 'auxiliar_2', 'k9'). Este enum é o mapeamento de exibição.
enum CrewPost {
  motorista('motorista', 'Motorista', 'MOT'),
  encarregado('encarregado', 'Encarregado', 'ENC'),
  auxiliar1('auxiliar_1', 'Auxiliar 1', 'AUX1'),
  auxiliar2('auxiliar_2', 'Auxiliar 2', 'AUX2'),
  k9('k9', 'K9', 'K9');

  const CrewPost(this.role, this.displayName, this.shortLabel);

  /// Valor que corresponde a VehicleCrewMember.role no Firestore.
  final String role;

  /// Nome completo para exibição (sheet, badge).
  final String displayName;

  /// Label curto para o mini-quadro do card.
  final String shortLabel;

  /// Mapeia string role → CrewPost.
  static CrewPost? fromRole(String role) {
    for (final post in CrewPost.values) {
      if (post.role == role) return post;
    }
    return null;
  }
}
