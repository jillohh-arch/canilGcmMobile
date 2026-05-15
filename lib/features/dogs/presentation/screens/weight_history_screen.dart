import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';

/// Tela 2.11 — Histórico de Peso Completo.
/// Gráfico ampliado, estatísticas, lista cronológica, registro de pesagem.
class WeightHistoryScreen extends StatefulWidget {
  final Dog dog;

  const WeightHistoryScreen({super.key, required this.dog});

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  String _periodFilter = '6m'; // '30d' | '6m' | '1ano' | 'tudo'

  @override
  Widget build(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final allEntries = _extractWeightHistory(healthVM.healthLogs);
    final filtered = _filterByPeriod(allEntries);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Histórico de Peso',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${widget.dog.name} • ${allEntries.length} pesagens',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf_outlined,
                color: AppTheme.primary, size: 20),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Exportação PDF em desenvolvimento',
                      style: GoogleFonts.inter(fontSize: 12)),
                  backgroundColor: AppTheme.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildPeriodChips(),
                const SizedBox(height: 16),
                _buildCurrentWeightCard(),
                const SizedBox(height: 16),
                _buildChart(filtered),
                const SizedBox(height: 16),
                _buildStats(filtered),
                const SizedBox(height: 16),
                _buildWeightList(filtered),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyButton(),
          ),
        ],
      ),
    );
  }

  // ─── Chips de período ──────────────────────────────────────────────

  Widget _buildPeriodChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _periodChip('30d', '30d'),
          const SizedBox(width: 8),
          _periodChip('6m', '6m'),
          const SizedBox(width: 8),
          _periodChip('1ano', '1 ano'),
          const SizedBox(width: 8),
          _periodChip('tudo', 'Tudo'),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    final selected = _periodFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _periodFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withAlpha(20) : Colors.white.withAlpha(8),
          border: Border.all(
            color: selected ? AppTheme.primary.withAlpha(80) : Colors.white.withAlpha(20),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? AppTheme.primary : AppTheme.textTertiary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ─── Card peso atual ───────────────────────────────────────────────

  Widget _buildCurrentWeightCard() {
    final weight = widget.dog.weight;
    if (weight == null) return const SizedBox.shrink();

    final healthVM = Provider.of<HealthViewModel>(context);
    final history = _extractWeightHistory(healthVM.healthLogs);
    final trend = _weightTrend(history);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: AppTheme.primary.withAlpha(40)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              'PESO ATUAL',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(children: [
                TextSpan(
                  text: weight.toStringAsFixed(1),
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' kg',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trend,
                style: GoogleFonts.inter(
                  color: AppTheme.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Gráfico ───────────────────────────────────────────────────────

  Widget _buildChart(List<_WeightEntry> entries) {
    if (entries.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            border: Border.all(color: Colors.white.withAlpha(20)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'Dados insuficientes para gráfico',
              style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: Colors.white.withAlpha(20)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _WeightFullChartPainter(
                  data: entries,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('dd/MM').format(entries.first.date),
                  style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 10),
                ),
                Text(
                  DateFormat('dd/MM').format(entries.last.date),
                  style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Estatísticas ──────────────────────────────────────────────────

  Widget _buildStats(List<_WeightEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final weights = entries.map((e) => e.weight).toList();
    final min = weights.reduce((a, b) => a < b ? a : b);
    final max = weights.reduce((a, b) => a > b ? a : b);
    final avg = weights.reduce((a, b) => a + b) / weights.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _statCard('MÍN', '${min.toStringAsFixed(1)} kg'),
          const SizedBox(width: 8),
          _statCard('MÉD', '${avg.toStringAsFixed(1)} kg'),
          const SizedBox(width: 8),
          _statCard('MÁX', '${max.toStringAsFixed(1)} kg'),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: Colors.white.withAlpha(20)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Lista cronológica ─────────────────────────────────────────────

  Widget _buildWeightList(List<_WeightEntry> entries) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: Text(
            'Nenhuma pesagem registrada',
            style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
          ),
        ),
      );
    }

    final reversed = entries.reversed.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PESAGENS',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          ...reversed.take(30).map((e) => _buildWeightItem(e, reversed)),
        ],
      ),
    );
  }

  Widget _buildWeightItem(
      _WeightEntry entry, List<_WeightEntry> allReversed) {
    final index = allReversed.indexOf(entry);
    final prevWeight =
        index + 1 < allReversed.length ? allReversed[index + 1].weight : null;
    final diff = prevWeight != null ? entry.weight - prevWeight : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        border: Border.all(color: Colors.white.withAlpha(15)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${entry.weight.toStringAsFixed(1)} kg',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (diff != null && diff.abs() >= 0.1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: diff > 0
                              ? AppTheme.warning.withAlpha(20)
                              : AppTheme.success.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                          style: GoogleFonts.inter(
                            color: diff > 0 ? AppTheme.warning : AppTheme.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      DateFormat('dd/MM/yyyy').format(entry.date),
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── CTA sticky ───────────────────────────────────────────────────

  Widget _buildStickyButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: GestureDetector(
        onTap: () => _showWeighForm(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withAlpha(51),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline,
                  color: Color(0xFF050D10), size: 18),
              const SizedBox(width: 8),
              Text(
                'REGISTRAR NOVA PESAGEM',
                style: GoogleFonts.inter(
                  color: const Color(0xFF050D10),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWeighForm() {
    final weightCtrl = TextEditingController(
      text: widget.dog.weight?.toStringAsFixed(1) ?? '',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOVA PESAGEM',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'PESO (KG)',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                border: Border.all(color: Colors.white.withAlpha(30)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: weightCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  suffixText: 'kg',
                  suffixStyle: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 14,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final text = weightCtrl.text.trim().replaceAll(',', '.');
                final weight = double.tryParse(text);
                if (weight == null || weight <= 0) return;

                final healthVM =
                    Provider.of<HealthViewModel>(ctx, listen: false);
                await healthVM.addWeightRecord(
                  widget.dog.id,
                  weight,
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                HapticFeedback.mediumImpact();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'SALVAR',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF050D10),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  List<_WeightEntry> _extractWeightHistory(List<HealthLogModel> logs) {
    final entries = <_WeightEntry>[];

    for (final log in logs) {
      if (log.dogId == widget.dog.id && log.weight != null) {
        entries.add(_WeightEntry(date: log.date, weight: log.weight!));
      }
    }

    if (widget.dog.weight != null) {
      final hasToday = entries.any((e) =>
          e.date.year == DateTime.now().year &&
          e.date.month == DateTime.now().month &&
          e.date.day == DateTime.now().day);
      if (!hasToday) {
        entries.add(_WeightEntry(date: DateTime.now(), weight: widget.dog.weight!));
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  List<_WeightEntry> _filterByPeriod(List<_WeightEntry> entries) {
    if (_periodFilter == 'tudo') return entries;

    final now = DateTime.now();
    final cutoff = switch (_periodFilter) {
      '30d' => now.subtract(const Duration(days: 30)),
      '6m' => now.subtract(const Duration(days: 180)),
      '1ano' => now.subtract(const Duration(days: 365)),
      _ => now.subtract(const Duration(days: 180)),
    };

    return entries.where((e) => e.date.isAfter(cutoff)).toList();
  }

  String _weightTrend(List<_WeightEntry> history) {
    if (history.length < 2) return '→ Estável';
    final first = history.first.weight;
    final last = history.last.weight;
    final diff = last - first;
    if (diff.abs() < 0.5) return '→ Estável';
    if (diff > 0) return '↑ +${diff.toStringAsFixed(1)} kg';
    return '↓ ${diff.toStringAsFixed(1)} kg';
  }
}

class _WeightEntry {
  final DateTime date;
  final double weight;

  const _WeightEntry({required this.date, required this.weight});
}

/// Painter para gráfico de peso ampliado.
class _WeightFullChartPainter extends CustomPainter {
  final List<_WeightEntry> data;

  _WeightFullChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final weights = data.map((e) => e.weight).toList();
    final minVal = weights.reduce((a, b) => a < b ? a : b) - 0.5;
    final maxVal = weights.reduce((a, b) => a > b ? a : b) + 0.5;
    final range = maxVal - minVal;

    final linePaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x304DD0E1), Color(0x004DD0E1)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final points = <Offset>[];

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i].weight - minVal) / range) * size.height;
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 3, dotPaint);
    }

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
