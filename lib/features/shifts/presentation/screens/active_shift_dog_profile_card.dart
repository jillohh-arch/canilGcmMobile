part of 'active_shift_dashboard_screen.dart';

/// Card clicável do perfil do cão — navega para DogProfileScreen.
class _DogProfileCard extends StatelessWidget {
  final Dog dog;

  const _DogProfileCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DogProfileScreen(dog: dog)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A1F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary.withAlpha(100), width: 1.5),
              ),
              child: ClipOval(
                child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: dog.profileImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: const Color(0xFF1A2328),
                          child: const Icon(Icons.pets, color: AppTheme.textTertiary, size: 20),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFF1A2328),
                          child: const Icon(Icons.pets, color: AppTheme.textTertiary, size: 20),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF1A2328),
                        child: Center(
                          child: Text(
                            dog.name.isNotEmpty ? dog.name[0] : 'K',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),

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
                  const SizedBox(height: 2),
                  Text(
                    '${dog.breed} · ${dog.age} anos${dog.weight != null ? ' · ${dog.weight!.toStringAsFixed(1)} kg' : ''}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}