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
          const Icon(
            Icons.health_and_safety_outlined,
            size: 56,
            color: Colors.white12,
          ),
          const SizedBox(height: 12),
          Text(
            filter == 'Todos'
                ? 'Nenhum registro médico'
                : 'Sem registros de $filter',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque em "Novo Registro" para adicionar',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
