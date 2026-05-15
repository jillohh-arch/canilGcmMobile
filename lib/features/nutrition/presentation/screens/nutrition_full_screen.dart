import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';

/// Tela 2.12 — Nutrição Completa.
/// Prescrição vigente, conformidade detalhada, gráfico 14 dias,
/// filtros, lista de refeições, CTA registrar.
class NutritionFullScreen extends StatefulWidget {
  final String dogId;
  final String dogName;

  const NutritionFullScreen({
    super.key,
    required this.dogId,
    required this.dogName,
  });

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
      vm.loadForDog(widget.dogId);
      vm.loadFullHistory(widget.dogId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<NutritionViewModel>(context);

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
              'Nutrição',
              style: GoogleFonts.inter(
                color: _nutritionColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${widget.dogName} • ${vm.totalFeedings90d} refeições • 90 dias',
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
                color: _nutritionColor, size: 20),
            onPressed: () {
              // TODO: exportar PDF nutricional
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Exportação PDF em desenvolvimento',
                      style: GoogleFonts.inter(fontSize: 12)),
                  backgroundColor: _nutritionColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: vm.historyLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: _nutritionColor, strokeWidth: 2),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildPrescriptionSection(vm),
                      const SizedBox(height: 16),
                      _buildConformityCard(vm),
                      const SizedBox(height: 16),
                      _buildChartSection(vm),
                      const SizedBox(height: 16),
                      _buildFilters(vm),
                      const SizedBox(height: 12),
                      _buildFeedingsList(vm),
                    ],
                  ),
                ),
                // CTA sticky
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

  // ─── Prescrição vigente ────────────────────────────────────────────

  Widget _buildPrescriptionSection(NutritionViewModel vm) {
    final prescription = vm.prescription;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('PRESCRIÇÃO VIGENTE'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: _nutritionColor.withAlpha(40)),
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
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description_outlined,
                              color: _nutritionColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${prescription.amountGramsPerDay}g/dia • ${prescription.foodType}',
                              style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (prescription.vetName != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Laudo: Dr(a). ${prescription.vetName}${prescription.vetCrmv != null ? ' • CRMV ${prescription.vetCrmv}' : ''}',
                          style: GoogleFonts.inter(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Vigente desde ${DateFormat('MM/yyyy').format(prescription.vigentFrom)}',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      if (vm.prescriptionHistory.length > 1) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _showPrescriptionHistory(vm),
                          child: Text(
                            'ver histórico de prescrições →',
                            style: GoogleFonts.inter(
                              color: _nutritionColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _showPrescriptionHistory(NutritionViewModel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
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
                style: GoogleFonts.inter(
                  color: _nutritionColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              ...vm.prescriptionHistory.map((p) => _buildPrescriptionHistoryItem(p)),
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
        color: Colors.white.withAlpha(isActive ? 12 : 5),
        border: Border.all(
          color: isActive ? _nutritionColor.withAlpha(60) : Colors.white.withAlpha(15),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
                color: AppTheme.success.withAlpha(31),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'VIGENTE',
                style: GoogleFonts.inter(
                  color: AppTheme.success,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: conformColor.withAlpha(40)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '${vm.conformity90d.toStringAsFixed(0)}%',
              style: GoogleFonts.inter(
                color: conformColor,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${vm.conformFeedings90d} conformes • ${vm.divergentFeedings90d} divergências',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '90 dias monitorados',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Gráfico de barras 14 dias ────────────────────────────────────

  Widget _buildChartSection(NutritionViewModel vm) {
    final data = vm.dailyConsumption14d;
    final prescribed = vm.prescribedPerDay;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('CONSUMO DIÁRIO • 14 DIAS'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(20)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
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
          ),
          const SizedBox(height: 6),
          // Legenda
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(_nutritionColor, 'Conforme'),
              const SizedBox(width: 16),
              _legendDot(AppTheme.warning, 'Divergente'),
              const SizedBox(width: 16),
              _legendDot(Colors.white24, 'Prescrição'),
            ],
          ),
        ],
      ),
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
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  // ─── Filtros ───────────────────────────────────────────────────────

  Widget _buildFilters(NutritionViewModel vm) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tipo
          Row(
            children: [
              _filterChip('todas', 'Todas', vm.filterType, vm.setFilterType),
              const SizedBox(width: 8),
              _filterChip('conformes', 'Conformes', vm.filterType, vm.setFilterType),
              const SizedBox(width: 8),
              _filterChip('divergencias', 'Divergências', vm.filterType, vm.setFilterType),
            ],
          ),
          const SizedBox(height: 8),
          // Período
          Row(
            children: [
              _filterChip('semana', 'Esta semana', vm.filterPeriod, vm.setFilterPeriod),
              const SizedBox(width: 8),
              _filterChip('mes', 'Este mês', vm.filterPeriod, vm.setFilterPeriod),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
      String value, String label, String current, void Function(String) onTap) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _nutritionColor.withAlpha(20) : Colors.white.withAlpha(8),
          border: Border.all(
            color: selected ? _nutritionColor.withAlpha(80) : Colors.white.withAlpha(20),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? _nutritionColor : AppTheme.textTertiary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('LISTA DE REFEIÇÕES'),
          const SizedBox(height: 8),
          ...feedings.take(50).map((f) => _buildFeedingItem(f)),
        ],
      ),
    );
  }

  Widget _buildFeedingItem(Feeding f) {
    final isDivergent = f.divergencePercent.abs() > 10;
    final periodIcon = _periodIcon(f.period);
    final periodLabel = NutritionViewModel.periodLabel(f.period);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(isDivergent ? 10 : 6),
        border: Border.all(
          color: isDivergent
              ? AppTheme.warning.withAlpha(40)
              : Colors.white.withAlpha(15),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(periodIcon, color: _nutritionColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$periodLabel • ${DateFormat('dd/MM').format(f.fedAt)}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${f.amountGrams}g',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (isDivergent) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${f.divergencePercent > 0 ? '+' : ''}${f.divergencePercent.toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(
                            color: AppTheme.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (f.divergenceReason != null) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.divergenceReason!,
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _periodIcon(String period) {
    switch (period) {
      case 'manha':
        return Icons.wb_sunny_outlined;
      case 'almoco':
        return Icons.wb_cloudy_outlined;
      case 'noite':
        return Icons.nightlight_outlined;
      default:
        return Icons.restaurant;
    }
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
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FeedingRegistrationScreen(
                dogId: widget.dogId,
                dogName: widget.dogName,
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
                color: _nutritionColor.withAlpha(51),
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
                'REGISTRAR ALIMENTAÇÃO',
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

  // ─── Helpers ───────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: _nutritionColor,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
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
    final prescriptionY = size.height - (prescribedPerDay / ceiling) * size.height;
    final dashPaint = Paint()
      ..color = Colors.white.withAlpha(60)
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

    // Barras
    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      if (d.totalGrams == 0) continue;

      final barHeight = (d.totalGrams / ceiling) * (size.height - 16);
      final x = 8 + i * barSpacing + (barSpacing - barWidth) / 2;
      final y = size.height - barHeight;

      final barPaint = Paint()
        ..color = d.isConform
            ? nutritionColor.withAlpha(180)
            : divergentColor.withAlpha(180)
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
