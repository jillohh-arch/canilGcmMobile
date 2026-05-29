import 'package:flutter/material.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/pending_badge.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/pending_screen.dart';

class CustomDrawer extends StatelessWidget {
  final String userId;

  const CustomDrawer({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Canil GCM',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'RA: $userId',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ],
            ),
          ),

          // Menu de navegação
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // Pendências
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Pendências'),
                  trailing: PendingBadge(userId: userId),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PendingScreen(userId: userId),
                      ),
                    );
                  },
                ),

                // Equipe
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Equipe'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    // Em produção, navegaria para a tela de equipe
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tela de equipe em desenvolvimento'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),

                Divider(height: 32),

                // Outros menus
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Histórico'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/history');
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.pets_outlined),
                  title: const Text('Cães'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/dogs');
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Treinamento'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/training');
                  },
                ),

                Divider(height: 32),

                // Configurações e ajuda
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configurações'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    // Em produção, abrir tela de configurações
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Ajuda'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    // Em produção, abrir tela de ajuda
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  title: const Text('Sair'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    // Em produção, fazer logout
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
