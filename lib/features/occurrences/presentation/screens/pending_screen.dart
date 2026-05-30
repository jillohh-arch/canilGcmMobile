import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_team_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart';

class PendingScreen extends StatefulWidget {
  final String userId;

  const PendingScreen({super.key, required this.userId});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  final NotificationService _notificationService = NotificationService();
  late Stream<List<NotificationItem>> _notificationsStream;
  late Stream<int> _unreadCountStream;
  bool _markingAllAsRead = false;

  @override
  void initState() {
    super.initState();
    _notificationsStream = _notificationService.getAllNotifications(
      userId: widget.userId,
    );
    _unreadCountStream = _notificationService.getUnreadCount(
      userId: widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendências'),
        actions: [
          // Badge de contador
          StreamBuilder<int>(
            stream: _unreadCountStream,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              if (count == 0) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(right: 16),
                child: Badge(
                  label: Text('$count'),
                  child: const Icon(Icons.notifications),
                ),
              );
            },
          ),
          // Marcar todas como lidas
          if (_markingAllAsRead)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all),
              tooltip: 'Marcar todas como lidas',
            ),
        ],
      ),
      body: StreamBuilder<List<NotificationItem>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma pendência',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Você não tem notificações pendentes',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          final notifications = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async {
              // Atualizar notificações
              setState(() {});
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (context, index) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationCard(
                  notification: notification,
                  onTap: () => _handleNotificationTap(notification),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    setState(() {
      _markingAllAsRead = true;
    });

    try {
      await _notificationService.markAllAsRead(userId: widget.userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao marcar como lidas: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _markingAllAsRead = false;
      });
    }
  }

  Future<void> _handleNotificationTap(NotificationItem notification) async {
    try {
      await _notificationService.markAsRead(
        userId: widget.userId,
        notificationId: notification.id,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível marcar como lida: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    if (!mounted) return;
    if (notification.isVehicleCrewNotification) {
      final crewId = notification.additionalData?.trim();
      if (crewId == null || crewId.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VehicleCrewProfileScreen(crewId: crewId),
        ),
      );
      return;
    }
    if (_opensActiveOccurrence(notification.type)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ActiveOccurrenceScreen(occurrenceId: notification.occurrenceId),
        ),
      );
      return;
    }
    if (_opensReview(notification.type)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OccurrenceReviewScreen(occurrenceId: notification.occurrenceId),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OccurrenceTeamScreen(occurrenceId: notification.occurrenceId),
      ),
    );
  }

  bool _opensActiveOccurrence(NotificationType type) {
    return type == NotificationType.occurrenceParticipationRequested ||
        type == NotificationType.correctionRequested;
  }

  bool _opensReview(NotificationType type) {
    return type == NotificationType.signatureRequested;
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header com ícone e data
              Row(
                children: [
                  // Ícone
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getIconColor(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getIcon(),
                      color: Theme.of(context).colorScheme.surface,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Título e data
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTitle(),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(notification.createdAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),

                  // Indicador de não lido
                  if (notification.isUnread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Conteúdo
              Text(
                _getMessage(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),

              // Dados adicionais
              if (notification.additionalData != null &&
                  !notification.isVehicleCrewNotification)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Dados: ${notification.additionalData}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.vehicleCrewInvitation:
        return Icons.group_add;
      case NotificationType.vehicleCrewInvitationAccepted:
        return Icons.how_to_reg;
      case NotificationType.vehicleCrewInvitationDeclined:
        return Icons.person_off;
      case NotificationType.occurrenceParticipationRequested:
        return Icons.groups;
      case NotificationType.occurrenceParticipationAccepted:
        return Icons.how_to_reg;
      case NotificationType.occurrenceParticipationDeclined:
        return Icons.person_off;
      case NotificationType.signatureRequested:
        return Icons.request_quote;
      case NotificationType.signatureCompleted:
        return Icons.check_circle;
      case NotificationType.signatureDeclined:
        return Icons.cancel_presentation;
      case NotificationType.correctionRequested:
        return Icons.rule;
      case NotificationType.deadlineWarning:
        return Icons.warning;
      case NotificationType.occurrenceFinalized:
        return Icons.verified;
      case NotificationType.amendmentCreated:
        return Icons.edit_note;
    }
  }

  Color _getIconColor(BuildContext context) {
    switch (notification.type) {
      case NotificationType.vehicleCrewInvitation:
        return Theme.of(context).colorScheme.primary;
      case NotificationType.vehicleCrewInvitationAccepted:
        return Colors.green;
      case NotificationType.vehicleCrewInvitationDeclined:
        return Theme.of(context).colorScheme.error;
      case NotificationType.occurrenceParticipationRequested:
        return Theme.of(context).colorScheme.primary;
      case NotificationType.occurrenceParticipationAccepted:
        return Colors.green;
      case NotificationType.occurrenceParticipationDeclined:
        return Theme.of(context).colorScheme.error;
      case NotificationType.signatureRequested:
        return Theme.of(context).colorScheme.primary;
      case NotificationType.signatureCompleted:
        return Colors.green;
      case NotificationType.signatureDeclined:
        return Theme.of(context).colorScheme.error;
      case NotificationType.correctionRequested:
        return Theme.of(context).colorScheme.tertiary;
      case NotificationType.deadlineWarning:
        return Colors.amber.shade800;
      case NotificationType.occurrenceFinalized:
        return Theme.of(context).colorScheme.secondary;
      case NotificationType.amendmentCreated:
        return Theme.of(context).colorScheme.tertiary;
    }
  }

  String _getTitle() {
    switch (notification.type) {
      case NotificationType.vehicleCrewInvitation:
        return 'Convite para a Guarnição';
      case NotificationType.vehicleCrewInvitationAccepted:
        return 'Convite Aceito';
      case NotificationType.vehicleCrewInvitationDeclined:
        return 'Convite Recusado';
      case NotificationType.occurrenceParticipationRequested:
        return 'Ocorrência Aberta';
      case NotificationType.occurrenceParticipationAccepted:
        return 'Participação Confirmada';
      case NotificationType.occurrenceParticipationDeclined:
        return 'Participação Recusada';
      case NotificationType.signatureRequested:
        return 'Solicitação de Assinatura';
      case NotificationType.signatureCompleted:
        return 'Assinatura Realizada';
      case NotificationType.signatureDeclined:
        return 'Assinatura Recusada';
      case NotificationType.correctionRequested:
        return 'Correção Solicitada';
      case NotificationType.deadlineWarning:
        return 'Prazo de Assinatura Vencendo';
      case NotificationType.occurrenceFinalized:
        return 'Ocorrência Finalizada';
      case NotificationType.amendmentCreated:
        return 'Aditamento Criado';
    }
  }

  String _getMessage() {
    switch (notification.type) {
      case NotificationType.vehicleCrewInvitation:
        return 'Você recebeu um convite para compor a guarnição "${notification.occurrenceTitle}".';
      case NotificationType.vehicleCrewInvitationAccepted:
        return 'Um condutor aceitou o convite para a guarnição "${notification.occurrenceTitle}".';
      case NotificationType.vehicleCrewInvitationDeclined:
        return 'Um condutor recusou o convite para a guarnição "${notification.occurrenceTitle}".';
      case NotificationType.occurrenceParticipationRequested:
        return 'Você foi incluído na ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.occurrenceParticipationAccepted:
        return 'Um integrante confirmou ciência da ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.occurrenceParticipationDeclined:
        return 'Um integrante recusou participação na ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.signatureRequested:
        return 'Você foi convidado a assinar a ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.signatureCompleted:
        return 'O integrante "${notification.additionalData}" assinou a ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.signatureDeclined:
        return 'Um integrante recusou assinar a ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.correctionRequested:
        return 'Foi solicitada correção na ocorrência "${notification.occurrenceTitle}"';
      case NotificationType.deadlineWarning:
        return 'O prazo para assinar a ocorrência "${notification.occurrenceTitle}" está expirando';
      case NotificationType.occurrenceFinalized:
        return 'A ocorrência "${notification.occurrenceTitle}" foi finalizada com sucesso';
      case NotificationType.amendmentCreated:
        return 'Um aditamento foi criado na ocorrência "${notification.occurrenceTitle}"';
    }
  }
}
