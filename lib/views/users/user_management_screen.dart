import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:canil_gcm/models/user.dart';
import 'package:canil_gcm/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/services/storage_service.dart';
import 'package:canil_gcm/widgets/tactical_card.dart';
import 'user_details_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  void _showUserForm([UserModel? user]) {
    final isEditing = user != null;
    final raController = TextEditingController(text: user?.ra ?? '');
    final nameController = TextEditingController(text: user?.name ?? '');
    final callsignController = TextEditingController(
      text: user?.callsign ?? '',
    );
    final unitController = TextEditingController(text: user?.unit ?? '');
    String accessLevel = user?.accessLevel ?? 'Condutor';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        bool isSaving = false;
        File? imageFile;
        String? currentPhotoUrl = user?.photoUrl;
        final picker = ImagePicker();
        final storageService = StorageService();

        return StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> pickImage() async {
              final XFile? picked = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 75,
              );
              if (picked != null) setS(() => imageFile = File(picked.path));
            }

            final cs = Theme.of(ctx).colorScheme;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEditing ? 'Editar Condutor' : 'Novo Condutor',
                      style: Theme.of(ctx).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Photo
                    Center(
                      child: GestureDetector(
                        onTap: pickImage,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: cs.primaryContainer,
                              backgroundImage: imageFile != null
                                  ? FileImage(imageFile!) as ImageProvider
                                  : (currentPhotoUrl != null
                                        ? NetworkImage(currentPhotoUrl)
                                        : null),
                              child:
                                  (imageFile == null && currentPhotoUrl == null)
                                  ? Icon(
                                      Icons.person,
                                      size: 44,
                                      color: cs.onPrimaryContainer,
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: cs.primary,
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 14,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // RA
                    TextField(
                      controller: raController,
                      enabled: !isEditing,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'R.A.',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: callsignController,
                      decoration: const InputDecoration(
                        labelText: 'Nome de Guerra',
                        prefixIcon: Icon(Icons.military_tech_outlined),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unitController,
                      decoration: const InputDecoration(
                        labelText: 'Unidade',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Access level
                    Text(
                      'Nível de Acesso',
                      style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Condutor',
                          label: Text('Condutor'),
                          icon: Icon(Icons.person_outline),
                        ),
                        ButtonSegment(
                          value: 'Admin',
                          label: Text('Admin'),
                          icon: Icon(Icons.admin_panel_settings_outlined),
                        ),
                      ],
                      selected: {accessLevel},
                      onSelectionChanged: (s) =>
                          setS(() => accessLevel = s.first),
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: cs.primaryContainer,
                        selectedForegroundColor: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),

                    FilledButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (raController.text.isEmpty ||
                                  callsignController.text.isEmpty) {
                                return;
                              }
                              if (nameController.text.isEmpty) {
                                return;
                              }
                              setS(() => isSaving = true);
                              String? finalPhotoUrl = currentPhotoUrl;
                              try {
                                if (imageFile != null) {
                                  if (currentPhotoUrl != null &&
                                      currentPhotoUrl.isNotEmpty) {
                                    try {
                                      await storageService.deleteImageFromUrl(
                                        currentPhotoUrl,
                                      );
                                    } catch (_) {}
                                  }
                                  finalPhotoUrl = await storageService
                                      .uploadProfileImage(imageFile!, 'users');
                                }
                                final newUser = UserModel(
                                  ra: raController.text,
                                  name: nameController.text,
                                  callsign: callsignController.text,
                                  unit: unitController.text,
                                  accessLevel: accessLevel,
                                  photoUrl: finalPhotoUrl,
                                  userBadges: user?.userBadges ?? const [],
                                  xp: user?.xp ?? 0,
                                );
                                if (!ctx.mounted) return;
                                await Provider.of<UserViewModel>(
                                  ctx,
                                  listen: false,
                                ).saveUser(newUser);
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                setS(() => isSaving = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro: $e'),
                                      backgroundColor: cs.error,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('SALVAR'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Theme.of(ctx).colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum guarda cadastrado',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Toque em + para adicionar',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.separated(
                  itemCount: userVM.users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final u = userVM.users[i];
                    return _UserCard(
                      user: u,
                      onEdit: () => _showUserForm(u),
                      onDelete: () => userVM.deleteUser(u.ra),
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

// ─── User Card ─────────────────────────────────────────────────────────────────
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
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF263238)],
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
          border: Border.all(color: Colors.white30, width: 2),
        ),
        child: CircleAvatar(
          radius: 32,
          backgroundColor: Colors.white24,
          backgroundImage: user.photoUrl != null
              ? NetworkImage(user.photoUrl!)
              : null,
          child: user.photoUrl == null
              ? Icon(Icons.person, size: 32, color: Colors.white70)
              : null,
        ),
      ),
      rightBadge: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.edit_outlined,
              color: Colors.white,
              size: 20,
            ),
            onPressed: onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
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
