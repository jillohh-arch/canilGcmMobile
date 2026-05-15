part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioPeso on _DogProntuarioTabScreenState {
  Widget _buildPesoSection(Dog dog) {
    if (dog.weight == null) return const SizedBox.shrink();

    final healthVM = Provider.of<HealthViewModel>(context);
    final weightHistory = _extractWeightHistory(healthVM.healthLogs, dog);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('EVOLUÇÃO DO PESO', action: 'Ver tudo →'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(20)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Topo: peso atual + trend
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${dog.weight}',
                            style: GoogleFonts.inter(
                              color: _textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' kg',
                            style: GoogleFonts.inter(
                              color: _textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _greenAccent.withAlpha(31),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _weightTrend(weightHistory),
                        style: GoogleFonts.inter(
                          color: _greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Gráfico simplificado
                if (weightHistory.length >= 2)
                  SizedBox(
                    height: 60,
                    child: CustomPaint(
                      size: const Size(double.infinity, 60),
                      painter: _WeightChartPainter(
                        data: weightHistory.map((e) => e.weight).toList(),
                      ),
                    ),
                  ),
                if (weightHistory.length >= 2) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (weightHistory.isNotEmpty)
                        Text(
                          DateFormat('MMM').format(weightHistory.first.date).toUpperCase(),
                          style: GoogleFonts.inter(color: _dimMuted, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      if (weightHistory.length > 1)
                        Text(
                          DateFormat('MMM').format(weightHistory.last.date).toUpperCase(),
                          style: GoogleFonts.inter(color: _dimMuted, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<({DateTime date, double weight})> _extractWeightHistory(
    List<HealthLogModel> logs,
    Dog dog,
  ) {
    final entries = <({DateTime date, double weight})>[];

    // Extrai pesos dos health logs
    for (final log in logs) {
      if (log.dogId == dog.id && log.weight != null) {
        entries.add((date: log.date, weight: log.weight!));
      }
    }

    // Adiciona peso atual se não está nos logs
    if (dog.weight != null) {
      final hasToday = entries.any((e) =>
          e.date.year == DateTime.now().year &&
          e.date.month == DateTime.now().month &&
          e.date.day == DateTime.now().day);
      if (!hasToday) {
        entries.add((date: DateTime.now(), weight: dog.weight!));
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    // Últimos 7 registros
    if (entries.length > 7) {
      return entries.sublist(entries.length - 7);
    }
    return entries;
  }

  String _weightTrend(List<({DateTime date, double weight})> history) {
    if (history.length < 2) return '→ Estável';
    final first = history.first.weight;
    final last = history.last.weight;
    final diff = last - first;
    if (diff.abs() < 0.5) return '→ Estável';
    if (diff > 0) return '↑ +${diff.toStringAsFixed(1)} kg';
    return '↓ ${diff.toStringAsFixed(1)} kg';
  }
}

/// Painter para o gráfico de peso
class _WeightChartPainter extends CustomPainter {
  final List<double> data;

  _WeightChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minVal = data.reduce((a, b) => a < b ? a : b) - 1;
    final maxVal = data.reduce((a, b) => a > b ? a : b) + 1;
    final range = maxVal - minVal;

    final linePaint = Paint()
      ..color = const Color(0xFF4DD0E1)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x204DD0E1), Color(0x004DD0E1)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = const Color(0xFF4DD0E1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final points = <Offset>[];

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Fill
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Line
    canvas.drawPath(path, linePaint);

    // Dots
    for (final point in points) {
      canvas.drawCircle(point, 3, dotPaint);
    }

    // Last dot bigger
    if (points.isNotEmpty) {
      final bgPaint = Paint()
        ..color = const Color(0xFF050D10)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points.last, 5, bgPaint);
      canvas.drawCircle(points.last, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
