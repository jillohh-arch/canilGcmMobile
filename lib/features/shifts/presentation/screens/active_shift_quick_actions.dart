part of 'active_shift_dashboard_screen.dart';

/// Seção "Registros rápidos" com botões carregados do Firestore.
class _QuickActionsSection extends StatelessWidget {
  final Dog dog;
  final List<QuickAction> actions;

  const _QuickActionsSection({required this.dog, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REGISTROS RÁPIDOS',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        if (actions.isEmpty)
          _buildFallbackActions(context)
        else
          Row(
            children: [
              for (int i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _QuickActionButton(
                    label: actions[i].nome,
                    icon: _resolveIcon(actions[i].icone),
                    color: _resolveColor(actions[i].cor),
                    onTap: () => _openSheet(
                      context,
                      actions[i].tipo,
                      actions[i].nome,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildFallbackActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'Ocorrência',
            icon: Icons.assignment_outlined,
            color: AppTheme.error,
            onTap: () => _openSheet(context, 'ocorrencia', 'Ocorrência'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Treino',
            icon: Icons.fitness_center_rounded,
            color: AppTheme.primary,
            onTap: () => _openSheet(context, 'treino', 'Treino'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Saúde',
            icon: Icons.medical_services_outlined,
            color: AppTheme.success,
            onTap: () => _openSheet(context, 'saude', 'Saúde'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Rotina',
            icon: Icons.schedule_rounded,
            color: AppTheme.attention,
            onTap: () => _openSheet(context, 'rotina', 'Rotina'),
          ),
        ),
      ],
    );
  }

  void _openSheet(BuildContext context, String tipo, String nome) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: nome,
        dogId: dog.id,
        dogName: dog.name,
      ),
    );
  }

  IconData _resolveIcon(String? iconName) {
    switch (iconName) {
      case 'assignment':
        return Icons.assignment_outlined;
      case 'fitness_center':
        return Icons.fitness_center_rounded;
      case 'medical_services':
        return Icons.medical_services_outlined;
      case 'schedule':
        return Icons.schedule_rounded;
      case 'pets':
        return Icons.pets_rounded;
      default:
        return Icons.radio_button_checked;
    }
  }

  Color _resolveColor(String? colorName) {
    switch (colorName) {
      case 'red':
      case 'danger':
        return AppTheme.error;
      case 'green':
      case 'success':
        return AppTheme.success;
      case 'amber':
      case 'warning':
        return AppTheme.warning;
      case 'orange':
      case 'attention':
        return AppTheme.attention;
      default:
        return AppTheme.primary;
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}