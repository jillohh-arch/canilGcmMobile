part of 'shift_assumption_screen.dart';

class _DogSelectionCard extends StatelessWidget {
  final Dog dog;
  final bool isSelected;
  final bool isTitular;
  final VoidCallback onTap;

  const _DogSelectionCard({
    required this.dog,
    required this.isSelected,
    required this.isTitular,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppTheme.primary
        : const Color(0xFF1D2C33);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(8)
              : const Color(0xFF0E1A1F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 0.8),
        ),
        child: Row(
          children: [
            // ── Avatar ─────────────────────────────────────────────
            _DogAvatar(dog: dog, isSelected: isSelected),
            const SizedBox(width: 14),

            // ── Info ───────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome + badge titular
                  Row(
                    children: [
                      Text(
                        dog.name,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (isTitular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'SEU CÃO',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Raça + idade + peso
                  Text(
                    _buildSubtitle(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Status badge
                  _StatusBadge(dog: dog),
                ],
              ),
            ),

            // ── Check indicator ────────────────────────────────────
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (dog.breed.isNotEmpty) parts.add(dog.breed);
    parts.add('${dog.age} anos');
    if (dog.weight != null) parts.add('${dog.weight!.toStringAsFixed(1)} kg');
    return parts.join(' · ');
  }
}

class _DogAvatar extends StatelessWidget {
  final Dog dog;
  final bool isSelected;

  const _DogAvatar({required this.dog, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? AppTheme.primary : AppTheme.success;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor.withAlpha(150), width: 2),
      ),
      child: ClipOval(
        child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: dog.profileImageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFF1A2328),
                  child: Icon(Icons.pets, color: AppTheme.textTertiary, size: 24),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF1A2328),
                  child: Icon(Icons.pets, color: AppTheme.textTertiary, size: 24),
                ),
              )
            : Container(
                color: const Color(0xFF1A2328),
                child: Center(
                  child: Text(
                    dog.name.isNotEmpty ? dog.name[0] : 'K',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Dog dog;

  const _StatusBadge({required this.dog});

  @override
  Widget build(BuildContext context) {
    final status = dog.status;
    final isActive = status == 'Ativo';

    final color = isActive ? AppTheme.success : AppTheme.warning;
    final label = isActive ? 'APTO PARA PLANTÃO' : status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AssumptionCta extends StatelessWidget {
  final Dog dog;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AssumptionCta({
    required this.dog,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: const Color(0xFF1D2C33), width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  'ASSUMIR PLANTÃO COM ${dog.name.toUpperCase()}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}