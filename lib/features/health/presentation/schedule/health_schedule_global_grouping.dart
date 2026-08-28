import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';

/// Bloco de um K9 dentro de uma seção temporal da Agenda Global.
///
/// O primeiro nível de agrupamento continua sendo temporal (as seções
/// aprovadas: REQUER ATENÇÃO / PENDENTES / HOJE / PRÓXIMOS / PROGRAMADOS).
/// Este bloco é o segundo nível, usado somente no modo Global — no modo
/// per-dog a identidade do cão já está no header da tela.
final class HealthScheduleDogBlock {
  HealthScheduleDogBlock({
    required this.dogId,
    required this.dogName,
    this.photoUrl,
    required List<HealthScheduleItemView> items,
  }) : items = List.unmodifiable(List<HealthScheduleItemView>.of(items));

  final String dogId;

  /// Nome de exibição resolvido pelo caller a partir do catálogo.
  ///
  /// Nunca é buscado no Firestore por item: o caller resolve o catálogo uma
  /// vez e enriquece localmente (sem N+1).
  final String dogName;

  /// Foto opcional; ausente → avatar com fallback local.
  final String? photoUrl;

  final List<HealthScheduleItemView> items;
}

/// Resolve identidade de exibição de um K9 a partir do catálogo.
///
/// Contrato: nunca lança e nunca faz I/O. Um item cujo `dog_id` não esteja no
/// catálogo (cão removido, fora de escopo) continua visível com rótulo neutro
/// — omitir um compromisso de saúde é pior que exibi-lo sem nome.
typedef HealthScheduleDogLabelResolver =
    HealthScheduleDogLabel Function(String dogId);

/// Identidade mínima de exibição do K9.
final class HealthScheduleDogLabel {
  const HealthScheduleDogLabel({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;
}

/// Agrupa itens de uma seção temporal por K9.
///
/// Ordem dos blocos: pela posição do item mais urgente de cada cão dentro da
/// seção (`scheduledFor ASC`, empate por `id ASC` — o mesmo comparador das
/// seções). Assim o K9 que exige ação primeiro aparece primeiro, e a ordem é
/// determinística para o mesmo conjunto.
///
/// Não reordena nem reclassifica itens: a precedência temporal já foi decidida
/// pela policy na leitura.
List<HealthScheduleDogBlock> groupSectionByDog(
  Iterable<HealthScheduleItemView> sectionItems, {
  required HealthScheduleDogLabelResolver resolveDog,
}) {
  final byDog = <String, List<HealthScheduleItemView>>{};
  for (final item in sectionItems) {
    byDog.putIfAbsent(item.dogId, () => <HealthScheduleItemView>[]).add(item);
  }

  final blocks = <HealthScheduleDogBlock>[];
  for (final entry in byDog.entries) {
    final items = sortScheduleItems(entry.value);
    final label = resolveDog(entry.key);
    blocks.add(
      HealthScheduleDogBlock(
        dogId: entry.key,
        dogName: label.name,
        photoUrl: label.photoUrl,
        items: items,
      ),
    );
  }

  blocks.sort((a, b) {
    final byUrgency = compareScheduleItemsByDue(a.items.first, b.items.first);
    if (byUrgency != 0) return byUrgency;
    // Empate absoluto: desempata por dogId para estabilidade entre execuções.
    return a.dogId.compareTo(b.dogId);
  });

  return List<HealthScheduleDogBlock>.unmodifiable(blocks);
}
