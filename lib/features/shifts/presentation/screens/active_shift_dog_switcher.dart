part of 'active_shift_dashboard_screen.dart';

/// Public helper to open the dog switcher from other screens.
void showDogSwitcher(BuildContext context) => _showDogSwitcher(context);

/// Bottom sheet para troca rápida de cão durante o turno.
void _showDogSwitcher(BuildContext context) {
  final dogVM = Provider.of<DogViewModel>(context, listen: false);
  final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
  final authVM = Provider.of<AuthViewModel>(context, listen: false);

  final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
  final titularDogs = dogVM.dogs.where((d) => d.conductorRa == currentRa).toList();
  final isTitularOfSingleDog = titularDogs.length <= 1;

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 8),
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
              if (isTitularOfSingleDog)
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.warning.withAlpha(60), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Condutor Titular Único',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Você é titular de apenas um cão associado neste plantão. Para conduzir outro cão, contate o gestor.',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppTheme.textSecondary.withAlpha(100)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Fechar',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...dogVM.dogs
                    .where((d) => d.id != shiftVM.activeDogId)
                    .map((dog) {
                      final fitness = const DogFitnessService().evaluate(dog);
                      return _DogSwitchTile(
                        dog: dog,
                        fitness: fitness,
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          if (fitness.status != DogFitnessStatus.apt) {
                            final confirm = await _showFitnessConfirmation(context, dog, fitness);
                            if (!confirm) return;
                          }
                          Navigator.of(ctx).pop();
                          await shiftVM.switchDog(dog.id);
                        },
                      );
                    }),
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
  final DogFitnessResult fitness;
  final VoidCallback onTap;

  const _DogSwitchTile({
    required this.dog,
    required this.fitness,
    required this.onTap,
  });

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
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
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
                      _buildFitnessBadge(fitness),
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

  Widget _buildFitnessBadge(DogFitnessResult fitness) {
    final Color color;
    final String label;
    final IconData icon;

    switch (fitness.status) {
      case DogFitnessStatus.apt:
        color = AppTheme.success;
        label = 'Apto';
        icon = Icons.check_circle_outline_rounded;
        break;
      case DogFitnessStatus.warning:
        color = AppTheme.warning;
        label = 'Pendência';
        icon = Icons.warning_amber_rounded;
        break;
      case DogFitnessStatus.unfit:
        color = AppTheme.error;
        label = 'Não Apto';
        icon = Icons.cancel_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 3),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _showFitnessConfirmation(
  BuildContext context,
  Dog dog,
  DogFitnessResult fitness,
) async {
  final Color color = fitness.status == DogFitnessStatus.unfit ? AppTheme.error : AppTheme.warning;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: const Color(0xFF0F1E24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(80)),
      ),
      title: Row(
        children: [
          Icon(
            fitness.status == DogFitnessStatus.unfit
                ? Icons.dangerous_rounded
                : Icons.warning_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fitness.status == DogFitnessStatus.unfit
                  ? 'Atenção: K9 Não Apto'
                  : 'Atenção: Pendências do K9',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Você está prestes a ativar o cão ${dog.name}. No entanto, este cão apresenta as seguintes pendências de saúde ou de status:',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ...fitness.pendencies.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        p.severity == DogPendencySeverity.critical
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        color: p.severity == DogPendencySeverity.critical
                            ? AppTheme.error
                            : AppTheme.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.label,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: p.severity == DogPendencySeverity.critical
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
            Text(
              'Deseja prosseguir e assumir este cão mesmo assim?',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text(
            'Cancelar',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            'Sim, confirmar',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}