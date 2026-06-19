import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_team_screen.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_transition_service.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/shift_assumption_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_promotion_request_screen.dart';

class PendingScreen extends StatefulWidget {
  final String userId;

  const PendingScreen({super.key, required this.userId});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  final NotificationService _notificationService = NotificationService();
  final VehicleCrewTransitionService _crewTransitionService =
      VehicleCrewTransitionService();
  late Stream<List<NotificationItem>> _notificationsStream;
  final Set<String> _processingNotifications = <String>{};
  bool _markingAllAsRead = false;

  @override
  void initState() {
    super.initState();
    _notificationsStream = _notificationService.getVisibleNotifications(
      userId: widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NotificationItem>>(
      stream: _notificationsStream,
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? const <NotificationItem>[];
        final actionItems =
            notifications.where((item) => item.isOpenAction).toList()
              ..sort(_compareActionItems);
        final notices =
            notifications.where((item) => !item.isOpenAction).toList()
              ..sort(_compareByCreatedAtDesc);
        final hasUnread = notifications.any((item) => item.isUnread);

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: _buildAppBar(
            actionCount: actionItems.length,
            noticeCount: notices.length,
            hasUnread: hasUnread,
          ),
          body: _buildBody(
            snapshot: snapshot,
            actionItems: actionItems,
            notices: notices,
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar({
    required int actionCount,
    required int noticeCount,
    required bool hasUnread,
  }) {
    return AppBar(
      backgroundColor: AppTheme.background,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      leading: IconButton(
        tooltip: 'Voltar',
        icon: const Icon(Icons.chevron_left_rounded, size: 32),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Notificacoes',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$actionCount requerem acao · $noticeCount avisos',
            style: GoogleFonts.ibmPlexMono(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        if (_markingAllAsRead)
          const Padding(
            padding: EdgeInsets.only(right: 18),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton(
            onPressed: hasUnread ? _markAllAsRead : null,
            child: Text(
              'Marcar lidas',
              style: GoogleFonts.inter(
                color: hasUnread ? AppTheme.primary : AppTheme.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildBody({
    required AsyncSnapshot<List<NotificationItem>> snapshot,
    required List<NotificationItem> actionItems,
    required List<NotificationItem> notices,
  }) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return _EmptyNotificationsState(
        icon: Icons.error_outline_rounded,
        title: 'Falha ao carregar',
        message: snapshot.error.toString(),
      );
    }

    if (actionItems.isEmpty && notices.isEmpty) {
      return const _EmptyNotificationsState(
        icon: Icons.notifications_none_rounded,
        title: 'Tudo em ordem',
        message: 'Nenhuma pendencia ou aviso ativo no momento.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfacePanel,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _NotificationSection(
            title: 'Requer acao',
            subtitle: 'Pendencias que precisam de decisao operacional.',
            count: actionItems.length,
            accent: AppTheme.warning,
            emptyMessage: 'Nenhuma pendencia aberta.',
            children: actionItems
                .map(
                  (notification) => _NotificationCard(
                    notification: notification,
                    processing: _isProcessing(notification),
                    onTap: () => _handleNotificationTap(notification),
                    onAccept:
                        notification.type ==
                            NotificationType.vehicleCrewInvitation
                        ? () => _respondToCrewInvitation(
                            notification,
                            accept: true,
                          )
                        : null,
                    onDecline:
                        notification.type ==
                            NotificationType.vehicleCrewInvitation
                        ? () => _declineCrewInvitation(notification)
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          _NotificationSection(
            title: 'Avisos',
            subtitle: 'Informativos ja resolvidos ou sem acao pendente.',
            count: notices.length,
            accent: AppTheme.primary,
            emptyMessage: 'Nenhum aviso ativo.',
            children: notices
                .map(
                  (notification) => _NotificationCard(
                    notification: notification,
                    processing: _isProcessing(notification),
                    onTap: () => _handleNotificationTap(notification),
                    onArchive: notification.canBeArchived
                        ? () => _archiveNotice(notification)
                        : null,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    setState(() => _markingAllAsRead = true);

    try {
      await _notificationService.markAllAsRead(userId: widget.userId);
    } catch (error) {
      _showSnack('Erro ao marcar como lidas: $error', isError: true);
    } finally {
      if (mounted) setState(() => _markingAllAsRead = false);
    }
  }

  Future<void> _respondToCrewInvitation(
    NotificationItem notification, {
    required bool accept,
    String? reason,
  }) async {
    final crewId = notification.vehicleCrewId;
    if (crewId == null) {
      _showSnack('Convite sem identificador da VTR/equipe.', isError: true);
      return;
    }

    _setProcessing(notification, true);
    try {
      await _crewTransitionService.respondToInvitation(
        crewId: crewId,
        accept: accept,
        reason: reason,
      );
      _showSnack(accept ? 'Convite aceito.' : 'Convite recusado.');
    } catch (error) {
      _showSnack('Falha ao responder convite: $error', isError: true);
    } finally {
      _setProcessing(notification, false);
    }
  }

  Future<void> _declineCrewInvitation(NotificationItem notification) async {
    final reason = await _askDeclineReason();
    if (reason == null || !mounted) return;
    await _respondToCrewInvitation(notification, accept: false, reason: reason);
  }

  Future<String?> _askDeclineReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Recusar convite',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          style: GoogleFonts.inter(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Motivo obrigatorio',
            hintText: 'Informe por que nao entrara na guarnicao',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.of(dialogContext).pop(text);
              }
            },
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _archiveNotice(NotificationItem notification) async {
    if (!notification.canBeArchived) {
      _showSnack('Pendencia aberta nao pode ser limpa.', isError: true);
      return;
    }

    _setProcessing(notification, true);
    try {
      await _notificationService.archiveNotice(
        userId: widget.userId,
        notification: notification,
      );
      _showSnack('Aviso limpo.');
    } catch (error) {
      _showSnack('Falha ao limpar aviso: $error', isError: true);
    } finally {
      _setProcessing(notification, false);
    }
  }

  Future<void> _handleNotificationTap(NotificationItem notification) async {
    if (notification.isUnread) {
      try {
        await _notificationService.markAsRead(
          userId: widget.userId,
          notificationId: notification.id,
        );
      } catch (error) {
        _showSnack('Nao foi possivel marcar como lida: $error', isError: true);
      }
    }

    if (!mounted) return;
    await _openNotificationTarget(notification);
  }

  Future<void> _openNotificationTarget(NotificationItem notification) async {
    switch (notification.type) {
      case NotificationType.trainingPromotionRequested:
        if (notification.isOpenAction) {
          final requestId = notification.resolvedPromotionRequestId;
          if (requestId == null) {
            _showSnack('Solicitacao sem identificador tecnico.', isError: true);
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  TrainingPromotionRequestScreen(requestId: requestId),
            ),
          );
          return;
        }
        await _openDogTrainingHistory(notification);
        return;

      case NotificationType.trainingPromotionApproved:
      case NotificationType.trainingPromotionRejected:
      case NotificationType.trainingBonusMilestoneAvailable:
        await _openDogTrainingHistory(notification);
        return;

      case NotificationType.shiftStartReminder:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ShiftAssumptionScreen()),
        );
        return;

      case NotificationType.shiftEndReminder:
      case NotificationType.shiftOverdueReminder:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActiveShiftDashboardScreen()),
        );
        return;

      case NotificationType.vehicleCrewInvitation:
      case NotificationType.vehicleCrewInvitationAccepted:
      case NotificationType.vehicleCrewInvitationDeclined:
        await _openVehicleCrew(notification);
        return;

      case NotificationType.signatureRequested:
      case NotificationType.signatureCompleted:
      case NotificationType.signatureDeclined:
      case NotificationType.deadlineWarning:
      case NotificationType.occurrenceFinalized:
      case NotificationType.amendmentCreated:
        await _openOccurrenceReview(notification);
        return;

      case NotificationType.correctionRequested:
        await _openActiveOccurrence(notification);
        return;

      case NotificationType.occurrenceParticipationRequested:
        await _openOccurrenceReview(notification);
        return;

      case NotificationType.occurrenceParticipationAccepted:
      case NotificationType.occurrenceParticipationDeclined:
        await _openOccurrenceTeam(notification);
        return;
    }
  }

  Future<void> _openVehicleCrew(NotificationItem notification) async {
    final crewId = notification.vehicleCrewId;
    if (crewId == null) {
      _showSnack('Convite sem identificador da VTR/equipe.', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleCrewProfileScreen(crewId: crewId),
      ),
    );
  }

  Future<void> _openDogTrainingHistory(NotificationItem notification) async {
    final dogId = notification.dogId?.trim();
    if (dogId == null || dogId.isEmpty) {
      _showSnack('Aviso de treino sem identificador do K9.', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainingLogScreen(
          dogId: dogId,
          dogName: notification.dogName ?? '',
        ),
      ),
    );
  }

  Future<void> _openOccurrenceReview(NotificationItem notification) async {
    final occurrenceId = notification.occurrenceId.trim();
    if (occurrenceId.isEmpty) {
      _showSnack('Notificacao sem numero de ocorrencia.', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceReviewScreen(occurrenceId: occurrenceId),
      ),
    );
  }

  Future<void> _openActiveOccurrence(NotificationItem notification) async {
    final occurrenceId = notification.occurrenceId.trim();
    if (occurrenceId.isEmpty) {
      _showSnack('Notificacao sem numero de ocorrencia.', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveOccurrenceScreen(occurrenceId: occurrenceId),
      ),
    );
  }

  Future<void> _openOccurrenceTeam(NotificationItem notification) async {
    final occurrenceId = notification.occurrenceId.trim();
    if (occurrenceId.isEmpty) {
      _showSnack('Notificacao sem numero de ocorrencia.', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceTeamScreen(occurrenceId: occurrenceId),
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppFeedback.show(
        context,
        AppFeedbackText.fromError(
          message,
          fallback: 'Não foi possível concluir a ação.',
        ),
        type: AppFeedbackType.error,
      );
      return;
    }
    AppFeedback.success(context, message);
  }

  bool _isProcessing(NotificationItem notification) {
    return _processingNotifications.contains(notification.id);
  }

  void _setProcessing(NotificationItem notification, bool processing) {
    if (!mounted) return;
    setState(() {
      if (processing) {
        _processingNotifications.add(notification.id);
      } else {
        _processingNotifications.remove(notification.id);
      }
    });
  }

  int _compareActionItems(NotificationItem a, NotificationItem b) {
    final urgency = _actionUrgency(a).compareTo(_actionUrgency(b));
    if (urgency != 0) return urgency;
    return _compareByCreatedAtDesc(a, b);
  }

  int _compareByCreatedAtDesc(NotificationItem a, NotificationItem b) {
    return b.createdAt.compareTo(a.createdAt);
  }

  int _actionUrgency(NotificationItem item) {
    return switch (item.type) {
      NotificationType.signatureRequested => 0,
      NotificationType.vehicleCrewInvitation => 1,
      NotificationType.shiftEndReminder ||
      NotificationType.shiftOverdueReminder => 2,
      NotificationType.shiftStartReminder => 3,
      NotificationType.trainingPromotionRequested => 4,
      _ => 5,
    };
  }
}

class _NotificationSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final Color accent;
  final String emptyMessage;
  final List<Widget> children;

  const _NotificationSection({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.accent,
    required this.emptyMessage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              '$count',
              style: GoogleFonts.ibmPlexMono(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          _SectionEmptyMessage(message: emptyMessage)
        else
          ...children,
      ],
    );
  }
}

class _SectionEmptyMessage extends StatelessWidget {
  final String message;

  const _SectionEmptyMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel.withAlpha(130),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.textTertiary.withAlpha(25)),
      ),
      child: Text(
        message,
        style: GoogleFonts.inter(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onArchive;
  final bool processing;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    this.onAccept,
    this.onDecline,
    this.onArchive,
    this.processing = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor();
    final unread = notification.isUnread;
    final contextLines = _contextLines();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: unread
                  ? accent.withAlpha(15)
                  : AppTheme.surfacePanel.withAlpha(210),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: unread
                    ? accent.withAlpha(100)
                    : AppTheme.surfaceWhiteBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(unread ? 65 : 35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withAlpha(22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accent.withAlpha(90)),
                      ),
                      child: Icon(_icon(), color: accent, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _title(),
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (unread) _UnreadDot(color: accent),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _message(),
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (contextLines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: contextLines
                        .map((line) => _TechnicalChip(label: line))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: AppTheme.textTertiary,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      DateFormat('dd/MM HH:mm').format(notification.createdAt),
                      style: GoogleFonts.ibmPlexMono(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _ActionPill(label: _actionLabel(), accent: accent),
                  ],
                ),
                if (_hasInlineActions) ...[
                  const SizedBox(height: 12),
                  _buildInlineActions(accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasInlineActions {
    return processing ||
        onAccept != null ||
        onDecline != null ||
        onArchive != null;
  }

  Widget _buildInlineActions(Color accent) {
    if (processing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
          ),
          const SizedBox(width: 10),
          Text(
            'Processando...',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (onAccept != null || onDecline != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDecline,
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('Recusar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: BorderSide(color: AppTheme.error.withAlpha(120)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('Aceitar'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: AppTheme.background,
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onArchive,
        icon: const Icon(Icons.cleaning_services_rounded, size: 16),
        label: const Text('Limpar aviso'),
        style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
      ),
    );
  }

  IconData _icon() {
    return switch (notification.type) {
      NotificationType.vehicleCrewInvitation => Icons.group_add_rounded,
      NotificationType.vehicleCrewInvitationAccepted =>
        Icons.how_to_reg_rounded,
      NotificationType.vehicleCrewInvitationDeclined =>
        Icons.person_off_rounded,
      NotificationType.occurrenceParticipationRequested =>
        Icons.groups_2_rounded,
      NotificationType.occurrenceParticipationAccepted =>
        Icons.how_to_reg_rounded,
      NotificationType.occurrenceParticipationDeclined =>
        Icons.person_off_rounded,
      NotificationType.signatureRequested => Icons.draw_rounded,
      NotificationType.signatureCompleted => Icons.verified_rounded,
      NotificationType.signatureDeclined => Icons.cancel_presentation_rounded,
      NotificationType.correctionRequested => Icons.rule_rounded,
      NotificationType.deadlineWarning => Icons.warning_amber_rounded,
      NotificationType.occurrenceFinalized => Icons.verified_user_rounded,
      NotificationType.amendmentCreated => Icons.edit_note_rounded,
      NotificationType.trainingPromotionRequested => Icons.school_rounded,
      NotificationType.trainingPromotionApproved =>
        Icons.workspace_premium_rounded,
      NotificationType.trainingPromotionRejected =>
        Icons.assignment_late_rounded,
      NotificationType.trainingBonusMilestoneAvailable =>
        Icons.add_task_rounded,
      NotificationType.shiftStartReminder => Icons.login_rounded,
      NotificationType.shiftEndReminder => Icons.logout_rounded,
      NotificationType.shiftOverdueReminder => Icons.timer_off_rounded,
    };
  }

  Color _accentColor() {
    if (notification.isOpenAction) {
      return switch (notification.type) {
        NotificationType.signatureRequested => AppTheme.error,
        NotificationType.vehicleCrewInvitation => AppTheme.warning,
        NotificationType.trainingPromotionRequested => AppTheme.primary,
        NotificationType.shiftStartReminder ||
        NotificationType.shiftEndReminder ||
        NotificationType.shiftOverdueReminder => AppTheme.warning,
        _ => AppTheme.warning,
      };
    }
    return switch (notification.type) {
      NotificationType.trainingPromotionApproved ||
      NotificationType.signatureCompleted ||
      NotificationType.occurrenceFinalized ||
      NotificationType.vehicleCrewInvitationAccepted ||
      NotificationType.occurrenceParticipationAccepted => AppTheme.success,
      NotificationType.trainingPromotionRejected ||
      NotificationType.signatureDeclined ||
      NotificationType.vehicleCrewInvitationDeclined ||
      NotificationType.occurrenceParticipationDeclined => AppTheme.error,
      NotificationType.trainingBonusMilestoneAvailable => AppTheme.warning,
      NotificationType.shiftOverdueReminder => AppTheme.warning,
      _ => AppTheme.primary,
    };
  }

  String _title() {
    return switch (notification.type) {
      NotificationType.vehicleCrewInvitation => 'Convite de guarnicao',
      NotificationType.vehicleCrewInvitationAccepted => 'Convite aceito',
      NotificationType.vehicleCrewInvitationDeclined => 'Convite recusado',
      NotificationType.occurrenceParticipationRequested => 'Ciencia solicitada',
      NotificationType.occurrenceParticipationAccepted => 'Participacao aceita',
      NotificationType.occurrenceParticipationDeclined =>
        'Participacao recusada',
      NotificationType.signatureRequested => 'Assinatura necessaria',
      NotificationType.signatureCompleted => 'Assinatura realizada',
      NotificationType.signatureDeclined => 'Assinatura recusada',
      NotificationType.correctionRequested => 'Correcao solicitada',
      NotificationType.deadlineWarning => 'Prazo de assinatura',
      NotificationType.occurrenceFinalized => 'Ocorrencia selada',
      NotificationType.amendmentCreated => 'Aditamento criado',
      NotificationType.trainingPromotionRequested =>
        notification.isOpenAction
            ? 'Evolucao para avaliar'
            : 'Evolucao ja avaliada',
      NotificationType.trainingPromotionApproved => 'Evolucao aprovada',
      NotificationType.trainingPromotionRejected => 'Evolucao reprovada',
      NotificationType.trainingBonusMilestoneAvailable =>
        'Marco-bonus disponivel',
      NotificationType.shiftStartReminder => 'Assumir turno',
      NotificationType.shiftEndReminder => 'Encerrar turno',
      NotificationType.shiftOverdueReminder => 'Turno em atraso',
    };
  }

  String _message() {
    return switch (notification.type) {
      NotificationType.trainingPromotionRequested =>
        notification.isOpenAction
            ? 'Um condutor solicitou validacao de evolucao.'
            : 'A solicitacao de evolucao ja foi resolvida.',
      NotificationType.trainingPromotionApproved =>
        'A evolucao de treino foi aprovada.',
      NotificationType.trainingPromotionRejected => _withReason(
        'A evolucao de treino foi reprovada.',
      ),
      NotificationType.trainingBonusMilestoneAvailable =>
        'Novo marco-bonus disponivel para treino.',
      NotificationType.shiftStartReminder =>
        'Seu plantao esta perto de iniciar. Abra o app para assumir o turno.',
      NotificationType.shiftEndReminder =>
        'O horario previsto terminou. Encerre o turno quando o trabalho operacional permitir.',
      NotificationType.shiftOverdueReminder =>
        'O turno segue aberto alem do horario previsto.',
      NotificationType.vehicleCrewInvitation =>
        'Voce recebeu um convite para compor a guarnicao.',
      NotificationType.vehicleCrewInvitationAccepted =>
        'Um condutor aceitou o convite para a guarnicao.',
      NotificationType.vehicleCrewInvitationDeclined =>
        'Um condutor recusou o convite para a guarnicao.',
      NotificationType.occurrenceParticipationRequested =>
        'Voce foi incluido na ocorrencia e precisa revisar a ciencia.',
      NotificationType.occurrenceParticipationAccepted =>
        'Um integrante confirmou ciencia da ocorrencia.',
      NotificationType.occurrenceParticipationDeclined =>
        'Um integrante recusou participacao na ocorrencia.',
      NotificationType.signatureRequested =>
        'Revise a ocorrencia antes de assinar.',
      NotificationType.signatureCompleted =>
        'Um integrante assinou a ocorrencia.',
      NotificationType.signatureDeclined =>
        'Um integrante recusou assinar a ocorrencia.',
      NotificationType.correctionRequested =>
        'Foi solicitada correcao na ocorrencia.',
      NotificationType.deadlineWarning =>
        'O prazo para assinatura esta proximo do limite.',
      NotificationType.occurrenceFinalized =>
        'A ocorrencia foi finalizada com integridade registrada.',
      NotificationType.amendmentCreated =>
        'Um aditamento foi criado na ocorrencia.',
    };
  }

  String _withReason(String base) {
    final reason = notification.decisionReason?.trim();
    if (reason == null || reason.isEmpty) return base;
    return '$base Motivo: $reason';
  }

  String _actionLabel() {
    if (notification.type == NotificationType.trainingPromotionRequested) {
      return notification.isOpenAction ? 'Avaliar' : 'Ver historico';
    }
    return switch (notification.type) {
      NotificationType.vehicleCrewInvitation =>
        notification.isOpenAction ? 'Responder' : 'Abrir equipe',
      NotificationType.vehicleCrewInvitationAccepted ||
      NotificationType.vehicleCrewInvitationDeclined => 'Abrir equipe',
      NotificationType.signatureRequested =>
        notification.isOpenAction ? 'Revisar e assinar' : 'Ver ocorrencia',
      NotificationType.trainingPromotionApproved ||
      NotificationType.trainingPromotionRejected ||
      NotificationType.trainingBonusMilestoneAvailable => 'Ver historico',
      NotificationType.shiftStartReminder => 'Assumir turno',
      NotificationType.shiftEndReminder ||
      NotificationType.shiftOverdueReminder => 'Abrir turno',
      NotificationType.occurrenceParticipationRequested => 'Revisar',
      NotificationType.occurrenceParticipationAccepted ||
      NotificationType.occurrenceParticipationDeclined => 'Ver equipe',
      NotificationType.correctionRequested => 'Corrigir',
      _ => 'Abrir',
    };
  }

  List<String> _contextLines() {
    final values = <String>[];
    final occurrenceId = notification.occurrenceId.trim();
    final crewId = notification.vehicleCrewId;
    final title = notification.occurrenceTitle.trim();
    final requestId = notification.resolvedPromotionRequestId;
    final dogName = notification.dogName?.trim();
    final moduleName = notification.moduleName?.trim();
    final moduleId = notification.moduleId?.trim();
    final milestone = notification.milestoneLabel?.trim();

    if (occurrenceId.isNotEmpty) values.add('OC $occurrenceId');
    if (notification.isVehicleCrewNotification) {
      if (title.isNotEmpty) values.add('VTR $title');
      if (crewId != null) values.add('CREW $crewId');
      return values;
    }
    if (notification.isTrainingPromotionNotification) {
      if (dogName != null && dogName.isNotEmpty) values.add('K9 $dogName');
      if (moduleName != null && moduleName.isNotEmpty) {
        values.add('MOD $moduleName');
      } else if (moduleId != null && moduleId.isNotEmpty) {
        values.add('MOD $moduleId');
      }
      if (milestone != null && milestone.isNotEmpty) {
        values.add('MARCO $milestone');
      }
      if (requestId != null) values.add('REQ $requestId');
      if (values.isEmpty && title.isNotEmpty) values.add(title);
      return values;
    }
    if (notification.isShiftReminderNotification) {
      if (title.isNotEmpty) values.add(title);
      final extra = notification.additionalData?.trim();
      if (extra != null && extra.isNotEmpty) values.add('PLANTAO $extra');
      return values;
    }
    if (title.isNotEmpty) values.add(title);
    final extra = notification.additionalData?.trim();
    if (extra != null && extra.isNotEmpty) values.add(extra);
    return values;
  }
}

class _UnreadDot extends StatelessWidget {
  final Color color;

  const _UnreadDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withAlpha(90), blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
  }
}

class _TechnicalChip extends StatelessWidget {
  final String label;

  const _TechnicalChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(150),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.primary.withAlpha(35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexMono(
          color: AppTheme.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _ActionPill({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyNotificationsState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.surfacePanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withAlpha(45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AppTheme.primary),
              const SizedBox(height: 14),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
