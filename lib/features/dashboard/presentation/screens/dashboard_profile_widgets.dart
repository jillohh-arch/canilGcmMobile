part of 'dashboard_screen.dart';

class _AvatarButton extends StatelessWidget {
  final String? photoStr;
  final String displayName;
  final String raStr;
  final AuthViewModel authVM;
  const _AvatarButton({
    required this.photoStr,
    required this.displayName,
    required this.raStr,
    required this.authVM,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _ProfileSheet(
          displayName: displayName,
          raStr: raStr,
          authVM: authVM,
          photoStr: photoStr,
        ),
      ),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: cs.secondaryContainer,
        backgroundImage: photoStr != null ? NetworkImage(photoStr!) : null,
        child: photoStr == null
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondaryContainer,
                ),
              )
            : null,
      ),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  final String displayName;
  final String raStr;
  final String? photoStr;
  final AuthViewModel authVM;
  const _ProfileSheet({
    required this.displayName,
    required this.raStr,
    required this.photoStr,
    required this.authVM,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: cs.secondaryContainer,
            backgroundImage: photoStr != null ? NetworkImage(photoStr!) : null,
            child: photoStr == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: cs.onSecondaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(displayName, style: Theme.of(context).textTheme.titleLarge),
          if (raStr != '--')
            Text(
              'RA: $raStr',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              authVM.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sair do sistema'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
          ),
        ],
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  final String displayName;
  final int trainingAlerts;
  final int healthAlerts;
  const _GreetingCard({
    required this.displayName,
    required this.trainingAlerts,
    required this.healthAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final total = trainingAlerts + healthAlerts;
    final now = DateTime.now();
    final months = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    final dateStr = '${now.day} de ${months[now.month - 1]}';

    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(225),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _hudCyan, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tudo em dia',
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr · Sem alertas operacionais',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudDanger.withAlpha(105), width: 0.8),
        boxShadow: [BoxShadow(color: _hudDanger.withAlpha(24), blurRadius: 16)],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _hudDanger, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total alerta${total > 1 ? 's' : ''} operacional${total > 1 ? 'is' : ''}',
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                if (trainingAlerts > 0)
                  Text(
                    '• $trainingAlerts cão sem treino há +3 dias',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (healthAlerts > 0)
                  Text(
                    '• $healthAlerts vacina${healthAlerts > 1 ? 's' : ''} vencida${healthAlerts > 1 ? 's' : ''}',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
