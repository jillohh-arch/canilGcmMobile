import 'package:flutter/material.dart';
import 'package:canil_gcm/core/services/notification_service.dart';

class PendingBadge extends StatelessWidget {
  final String userId;

  const PendingBadge({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();

    return StreamBuilder<int>(
      stream: notificationService.getUnreadCount(userId: userId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        if (count == 0) {
          return const SizedBox.shrink();
        }

        return Badge(
          isLabelVisible: true,
          label: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(fontSize: 11),
          ),
          child: const Icon(Icons.notifications_outlined),
        );
      },
    );
  }
}
