part of 'health_dashboard_screen.dart';

// Pintor Tático para simular o gráfico de evolução do peso
class WeightChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final paintGlow = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.4)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final paintDotOuter = Paint()
      ..color = const Color(0xFF082F49)
      ..style = PaintingStyle.fill;

    final paintDotInner = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;

    // Coordenadas simuladas para o gráfico (pode ser substituído por dados reais no futuro)
    final points = [
      Offset(size.width * 0.05, size.height * 0.8),
      Offset(size.width * 0.25, size.height * 0.6),
      Offset(size.width * 0.50, size.height * 0.75),
      Offset(size.width * 0.75, size.height * 0.3),
      Offset(size.width * 0.95, size.height * 0.2),
    ];

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    // Curva Suave (Cubic Bezier)
    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final controlPointX = p0.dx + (p1.dx - p0.dx) / 2;
      path.cubicTo(controlPointX, p0.dy, controlPointX, p1.dy, p1.dx, p1.dy);
    }

    // Desenha o brilho e depois a linha
    canvas.drawPath(path, paintGlow);
    canvas.drawPath(path, paintLine);

    // Desenha os pontos de marcação
    for (var point in points) {
      canvas.drawCircle(point, 5, paintDotOuter);
      canvas.drawCircle(point, 3, paintDotInner);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
