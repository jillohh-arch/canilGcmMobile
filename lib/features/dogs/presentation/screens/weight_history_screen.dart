import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/core/services/pdf_generator/weight_history_pdf.dart';

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

    final idealMin = widget.dog.idealWeightMin ?? 26.0;
    final idealMax = widget.dog.idealWeightMax ?? 30.0;
    final historyContextLabel =
        '${allEntries.length} pesagens registradas · faixa ideal ${idealMin.toStringAsFixed(0)}-${idealMax.toStringAsFixed(0)}kg';

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
                            _buildExportBar(context, healthVM.healthLogs),
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

  Widget _buildExportBar(BuildContext context, List<HealthLogModel> logs) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        try {
          final pdfBytes = await WeightHistoryPdf.generate(widget.dog, logs);
          await Printing.layoutPdf(
            onLayout: (format) async => pdfBytes,
            name: 'Historico_Peso_${widget.dog.name}.pdf',
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erro ao gerar PDF: $e',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
                backgroundColor: AppTheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
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
    final currentWeight = widget.dog.weight ?? 28.0;
    final trend = _weightTrend(history);

    // Get conductor name for last record
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final weightLogs = healthVM.healthLogs
        .where((l) => l.dogId == widget.dog.id && l.weight != null)
        .toList();
    final author = weightLogs.isNotEmpty
        ? (weightLogs.first.createdBy ?? 'você')
        : 'você';
    final dateStr = weightLogs.isNotEmpty
        ? DateFormat('dd/MM/yyyy').format(weightLogs.first.date)
        : DateFormat('dd/MM/yyyy').format(DateTime.now());

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
                  text: currentWeight.toStringAsFixed(1),
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
                  '$trend · faixa ideal',
                  style: GoogleFonts.inter(
                    color: AppTheme.success,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Medido em $dateStr · $author',
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
                idealWeightMin: widget.dog.idealWeightMin ?? 26.0,
                idealWeightMax: widget.dog.idealWeightMax ?? 30.0,
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
    final prevWeight = index + 1 < allReversed.length
        ? allReversed[index + 1].weight
        : null;
    final prevDate = index + 1 < allReversed.length
        ? allReversed[index + 1].date
        : null;
    final diff = prevWeight != null ? entry.weight - prevWeight : null;
    final days = prevDate != null ? entry.date.difference(prevDate).inDays : 0;

    // Get log observations/metadata for the weight row
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final log = healthVM.healthLogs.firstWhere(
      (l) =>
          l.dogId == widget.dog.id &&
          l.weight == entry.weight &&
          l.date.day == entry.date.day &&
          l.date.month == entry.date.month,
      orElse: () => HealthLogModel(
        dogId: widget.dog.id,
        date: entry.date,
        type: 'other',
        healthObservations: '',
        createdBy: 'você',
      ),
    );

    final author = log.createdBy ?? 'você';
    final hasPhoto = log.attachmentUrl != null || log.mediaAttachments != null;

    // Variation label
    String variationLabel = '→ Estável';
    Color variationColor = AppTheme.textTertiary;
    if (diff != null && diff.abs() >= 0.05) {
      variationLabel =
          '${diff > 0 ? '↑ +' : '↓ '}${diff.toStringAsFixed(1)}kg em ${days}d';
      variationColor = diff > 0 ? AppTheme.warning : AppTheme.success;
    }

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
          // Date
          Text(
            DateFormat('dd/MM').format(entry.date),
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 24),
          // Weight
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
          // Variation & Author details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variationLabel,
                  style: GoogleFonts.inter(
                    color: variationColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$author · canil',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (hasPhoto) const Text('📷', style: TextStyle(fontSize: 14)),
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

  void _showWeighForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.transparent,
      isScrollControlled: true,
      builder: (ctx) => _WeighFormSheet(
        dog: widget.dog,
        healthVM: Provider.of<HealthViewModel>(context, listen: false),
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
      final hasToday = entries.any(
        (e) =>
            e.date.year == DateTime.now().year &&
            e.date.month == DateTime.now().month &&
            e.date.day == DateTime.now().day,
      );
      if (!hasToday) {
        entries.add(
          _WeightEntry(date: DateTime.now(), weight: widget.dog.weight!),
        );
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

/// A stateful bottom sheet for weighing registration
class _WeighFormSheet extends StatefulWidget {
  final Dog dog;
  final HealthViewModel healthVM;

  const _WeighFormSheet({required this.dog, required this.healthVM});

  @override
  State<_WeighFormSheet> createState() => _WeighFormSheetState();
}

class _WeighFormSheetState extends State<_WeighFormSheet> {
  late double _weight;
  String _selectedLocation = 'Canil';
  bool _hasPhoto = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _weight = widget.dog.weight ?? 28.0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfacePanelStrong,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REGISTRAR PESAGEM',
                style: GoogleFonts.outfit(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.close,
                  color: AppTheme.textPrimary.withAlpha(153),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Big selector with +/- buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minus button
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (_weight > 1.0) _weight -= 0.1;
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.textPrimary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '-',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 32),
              // Value display
              Column(
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _weight.toStringAsFixed(1),
                          style: GoogleFonts.outfit(
                            color: AppTheme.textPrimary,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(
                          text: ' kg',
                          style: GoogleFonts.inter(
                            color: AppTheme.textTertiary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PESO DETECTADO',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 32),
              // Plus button
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _weight += 0.1;
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.textPrimary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '+',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Location Checklist
          Text(
            'LOCAL DA PESAGEM',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _locationChip('Canil'),
              const SizedBox(width: 8),
              _locationChip('Veterinário'),
              const SizedBox(width: 8),
              _locationChip('Campo'),
            ],
          ),
          const SizedBox(height: 20),

          // Photo Trigger
          Text(
            'COMPROVAÇÃO (OPCIONAL)',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _hasPhoto = !_hasPhoto;
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _hasPhoto
                    ? AppTheme.surfacePanelAlt
                    : AppTheme.transparent,
                border: Border.all(
                  color: _hasPhoto
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.textPrimary.withValues(alpha: 0.1),
                  style: _hasPhoto ? BorderStyle.solid : BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _hasPhoto
                        ? '✓ Foto da Balança Anexada'
                        : '📷 Anexar foto da balança',
                    style: GoogleFonts.inter(
                      color: _hasPhoto
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Save Button
          GestureDetector(
            onTap: _isSaving
                ? null
                : () async {
                    HapticFeedback.mediumImpact();
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    setState(() => _isSaving = true);
                    final log = HealthLogModel(
                      dogId: widget.dog.id,
                      date: DateTime.now(),
                      type: 'other',
                      subtype: 'Pesagem',
                      weight: _weight,
                      healthObservations:
                          'Pesagem efetuada em $_selectedLocation.',
                      attachmentUrl: _hasPhoto
                          ? 'scale_photo_comprovante_balanca.jpg'
                          : null,
                    );

                    try {
                      await widget.healthVM.addHealthLog(log);
                      await WeightHistoryService().addRecord(
                        widget.dog.id,
                        WeightRecord(
                          weightKg: _weight,
                          measuredAt: log.date,
                          measuredBy: log.createdBy ?? 'app_mobile',
                          context: _selectedLocation,
                          photoUrl: log.attachmentUrl,
                          notes: log.healthObservations,
                        ),
                      );
                      if (!mounted) return;
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Pesagem registrada: ${_weight.toStringAsFixed(1)} kg.',
                          ),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (e) {
                      if (mounted) {
                        setState(() => _isSaving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Erro ao salvar pesagem: $e'),
                            backgroundColor: AppTheme.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
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
                  _isSaving ? 'SALVANDO...' : 'SALVAR REGISTRO',
                  style: GoogleFonts.inter(
                    color: AppTheme.background,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationChip(String value) {
    final selected = _selectedLocation == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedLocation = value),
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
          value,
          style: GoogleFonts.inter(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Painter para gráfico de peso ampliado.
class _WeightFullChartPainter extends CustomPainter {
  final List<_WeightEntry> data;
  final double idealWeightMin;
  final double idealWeightMax;

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

    if (idealWeightMin < minWeight) {
      minWeight = idealWeightMin;
    }
    if (idealWeightMax > maxWeight) {
      maxWeight = idealWeightMax;
    }

    final minVal = minWeight - 0.5;
    final maxVal = maxWeight + 0.5;
    final range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;

    // Draw ideal weight shaded range band
    final yMin =
        size.height - ((idealWeightMin - minVal) / range) * size.height;
    final yMax =
        size.height - ((idealWeightMax - minVal) / range) * size.height;

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
          'IDEAL ${idealWeightMin.toStringAsFixed(0)}-${idealWeightMax.toStringAsFixed(0)}kg',
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
