part of 'active_shift_dashboard_screen.dart';

/// Bottom sheet para troca rápida de cão durante o turno.
void _showDogSwitcher(BuildContext context) {
  final dogVM = Provider.of<DogViewModel>(context, listen: false);
  final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Trocar cão',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecione outro cão para continuar o plantão',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ...dogVM.dogs
                  .where((d) => d.id != shiftVM.activeDogId)
                  .map((dog) => _DogSwitchTile(
                        dog: dog,
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          Navigator.of(ctx).pop();
                          await shiftVM.switchDog(dog.id);
                        },
                      )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class _DogSwitchTile extends StatelessWidget {
  final Dog dog;
  final VoidCallback onTap;

  const _DogSwitchTile({required this.dog, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.primary.withAlpha(80)),
        ),
        child: ClipOval(
          child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: dog.profileImageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.pets,
                    color: AppTheme.textTertiary,
                    size: 18,
                  ),
                )
              : Center(
                  child: Text(
                    dog.name.isNotEmpty ? dog.name[0] : 'K',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
        ),
      ),
      title: Text(
        dog.name,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        '${dog.breed} · ${dog.status}',
        style: GoogleFonts.inter(
          fontSize: 12,
          color: AppTheme.textSecondary,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: AppTheme.textTertiary,
      ),
    );
  }
}