part of 'health_dashboard_screen.dart';

extension _HealthDashboardWeightSection on _HealthDashboardScreenState {
  Widget _buildWeightGraphCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 120, // Altura do gráfico
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF082F49).withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(6),
            topRight: Radius.circular(6),
          ),
          border: Border.all(color: Colors.cyanAccent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Título do Gráfico
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                children: [
                  Icon(
                    Icons.show_chart,
                    size: 14,
                    color: Colors.cyanAccent.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ANÁLISE BIOMÉTRICA: EVOLUÇÃO DE PESO',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Linhas de Grade de Fundo
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Divider(color: Colors.cyan.withValues(alpha: 0.1), height: 1),
                  Divider(color: Colors.cyan.withValues(alpha: 0.1), height: 1),
                  Divider(color: Colors.cyan.withValues(alpha: 0.1), height: 1),
                ],
              ),
            ),
            // A Pintura do Gráfico Customizado
            Positioned.fill(
              top: 30,
              child: CustomPaint(painter: WeightChartPainter()),
            ),
          ],
        ),
      ),
    );
  }
}
