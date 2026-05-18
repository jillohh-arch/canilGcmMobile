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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: AppTheme.primary.withAlpha(40)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Foto maior
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withAlpha(80)),
                color: const Color(0xFF1A2A30),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: dog.profileImageUrl != null &&
                        dog.profileImageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: dog.profileImageUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.pets_rounded,
                          color: AppTheme.primary.withAlpha(128),
                          size: 24,
                        ),
                      )
                    : Center(
                        child: Text(
                          dog.name.isNotEmpty
                              ? dog.name.substring(0, dog.name.length.clamp(0, 3)).toUpperCase()
                              : 'K9',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dog.breed,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dog.status == 'Ativo'
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        dog.status,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: dog.status == 'Ativo'
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Seta
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}