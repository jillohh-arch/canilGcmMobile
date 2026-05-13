part of 'active_shift_dashboard_screen.dart';

/// Seção "REGISTROS RÁPIDOS" com botões carregados do Firestore.
class _QuickActionsSection extends StatelessWidget {
  final Dog dog;
  final List<QuickAction> actions;

  const _QuickActionsSection({required this.dog, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: _hudCyan, size: 16),
            const SizedBox(width: 6),
            Text(
              'REGISTROS RÁPIDOS',
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ],
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
                    borderColor: _resolveColor(actions[i].cor),
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

  /// Fallback caso a coleção atalhos_registro esteja vazia.
  Widget _buildFallbackActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'Passeio',
            icon: Icons.directions_walk_rounded,
            borderColor: _hudGreen,
            onTap: () => _openSheet(context, 'Rotina', 'Passeio'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Limpeza',
            icon: Icons.cleaning_services_rounded,
            borderColor: const Color(0xFFAB47BC),
            onTap: () => _openSheet(context, 'Rotina', 'Limpeza'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Alimentação',
            icon: Icons.restaurant_rounded,
            borderColor: _hudCyan,
            onTap: () => _openSheet(context, 'Rotina', 'Alimentação'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'Detecção',
            icon: Icons.track_changes_rounded,
            borderColor: _hudAmber,
            onTap: () => _openSheet(context, 'Treino', null),
          ),
        ),
      ],
    );
  }

  void _openSheet(BuildContext context, String category, String? subtype) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: category,
        dogId: dog.id,
        dogName: dog.name,
      ),
    );
  }

  IconData _resolveIcon(String icone) {
    switch (icone) {
      case 'dog_walk':
      case 'passeio':
        return Icons.directions_walk_rounded;
      case 'cleaning':
      case 'limpeza':
        return Icons.cleaning_services_rounded;
      case 'food':
      case 'alimentacao':
        return Icons.restaurant_rounded;
      case 'detection':
      case 'deteccao':
        return Icons.track_changes_rounded;
      case 'training':
      case 'treino':
        return Icons.fitness_center_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  Color _resolveColor(String cor) {
    switch (cor) {
      case 'verde':
        return _hudGreen;
      case 'vermelho':
        return _hudDanger;
      case 'laranja':
      case 'amber':
        return _hudAmber;
      case 'roxo':
        return const Color(0xFFAB47BC);
      case 'ciano':
      default:
        return _hudCyan;
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color borderColor;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(200),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor.withAlpha(100)),
          boxShadow: [
            BoxShadow(color: borderColor.withAlpha(20), blurRadius: 12),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: borderColor, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
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
