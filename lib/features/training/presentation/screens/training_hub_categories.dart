part of 'training_hub_screen.dart';

class _TrainingHubCategories extends StatelessWidget {
  final Dog dog;
  final void Function(String category) onCategoryTap;

  const _TrainingHubCategories({
    required this.dog,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CategoryCard(
                icon: Icons.search_rounded,
                label: 'Detecção',
                subtitle: 'Protocolo Ragonha',
                color: AppTheme.primary,
                onTap: () => onCategoryTap('Detecção'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryCard(
                icon: Icons.shield_rounded,
                label: 'Guarda & Proteção',
                subtitle: 'Defesa e contenção',
                color: AppTheme.error,
                onTap: () => onCategoryTap('Guarda & Proteção'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CategoryCard(
                icon: Icons.psychology_rounded,
                label: 'Obediência',
                subtitle: 'Comandos e disciplina',
                color: AppTheme.success,
                onTap: () => onCategoryTap('Obediência'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryCard(
                icon: Icons.school_rounded,
                label: 'Formação BC',
                subtitle: 'Base curricular',
                color: AppTheme.warning,
                onTap: () => onCategoryTap('Formação BC'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CategoryCard(
                icon: Icons.directions_run_rounded,
                label: 'Condicionamento',
                subtitle: 'Físico e resistência',
                color: AppTheme.attention,
                onTap: () => onCategoryTap('Condicionamento'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryCard(
                icon: Icons.air_rounded,
                label: 'Faro / Rastro',
                subtitle: 'Busca e captura',
                color: const Color(0xFF9C27B0),
                onTap: () => onCategoryTap('Faro / Rastro'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}