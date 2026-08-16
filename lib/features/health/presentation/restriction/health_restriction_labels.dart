import '../../domain/health_v1_enums_ext.dart';

/// Rótulos operacionais dos níveis de restrição.
///
/// Nunca expõem o vocabulário interno de prontidão (`temporarily_unfit`,
/// `fit_with_restrictions`, `operational_attention`): aquilo é veredito do
/// projetor, não linguagem de quem registra.
String healthRestrictionLevelLabel(RestrictionLevel level) {
  return switch (level) {
    RestrictionLevel.absolute => 'Restrição absoluta',
    RestrictionLevel.partial => 'Restrição parcial',
    RestrictionLevel.attention => 'Atenção operacional',
  };
}

/// Consequência operacional de cada nível, em linguagem de campo.
String healthRestrictionLevelSupport(RestrictionLevel level) {
  return switch (level) {
    RestrictionLevel.absolute =>
      'Impede o uso operacional enquanto estiver ativa.',
    RestrictionLevel.partial =>
      'Permite uso com atividades especificamente limitadas.',
    RestrictionLevel.attention =>
      'Mantém o K9 operacional, mas registra uma condição que exige atenção.',
  };
}

/// Ordem de apresentação: do mais restritivo ao menos restritivo.
const List<RestrictionLevel> kHealthRestrictionLevelOrder = <RestrictionLevel>[
  RestrictionLevel.absolute,
  RestrictionLevel.partial,
  RestrictionLevel.attention,
];

/// Rótulos humanos das categorias. Os `wireName` permanecem intocados.
String healthRestrictionCategoryLabel(RestrictionCategory category) {
  return switch (category) {
    RestrictionCategory.injury => 'Lesão / trauma',
    RestrictionCategory.postSurgical => 'Pós-operatório',
    RestrictionCategory.medicationEffect => 'Efeito de medicação',
    RestrictionCategory.behavioral => 'Comportamental',
    RestrictionCategory.infectious => 'Condição infecciosa',
    RestrictionCategory.chronic => 'Condição crônica',
    RestrictionCategory.preventivePending => 'Preventivo pendente',
    RestrictionCategory.other => 'Outro',
  };
}

/// Ordem de apresentação das categorias, agrupando o que é clinicamente afim.
const List<RestrictionCategory> kHealthRestrictionCategoryOrder =
    <RestrictionCategory>[
      RestrictionCategory.injury,
      RestrictionCategory.postSurgical,
      RestrictionCategory.medicationEffect,
      RestrictionCategory.infectious,
      RestrictionCategory.chronic,
      RestrictionCategory.behavioral,
      RestrictionCategory.preventivePending,
      RestrictionCategory.other,
    ];
