import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';
import 'package:canil_gcm/core/services/pdf_generator/nutrition_pdf.dart';

/// Tela 2.12 — Nutrição Completa.
/// Prescrição vigente, conformidade detalhada, gráfico 14 dias,
/// filtros, lista de refeições, CTA registrar.
class NutritionFullScreen extends StatefulWidget {
  final Dog dog;

  const NutritionFullScreen({super.key, required this.dog});

  @override
  State<NutritionFullScreen> createState() => _NutritionFullScreenState();
}

class _NutritionFullScreenState extends State<NutritionFullScreen> {
  static final _nutritionColor = AppTheme.attention;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = Provider.of<NutritionViewModel>(context, listen: false);
      vm.loadForDog(widget.dog.id);
      vm.loadFullHistory(widget.dog.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<NutritionViewModel>(context);
    final historyContextLabel =
        '${vm.totalFeedings90d} refeições registradas · 90 dias monitorados';

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
                AppTheme.surfaceBackdrop,
                AppTheme.surfacePanelDeep,
                AppTheme.background,
              ],
            ),
          ),
          child: SafeArea(
            child: vm.historyLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: _nutritionColor,
                      strokeWidth: 2,
                    ),
                  )
                : Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context, historyContextLabel),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                100,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildExportBar(context, vm),
                                  const SizedBox(height: 16),
                                  _buildPrescriptionSection(vm),
                                  const SizedBox(height: 16),
                                  _buildConformityCard(vm),
                                  const SizedBox(height: 16),
                                  _buildChartSection(vm),
                                  const SizedBox(height: 16),
                                  _buildFilters(vm),
                                  const SizedBox(height: 16),
                                  _buildFeedingsList(vm),
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
                    color: _nutritionColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  'Nutrição',
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
          // Meat tag icon on the right
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _nutritionColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Text('🥩', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }

  // ─── Export Bar ────────────────────────────────────────────────────

  Widget _buildExportBar(BuildContext context, NutritionViewModel vm) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        try {
          final pdfBytes = await NutritionPdf.generate(
            dog: widget.dog,
            feedings: vm.historyFeedings,
            prescription: vm.prescription,
            conformityPercent: vm.conformity90d,
            conformCount: vm.conformFeedings90d,
            divergentCount: vm.divergentFeedings90d,
          );
          await Printing.layoutPdf(
            onLayout: (format) async => pdfBytes,
            name: 'Relatorio_Nutricional_${widget.dog.name}.pdf',
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
          color: AppTheme.surfaceNutrition,
          border: Border.all(color: _nutritionColor.withValues(alpha: 0.2)),
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
                    'Exportar relatório nutricional',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Prescrição · conformidade · histórico completo',
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
                color: _nutritionColor,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Prescrição vigente ────────────────────────────────────────────

  Widget _buildPrescriptionSection(NutritionViewModel vm) {
    final prescription = vm.prescription;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('PRESCRIÇÃO VIGENTE'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfacePanelMuted,
            border: Border.all(
              color: AppTheme.textPrimary.withValues(alpha: 0.04),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: prescription == null
              ? Row(
                  children: [
                    Icon(Icons.info_outline, color: _nutritionColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cão sem laudo nutricional · registros não terão referência',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📋', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${prescription.amountGramsPerDay}g/dia · ${prescription.foodType.toLowerCase()}',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Laudo nutricional · Dr(a). ${prescription.vetName ?? "Não informado"}${prescription.vetCrmv != null ? ' · CRMV ${prescription.vetCrmv}' : ''}\nVigente desde ${DateFormat('MM/yyyy').format(prescription.vigentFrom)}',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textTertiary,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (vm.prescriptionHistory.length > 1) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _showPrescriptionHistory(vm),
                        child: Text(
                          'Ver histórico de prescrições →',
                          style: GoogleFonts.inter(
                            color: _nutritionColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  void _showPrescriptionHistory(NutritionViewModel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfacePanelDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HISTÓRICO DE PRESCRIÇÕES',
                style: GoogleFonts.outfit(
                  color: _nutritionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              ...vm.prescriptionHistory.map(
                (p) => _buildPrescriptionHistoryItem(p),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrescriptionHistoryItem(NutritionPrescription p) {
    final isActive = p.isVigentAt(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withValues(alpha: isActive ? 0.08 : 0.04),
        border: Border.all(
          color: isActive
              ? _nutritionColor.withValues(alpha: 0.4)
              : AppTheme.textPrimary.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.amountGramsPerDay}g/dia • ${p.foodType}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(p.vigentFrom)}${p.vigentUntil != null ? ' — ${DateFormat('dd/MM/yyyy').format(p.vigentUntil!)}' : ' — atual'}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'VIGENTE',
                style: GoogleFonts.inter(
                  color: AppTheme.success,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Conformidade ──────────────────────────────────────────────────

  Widget _buildConformityCard(NutritionViewModel vm) {
    final conformColor = vm.conformity90d >= 90
        ? AppTheme.success
        : vm.conformity90d >= 70
        ? _nutritionColor
        : AppTheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanelMuted,
        border: Border.all(color: AppTheme.textPrimary.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: vm.conformity90d.toStringAsFixed(0),
                  style: GoogleFonts.outfit(
                    color: conformColor,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: '%',
                  style: GoogleFonts.inter(
                    color: conformColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
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
                  'Conformidade últimos 90 dias',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${vm.conformFeedings90d} de ${vm.totalFeedings90d} refeições conformes ·\n${vm.divergentFeedings90d} divergências documentadas',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Gráfico de barras 14 dias ────────────────────────────────────

  Widget _buildChartSection(NutritionViewModel vm) {
    final data = vm.dailyConsumption14d;
    final prescribed = vm.prescribedPerDay;

    // Generate month days for chart X-axis
    final chartDays = <String>[];
    for (int i = 13; i >= 0; i--) {
      if (i == 0) {
        chartDays.add('HJ');
      } else {
        final date = DateTime.now().subtract(Duration(days: i));
        chartDays.add(DateFormat('dd').format(date));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('📊 CONSUMO DIÁRIO · ÚLTIMOS 14 DIAS'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withValues(alpha: 0.04),
            border: Border.all(
              color: AppTheme.textPrimary.withValues(alpha: 0.08),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 120,
                child: CustomPaint(
                  size: const Size(double.infinity, 120),
                  painter: _NutritionBarChartPainter(
                    data: data,
                    prescribedPerDay: prescribed,
                    nutritionColor: _nutritionColor,
                    divergentColor: AppTheme.warning,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Days labels row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: chartDays.map((lbl) {
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
        ),
        const SizedBox(height: 8),
        // Legenda
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(_nutritionColor, 'Conforme'),
            const SizedBox(width: 16),
            _legendDot(AppTheme.warning, 'Divergente'),
            const SizedBox(width: 16),
            _legendDot(AppTheme.textPrimary.withAlpha(77), 'Prescrição'),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 10),
        ),
      ],
    );
  }

  // ─── Filtros ───────────────────────────────────────────────────────

  Widget _buildFilters(NutritionViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FILTROS',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip('todas', 'Todas', vm.filterType, vm.setFilterType),
              const SizedBox(width: 6),
              _filterChip(
                'conformes',
                'Conformes',
                vm.filterType,
                vm.setFilterType,
              ),
              const SizedBox(width: 6),
              _filterChip(
                'divergencias',
                'Divergências',
                vm.filterType,
                vm.setFilterType,
              ),
              const SizedBox(width: 12),
              _filterChip(
                'semana',
                'Esta semana',
                vm.filterPeriod,
                vm.setFilterPeriod,
              ),
              const SizedBox(width: 6),
              _filterChip(
                'mes',
                'Este mês',
                vm.filterPeriod,
                vm.setFilterPeriod,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(
    String value,
    String label,
    String current,
    void Function(String) onTap,
  ) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? _nutritionColor.withValues(alpha: 0.12)
              : AppTheme.textPrimary.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? _nutritionColor.withValues(alpha: 0.4)
                : AppTheme.textPrimary.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Align(
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: selected ? _nutritionColor : AppTheme.textTertiary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Lista de refeições ────────────────────────────────────────────

  Widget _buildFeedingsList(NutritionViewModel vm) {
    final feedings = vm.filteredFeedings;

    if (feedings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Nenhuma refeição encontrada para o filtro selecionado',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'REFEIÇÕES',
                  style: GoogleFonts.inter(
                    color: _nutritionColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 1,
                  width: 60,
                  color: _nutritionColor.withValues(alpha: 0.2),
                ),
              ],
            ),
            Text(
              '${feedings.length} registros',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...feedings.take(40).map((f) => _buildFeedingItem(f)),
      ],
    );
  }

  Widget _buildFeedingItem(Feeding f) {
    final isDivergent = f.divergencePercent.abs() > 10;
    final periodIcon = _periodIcon(f.period);
    final periodLabel = NutritionViewModel.periodLabel(f.period).toLowerCase();

    // Calculate relative day name
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(f.fedAt.year, f.fedAt.month, f.fedAt.day)).inDays;
    String dayLabel = DateFormat('dd/MM').format(f.fedAt);
    if (diff == 0) {
      dayLabel = 'HOJE';
    } else if (diff == 1) {
      dayLabel = 'ONTEM';
    }

    final author = f.fedBy == 'unknown' ? 'sistema' : 'você';
    final timeStr = DateFormat('HH:mm').format(f.fedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanelMuted,
        border: Border.all(
          color: isDivergent
              ? AppTheme.warning.withValues(alpha: 0.2)
              : AppTheme.textPrimary.withValues(alpha: 0.04),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Day
          Text(
            dayLabel,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          // Period emoji
          Text(periodIcon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 16),
          // Amount details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: f.amountGrams.toString(),
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: 'g · $periodLabel',
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isDivergent) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${f.divergencePercent > 0 ? '+' : ''}${f.divergencePercent.toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(
                          color: AppTheme.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$author · ${f.divergenceReason ?? timeStr}',
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

  String _periodIcon(String period) {
    switch (period) {
      case 'manha':
        return '🌅';
      case 'almoco':
        return '☀️';
      case 'noite':
        return '🌙';
      default:
        return '🥩';
    }
  }

  // ─── CTA sticky ───────────────────────────────────────────────────

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
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FeedingRegistrationScreen(
                dogId: widget.dog.id,
                dogName: widget.dog.name,
              ),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _nutritionColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _nutritionColor.withValues(alpha: 0.2),
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
                'REGISTRAR ALIMENTAÇÃO',
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

  // ─── Helpers ───────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: _nutritionColor,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─── CustomPainter para gráfico de barras ────────────────────────────

class _NutritionBarChartPainter extends CustomPainter {
  final List<DailyConsumption> data;
  final int prescribedPerDay;
  final Color nutritionColor;
  final Color divergentColor;

  _NutritionBarChartPainter({
    required this.data,
    required this.prescribedPerDay,
    required this.nutritionColor,
    required this.divergentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxGrams = data.fold<int>(
      prescribedPerDay,
      (max, d) => d.totalGrams > max ? d.totalGrams : max,
    );
    final ceiling = (maxGrams * 1.2).toInt();
    if (ceiling == 0) return;

    final barWidth = (size.width - 16) / data.length - 4;
    final barSpacing = (size.width - 16) / data.length;

    // Linha pontilhada da prescrição
    final prescriptionY =
        size.height - (prescribedPerDay / ceiling) * size.height;
    final dashPaint = Paint()
      ..color = AppTheme.textPrimary.withValues(alpha: 0.25)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    double dashX = 8;
    while (dashX < size.width - 8) {
      canvas.drawLine(
        Offset(dashX, prescriptionY),
        Offset(dashX + 4, prescriptionY),
        dashPaint,
      );
      dashX += 8;
    }

    // Label da prescrição
    final textSpan = TextSpan(
      text: '${prescribedPerDay}g',
      style: GoogleFonts.inter(
        color: AppTheme.textPrimary.withAlpha(179),
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
    textPainter.paint(canvas, Offset(8, prescriptionY - 11));

    // Barras
    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      if (d.totalGrams == 0) continue;

      final barHeight = (d.totalGrams / ceiling) * (size.height - 16);
      final x = 8 + i * barSpacing + (barSpacing - barWidth) / 2;
      final y = size.height - barHeight;

      final barPaint = Paint()
        ..color = d.isConform
            ? nutritionColor.withValues(alpha: 0.8)
            : divergentColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
