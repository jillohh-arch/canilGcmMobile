import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_item_card.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_status_views.dart';

/// Copy da Agenda Global. Preserva o vocabulário operacional do Centro de
/// Prontidão K9 — não é agenda pessoal nem calendário genérico.
abstract final class HealthScheduleGlobalCopy {
  const HealthScheduleGlobalCopy._();

  static const title = 'AGENDA PREVENTIVA';
  static const subtitle = 'Cuidados programados do efetivo K9';

  static String subtitleFor(int dogCount) => dogCount == 1
      ? 'Cuidados programados de 1 K9'
      : 'Cuidados programados de $dogCount K9s';

  /// Catálogo vazio ≠ agenda em dia.
  static const noCatalogTitle = 'Nenhum K9 disponível';
  static const noCatalogMessage =
      'Não há K9 acessível para montar a agenda do efetivo.';

  /// Catálogo existe, agenda sem itens abertos.
  static const emptyTitle = 'Agenda em dia';
  static const emptyMessage =
      'Nenhum cuidado programado em aberto para o efetivo.';

  static const permissionDeniedTitle = 'Sem permissão';
  static const permissionDeniedMessage =
      'Sua sessão não autoriza a agenda do efetivo.';

  static const errorTitle = 'Não foi possível carregar';
  static const offlineTitle = 'Sem conexão';

  static const retryLabel = 'Tentar novamente';

  /// Lista cortada pelo limite — nunca insinuar lista completa.
  static String truncatedNotice(int shown) =>
      'Mostrando os primeiros $shown itens.';

  static const filterEmptyTitle = 'Nenhum item no filtro';
  static const filterEmptyMessage =
      'Nenhum cuidado corresponde ao filtro selecionado.';
}

/// Agenda Preventiva **global** (multi-K9).
///
/// Estrutura: seção temporal aprovada (primeiro nível) → subheader por K9
/// (segundo nível) → [HealthScheduleItemCard] existente, preservado sem
/// alteração.
///
/// Estados temporais são derivados na leitura pela policy única; nada temporal
/// é consultado nem persistido.
class HealthScheduleGlobalView extends StatelessWidget {
  const HealthScheduleGlobalView({
    super.key,
    required this.controller,
    required this.resolveDog,
    this.now,
    this.bottomPadding = 0,
    this.onRetry,
  });

  final HealthScheduleGlobalController controller;

  /// Resolve nome/foto do K9 a partir do catálogo já materializado.
  ///
  /// Contrato: sem I/O por item — o caller monta o mapa uma vez (zero N+1).
  final HealthScheduleDogLabelResolver resolveDog;

  final DateTime Function()? now;
  final double bottomPadding;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _body(context, controller.state),
    );
  }

  Widget _body(BuildContext context, HealthScheduleGlobalState state) {
    switch (state) {
      case HealthScheduleGlobalInitial():
        return _message(
          key: const ValueKey('schedule-global-initial'),
          icon: Icons.event_available_rounded,
          title: HealthScheduleGlobalCopy.title,
          message: 'Carregando a agenda do efetivo…',
        );

      case HealthScheduleGlobalLoading():
        return const HealthScheduleLoadingView();

      // Catálogo vazio é distinto de agenda vazia.
      case HealthScheduleGlobalNoCatalog():
        return _message(
          key: const ValueKey('schedule-global-no-catalog'),
          icon: Icons.pets_rounded,
          title: HealthScheduleGlobalCopy.noCatalogTitle,
          message: HealthScheduleGlobalCopy.noCatalogMessage,
        );

      case HealthScheduleGlobalEmpty():
        return _message(
          key: const ValueKey('schedule-global-empty'),
          icon: Icons.event_note_rounded,
          title: HealthScheduleGlobalCopy.emptyTitle,
          message: HealthScheduleGlobalCopy.emptyMessage,
          onAction: onRetry,
          actionLabel: HealthScheduleGlobalCopy.retryLabel,
        );

      // Autorização: nunca apresentada como agenda vazia.
      case HealthScheduleGlobalPermissionDenied(:final message):
        return _message(
          key: const ValueKey('schedule-global-permission-denied'),
          icon: Icons.lock_outline_rounded,
          iconColor: AppTheme.error,
          title: HealthScheduleGlobalCopy.permissionDeniedTitle,
          message: message.isEmpty
              ? HealthScheduleGlobalCopy.permissionDeniedMessage
              : message,
        );

      // Erro técnico (índice/query) ou offline: distintos de vazio.
      case HealthScheduleGlobalError(:final message, :final isOffline):
        return _message(
          key: ValueKey(
            isOffline ? 'schedule-global-offline' : 'schedule-global-error',
          ),
          icon: isOffline
              ? Icons.cloud_off_rounded
              : Icons.error_outline_rounded,
          iconColor: isOffline ? AppTheme.warning : AppTheme.error,
          title: isOffline
              ? HealthScheduleGlobalCopy.offlineTitle
              : HealthScheduleGlobalCopy.errorTitle,
          message: message,
          onAction: onRetry,
          actionLabel: HealthScheduleGlobalCopy.retryLabel,
        );

      case HealthScheduleGlobalData(:final snapshot):
        return _dataBody(context, snapshot);
    }
  }

  Widget _message({
    required Key key,
    required IconData icon,
    required String title,
    required String message,
    Color iconColor = AppTheme.primary,
    Future<void> Function()? onAction,
    String? actionLabel,
  }) {
    return HealthScheduleSurfaceMessage(
      key: key,
      icon: icon,
      iconColor: iconColor,
      title: title,
      message: message,
      actionLabel: onAction == null ? null : actionLabel,
      onAction: onAction == null ? null : () => onAction(),
    );
  }

  Widget _dataBody(
    BuildContext context,
    HealthScheduleGlobalSnapshot snapshot,
  ) {
    final children = <Widget>[
      if (snapshot.isRefreshing)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      // Falha de refresh preserva a lista e avisa — não apaga dados.
      if (snapshot.hasRefreshFailure)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _RefreshFailureBanner(
            message: snapshot.lastRefreshError ?? '',
            isOffline: snapshot.lastRefreshWasOffline,
          ),
        ),
      // Resultado cortado: explícito, sem botão de carga ilimitada.
      if (snapshot.truncated)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TruncatedBanner(shown: snapshot.items.length),
        ),
      ..._buildSections(snapshot.groups),
    ];

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: children,
    );

    final body = onRetry == null
        ? list
        : RefreshIndicator(
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfacePanel,
            onRefresh: onRetry!,
            child: list,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlobalHeader(dogCount: snapshot.catalogSize),
        const SizedBox(height: 14),
        Expanded(child: body),
      ],
    );
  }

  /// Seções temporais aprovadas (mesma ordem e cores da Agenda per-dog),
  /// com segundo nível por K9.
  List<Widget> _buildSections(HealthScheduleGroups groups) {
    final blocks =
        <({String title, Color color, List<HealthScheduleItemView> items})>[
          (
            title: HealthScheduleUserCopy.sectionAttention,
            color: AppTheme.error,
            items: groups.overdue,
          ),
          (
            title: HealthScheduleUserCopy.sectionPending,
            color: AppTheme.warning,
            items: groups.pending,
          ),
          (
            title: HealthScheduleUserCopy.sectionToday,
            color: AppTheme.primary,
            items: groups.today,
          ),
          (
            title: HealthScheduleUserCopy.sectionUpcoming,
            color: AppTheme.success,
            items: groups.upcoming,
          ),
          (
            title: HealthScheduleUserCopy.sectionScheduled,
            color: AppTheme.primary,
            items: groups.scheduled,
          ),
        ];

    final widgets = <Widget>[];
    for (final block in blocks) {
      if (block.items.isEmpty) continue;

      // Chave qualificada pela seção: o MESMO cão aparece em várias seções
      // temporais (atrasado + hoje, por exemplo). Sem o prefixo da seção, as
      // chaves de subheader colidem na mesma ListView e a reconciliação
      // estoura `child == null || indexOf(child) > index` no sliver assim que
      // os índices deslocam (ex.: ao inserir o banner de truncated).
      final sectionSlug = block.title.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '-',
      );

      widgets.add(
        _GlobalSectionHeader(
          key: ValueKey('schedule-global-section-$sectionSlug'),
          title: block.title,
          color: block.color,
          count: block.items.length,
        ),
      );

      final dogBlocks = groupSectionByDog(block.items, resolveDog: resolveDog);

      for (final dogBlock in dogBlocks) {
        widgets.add(
          _DogSubheader(
            key: ValueKey('schedule-global-dog-$sectionSlug-${dogBlock.dogId}'),
            dogName: dogBlock.dogName,
            photoUrl: dogBlock.photoUrl,
            count: dogBlock.items.length,
          ),
        );
        for (var i = 0; i < dogBlock.items.length; i++) {
          if (i > 0) {
            widgets.add(
              SizedBox(
                key: ValueKey(
                  'gap-$sectionSlug-${dogBlock.dogId}-'
                  '${dogBlock.items[i].id}',
                ),
                height: 8,
              ),
            );
          }
          final item = dogBlock.items[i];
          // Card compartilhado, preservado sem alteração.
          widgets.add(
            HealthScheduleItemCard(
              key: ValueKey('schedule-card-${item.dogId}-${item.id}'),
              item: item,
              now: now,
            ),
          );
        }
        widgets.add(
          SizedBox(
            key: ValueKey('gap-dog-$sectionSlug-${dogBlock.dogId}'),
            height: 14,
          ),
        );
      }
      widgets.add(
        SizedBox(key: ValueKey('gap-section-$sectionSlug'), height: 4),
      );
    }
    return widgets;
  }
}

class _GlobalHeader extends StatelessWidget {
  const _GlobalHeader({required this.dogCount});

  final int dogCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          HealthScheduleGlobalCopy.title,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          HealthScheduleGlobalCopy.subtitleFor(dogCount),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _GlobalSectionHeader extends StatelessWidget {
  const _GlobalSectionHeader({
    super.key,
    required this.title,
    required this.color,
    required this.count,
  });

  final String title;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Text(
            '$count',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subheader compacto de K9 — segundo nível de agrupamento.
///
/// Deliberadamente leve: identidade suficiente para saber de qual K9 é o
/// compromisso, sem repetir card de cão em cada linha (leitura rápida em campo).
class _DogSubheader extends StatelessWidget {
  const _DogSubheader({
    super.key,
    required this.dogName,
    required this.count,
    this.photoUrl,
  });

  final String dogName;
  final String? photoUrl;
  final int count;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          _DogAvatar(dogName: dogName, photoUrl: photo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dogName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            count == 1 ? '1 item' : '$count itens',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar do K9 com fallback local (inicial) quando não há foto.
class _DogAvatar extends StatelessWidget {
  const _DogAvatar({required this.dogName, this.photoUrl});

  final String dogName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl;
    final initial = dogName.trim().isEmpty
        ? '?'
        : dogName.trim().substring(0, 1).toUpperCase();

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.primary.withValues(alpha: 0.16),
        image: (photo == null || photo.isEmpty)
            ? null
            : DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: (photo == null || photo.isEmpty)
          ? Text(
              initial,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _TruncatedBanner extends StatelessWidget {
  const _TruncatedBanner({required this.shown});

  final int shown;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('schedule-global-truncated'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              HealthScheduleGlobalCopy.truncatedNotice(shown),
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshFailureBanner extends StatelessWidget {
  const _RefreshFailureBanner({required this.message, required this.isOffline});

  final String message;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final color = isOffline ? AppTheme.warning : AppTheme.error;
    return Container(
      key: const ValueKey('schedule-global-refresh-failure'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isOffline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
