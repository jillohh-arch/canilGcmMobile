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
