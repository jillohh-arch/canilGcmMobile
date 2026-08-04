import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/core/services/pdf_generator/weight_history_pdf.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_form_sheet.dart';

/// Tela 2.11 — Histórico de Peso Completo.
/// Gráfico ampliado, estatísticas, lista cronológica, registro de pesagem.
class WeightHistoryScreen extends StatefulWidget {
  final Dog dog;
  final WeightHistoryService? historyService;

  const WeightHistoryScreen({
    super.key,
    required this.dog,
    this.historyService,
  });

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  String _periodFilter = '6m'; // '30d' | '6m' | '1ano' | 'tudo'
  late final WeightHistoryService _historyService;

  @override
  void initState() {
    super.initState();
    _historyService = widget.historyService ?? WeightHistoryService();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WeightRecord>>(
      stream: _historyService.watchHistory(widget.dog.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildReadState(
            message: 'Não foi possível carregar o histórico de peso.',
            retry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildHistory(snapshot.data!);
      },
    );
  }

  Widget _buildHistory(List<WeightRecord> records) {
    final allEntries = _extractWeightHistory(records);
    final filtered = _filterByPeriod(allEntries);
    final historyContextLabel = '${allEntries.length} pesagens registradas';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: AppTheme.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.background,
                AppTheme.surfacePanelStrong,
                AppTheme.background,
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, historyContextLabel),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildExportBar(context, records),
                            const SizedBox(height: 16),
                            _buildPeriodChips(),
                            const SizedBox(height: 16),
                            _buildCurrentWeightCard(allEntries),
                            const SizedBox(height: 16),
                            _buildChart(filtered),
                            const SizedBox(height: 16),
                            _buildStats(filtered),
                            const SizedBox(height: 24),
                            _buildWeightList(allEntries),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildStickyButton(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadState({
    required String message,
    required VoidCallback retry,
  }) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            TextButton(onPressed: retry, child: const Text('TENTAR NOVAMENTE')),
          ],
        ),
      ),
    );
  }

  // ─── Header Universal ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, String contextLabel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Boxed back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppTheme.textPrimary.withValues(alpha: 0.15),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '‹',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    height: 0.9,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PRONTUÁRIO · ${widget.dog.name.toUpperCase()}',
                  style: GoogleFonts.outfit(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  'Histórico de peso',
                  style: GoogleFonts.outfit(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  contextLabel,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Weight symbol icon on the right
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Text('⚖', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }

  // ─── Export Bar ────────────────────────────────────────────────────

  Widget _buildExportBar(BuildContext context, List<WeightRecord> records) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        try {
          final logs = records
              .map(
                (record) => HealthLogModel(
                  dogId: widget.dog.id,
                  date: record.measuredAt,
                  type: 'other',
                  subtype: 'Pesagem',
                  weight: record.weightKg,
                  healthObservations: record.notes ?? '',
                  createdBy: record.recordedBy.name,
                ),
              )
              .toList(growable: false);
          final pdfBytes = await WeightHistoryPdf.generate(widget.dog, logs);
          await Printing.layoutPdf(
            onLayout: (format) async => pdfBytes,
            name: 'Historico_Peso_${widget.dog.name}.pdf',
          );
        } catch (e) {
          if (context.mounted) {
            AppFeedback.error(context, e);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSheet,
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Text('📄', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exportar histórico em PDF',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gráfico + tabela completa pra prestação de contas',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '›',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Chips de período ──────────────────────────────────────────────

  Widget _buildPeriodChips() {
    return Row(
      children: [
        _periodChip('30d', '30d'),
        const SizedBox(width: 8),
        _periodChip('6m', '6m'),
        const SizedBox(width: 8),
        _periodChip('1ano', '1 ano'),
        const SizedBox(width: 8),
        _periodChip('tudo', 'Tudo'),
      ],
    );
  }

  Widget _periodChip(String value, String label) {
    final selected = _periodFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _periodFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.textPrimary.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.4)
                : AppTheme.textPrimary.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? AppTheme.primary : AppTheme.textTertiary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ─── Card peso atual ───────────────────────────────────────────────

  Widget _buildCurrentWeightCard(List<_WeightEntry> history) {
    if (history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Nenhuma pesagem canônica registrada.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    final latest = history.last;
    final dateStr = DateFormat('dd/MM/yyyy').format(latest.date);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        border: Border.all(color: AppTheme.textPrimary.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: latest.weight.toStringAsFixed(1),
                  style: GoogleFonts.outfit(
                    color: AppTheme.textPrimary,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ' kg',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PESO ATUAL',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Medido em $dateStr · ${latest.record.recordedBy.name}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Gráfico ───────────────────────────────────────────────────────

  Widget _buildChart(List<_WeightEntry> entries) {
    if (entries.length < 2) {
      return Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.textPrimary.withValues(alpha: 0.04),
          border: Border.all(
            color: AppTheme.textPrimary.withValues(alpha: 0.08),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Dados insuficientes para exibir o gráfico',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // Generate month labels for the filter period
    final now = DateTime.now();
    final months = [
      'NOV',
      'DEZ',
      'JAN',
      'FEV',
      'MAR',
      'ABR',
      'MAI',
      'JUN',
      'JUL',
      'AGO',
      'SET',
      'OUT',
    ];
    final chartMonths = <String>[];
    final count = _periodFilter == '30d' ? 4 : (_periodFilter == '6m' ? 6 : 7);

    for (int i = count - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      chartMonths.add(months[(date.month - 1) % 12]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withValues(alpha: 0.04),
        border: Border.all(color: AppTheme.textPrimary.withValues(alpha: 0.08)),
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
                idealWeightMin: widget.dog.idealWeightMin,
                idealWeightMax: widget.dog.idealWeightMax,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Months row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: chartMonths.map((lbl) {
              return Text(
                lbl,
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
        ],
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

    return Row(
      children: [
        _statCard('MÍNIMO', '${min.toStringAsFixed(1)}kg'),
        const SizedBox(width: 8),
        _statCard('MÉDIA', '${avg.toStringAsFixed(1)}kg'),
        const SizedBox(width: 8),
        _statCard('MÁXIMO', '${max.toStringAsFixed(1)}kg'),
      ],
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.textPrimary.withValues(alpha: 0.04),
          border: Border.all(
            color: AppTheme.textPrimary.withValues(alpha: 0.08),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
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
      return const SizedBox.shrink();
    }

    final reversed = entries.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'PESAGENS',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 1,
                  width: 60,
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
              ],
            ),
            Text(
              '${reversed.length} registros',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...reversed.take(20).map((e) => _buildWeightItem(e, reversed)),
      ],
    );
  }

  Widget _buildWeightItem(_WeightEntry entry, List<_WeightEntry> allReversed) {
    final index = allReversed.indexOf(entry);
    final previous = index + 1 < allReversed.length
        ? allReversed[index + 1]
        : null;
    final diff = previous == null ? null : entry.weight - previous.weight;
    final days = previous == null
        ? 0
        : entry.date.difference(previous.date).inDays;
    final variationLabel = diff == null
        ? 'Primeiro registro'
        : '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}kg em ${days}d';
    final contextLabel = entry.record.contextLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        border: Border.all(color: AppTheme.textPrimary.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            DateFormat('dd/MM').format(entry.date),
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 24),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: entry.weight.toStringAsFixed(1),
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: 'kg',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variationLabel,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [entry.record.recordedBy.name, ?contextLabel].join(' · '),
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── CTA Sticky Button ─────────────────────────────────────────────

  Widget _buildStickyButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withValues(alpha: 0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: GestureDetector(
        onTap: () => _showWeighForm(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_circle_outline,
                color: AppTheme.background,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'REGISTRAR NOVA PESAGEM',
                style: GoogleFonts.inter(
                  color: AppTheme.background,
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

  Future<void> _showWeighForm(BuildContext context) async {
    await showHealthWeightFormSheet(context: context, dog: widget.dog);
  }

  // ─── Helpers ────────────────────────────────────────────────────

  List<_WeightEntry> _extractWeightHistory(List<WeightRecord> records) {
    final entries = records
        .map(
          (record) => _WeightEntry(
            date: record.measuredAt,
            weight: record.weightKg,
            record: record,
          ),
        )
        .toList();
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
}

class _WeightEntry {
  final DateTime date;
  final double weight;
  final WeightRecord record;

  const _WeightEntry({
    required this.date,
    required this.weight,
    required this.record,
  });
}

/// Painter para gráfico de peso ampliado.
class _WeightFullChartPainter extends CustomPainter {
  final List<_WeightEntry> data;
  final double? idealWeightMin;
  final double? idealWeightMax;

  _WeightFullChartPainter({
    required this.data,
    required this.idealWeightMin,
    required this.idealWeightMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final weights = data.map((e) => e.weight).toList();
    double minWeight = weights.reduce((a, b) => a < b ? a : b);
    double maxWeight = weights.reduce((a, b) => a > b ? a : b);

    if (idealWeightMin != null && idealWeightMin! < minWeight) {
      minWeight = idealWeightMin!;
    }
    if (idealWeightMax != null && idealWeightMax! > maxWeight) {
      maxWeight = idealWeightMax!;
    }

    final minVal = minWeight - 0.5;
    final maxVal = maxWeight + 0.5;
    final range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;

    if (idealWeightMin != null && idealWeightMax != null) {
      _drawIdealRange(
        canvas,
        size,
        minVal,
        range,
        idealWeightMin!,
        idealWeightMax!,
      );
    }

    final linePaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.primary.withAlpha(48), AppTheme.primary.withAlpha(0)],
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
        ..color = AppTheme.background
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points.last, 5, bgPaint);
      canvas.drawCircle(points.last, 4, dotPaint);
    }
  }

  void _drawIdealRange(
    Canvas canvas,
    Size size,
    double minVal,
    double range,
    double idealMin,
    double idealMax,
  ) {
    final yMin = size.height - ((idealMin - minVal) / range) * size.height;
    final yMax = size.height - ((idealMax - minVal) / range) * size.height;

    final rectPaint = Paint()
      ..color = AppTheme.success
          .withAlpha(24) // Semi-transparent green
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTRB(0, yMax, size.width, yMin), rectPaint);

    final boundaryPaint = Paint()
      ..color = AppTheme.success.withAlpha(53)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, yMax), Offset(size.width, yMax), boundaryPaint);
    canvas.drawLine(Offset(0, yMin), Offset(size.width, yMin), boundaryPaint);

    // Draw IDEAL text label
    final textSpan = TextSpan(
      text:
          'IDEAL ${idealMin.toStringAsFixed(0)}-${idealMax.toStringAsFixed(0)}kg',
      style: GoogleFonts.inter(
        color: AppTheme.success,
        fontSize: 8,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(8, yMax + 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
