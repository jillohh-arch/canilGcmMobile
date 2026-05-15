part of 'shift_assumption_screen.dart';

class _EmptyDogState extends StatelessWidget {
  const _EmptyDogState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pets_rounded,
              size: 64,
              color: AppTheme.textTertiary.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum cão cadastrado',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre um cão no painel administrativo para iniciar o plantão.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}