part of 'health_log_screen.dart';

class _EmptyHealth extends StatelessWidget {
  final String filter;

  const _EmptyHealth({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 56,
            color: AppTheme.textPrimary.withAlpha(31),
          ),
          const SizedBox(height: 12),
          Text(
            filter == 'Todos'
                ? 'Nenhum registro médico'
                : 'Sem registros de $filter',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textPrimary.withAlpha(179),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque em "Novo Registro" para adicionar',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textPrimary.withAlpha(179),
            ),
          ),
        ],
      ),
    );
  }
}
