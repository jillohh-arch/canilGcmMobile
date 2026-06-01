import 'dart:io';
import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/widgets/tactical_card.dart';
import 'user_details_screen.dart';

part 'user_form_sheet.dart';
part 'user_form_widgets.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  void _showUserForm([UserModel? user]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _UserFormSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserViewModel>(
      builder: (ctx, userVM, _) {
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text('Guardas', style: Theme.of(ctx).textTheme.titleLarge),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'Novo Condutor',
                  onPressed: () => _showUserForm(),
                ),
                const SizedBox(width: 4),
              ],
            ),
            if (userVM.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (userVM.users.isEmpty)
              const _EmptyUsersState()
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.separated(
                  itemCount: userVM.users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final user = userVM.users[i];
                    return _UserCard(
                      user: user,
                      onEdit: () => _showUserForm(user),
                      onDelete: () => userVM.deleteUser(user.ra),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyUsersState extends StatelessWidget {
  const _EmptyUsersState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Nenhum guarda cadastrado',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque em + para adicionar',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.accessLevel == 'Admin';
    final gradient = isAdmin
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.infoStrong, AppTheme.info],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.surfacePanelAlt, AppTheme.surfacePanel],
          );

    return TacticalCard(
      gradient: gradient,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserDetailsScreen(user: user)),
      ),
      title: user.callsign,
      subtitle: isAdmin ? 'ADMINISTRADOR' : 'CONDUTOR',
      avatar: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.textPrimary.withAlpha(77),
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 32,
          backgroundColor: AppTheme.textPrimary.withAlpha(61),
          backgroundImage: user.photoUrl != null
              ? NetworkImage(user.photoUrl!)
              : null,
          child: user.photoUrl == null
              ? Icon(
                  Icons.person,
                  size: 32,
                  color: AppTheme.textPrimary.withAlpha(179),
                )
              : null,
        ),
      ),
      rightBadge: _UserCardActions(onEdit: onEdit, onDelete: onDelete),
      stats: [
        TacticalCardStat(label: 'RA', value: user.ra),
        TacticalCardStat(
          label: 'Unidade',
          value: user.unit.isEmpty ? '--' : user.unit,
        ),
      ],
    );
  }
}

class _UserCardActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UserCardActions({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.edit_outlined,
            color: AppTheme.textPrimary,
            size: 20,
          ),
          onPressed: onEdit,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(height: 12),
        IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: AppTheme.textPrimary.withAlpha(179),
            size: 20,
          ),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}
