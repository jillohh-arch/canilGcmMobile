import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/core/services/pdf_generator/vaccination_pdf.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';

/// Tela 2.10 — Carteira de Vacinação Completa.
/// Timeline horizontal de próximas doses, histórico agrupado por tipo, exportar PDF.
class VaccinationHistoryScreen extends StatelessWidget {
  final Dog dog;

  const VaccinationHistoryScreen({super.key, required this.dog});

  @override
  Widget build(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final vaccineLogs = _extractVaccineLogs(healthVM.healthLogs);
    final grouped = _groupByType(vaccineLogs);

    // Calculate years of history dynamically
    int yearsOfHistory = 1;
    if (vaccineLogs.isNotEmpty) {
      final oldest = vaccineLogs.last.date;
      final newest = vaccineLogs.first.date;
      final diffDays = newest.difference(oldest).inDays;
      yearsOfHistory = (diffDays / 365.0).ceil();
      if (yearsOfHistory < 1) yearsOfHistory = 1;
    }

    final historyContextLabel =
        '${vaccineLogs.length} vacinas registradas · $yearsOfHistory ${yearsOfHistory == 1 ? 'ano' : 'anos'} de histórico';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppTheme.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF040B0F),
                Color(0xFF06131A),
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
                            _buildTimelineHorizontal(context, vaccineLogs),
                            const SizedBox(height: 24),
                            _buildGroupedList(context, grouped),
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
                color: Colors.white.withOpacity(0.08),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '‹',
                  style: TextStyle(
                    color: Colors.white,
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
                  'PRONTUÁRIO · ${dog.name.toUpperCase()}',
                  style: GoogleFonts.outfit(
                    color: AppTheme.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  'Carteira de vacinação',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
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
          // Large vaccine icon on the right
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Text(
              '💉',
              style: TextStyle(fontSize: 20),
            ),
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
          final pdfBytes = await VaccinationPdf.generate(dog, logs);
          await Printing.layoutPdf(
            onLayout: (format) async => pdfBytes,
            name: 'Carteira_Vacinas_${dog.name}.pdf',
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
          color: const Color(0xFF0F2624),
          border: Border.all(color: AppTheme.success.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Text(
              '📄',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exportar carteira em PDF',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Formato similar à carteira física · para vet ou auditoria',
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
                color: AppTheme.success,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Timeline horizontal ───────────────────────────────────────────

  Widget _buildTimelineHorizontal(BuildContext context, List<HealthLogModel> logs) {
    // Group by vaccine type and get the most recent log of each
    final latestByType = <String, HealthLogModel>{};
    for (final log in logs) {
      final type = log.vaccines.isNotEmpty ? log.vaccines.first : log.logType;
      if (!latestByType.containsKey(type) || log.date.isAfter(latestByType[type]!.date)) {
        latestByType[type] = log;
      }
    }

    if (latestByType.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Nenhuma vacinação registrada',
            style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
          ),
        ),
      );
    }

    // Build timeline events within a 12-month window starting from today
    final now = DateTime.now();
    final timelineEvents = <_TimelineEvent>[];

    latestByType.forEach((type, log) {
      final status = _vaccineStatus(log);
      final isAntiparasitic = log.logType == 'Antipulgas' || log.logType == 'Antiparasitário';
      final validityDays = isAntiparasitic ? 90 : 365;
      final nextDue = log.date.add(Duration(days: validityDays));
      final daysRemaining = nextDue.difference(now).inDays;

      String code = 'V';
      if (type.toLowerCase().contains('raiva') || type.toLowerCase().contains('antirrábica')) {
        code = 'R';
      } else if (log.logType == 'Antipulgas' || log.logType == 'Antiparasitário') {
        code = '!';
      }

      timelineEvents.add(_TimelineEvent(
        name: type,
        nextDue: nextDue,
        daysRemaining: daysRemaining,
        code: code,
        status: status,
      ));
    });

    // Sort by soonest due
    timelineEvents.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    // Dynamic month labels (every 2 months for 12 months)
    final months = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];
    final monthLabels = <String>[];
    for (int i = 0; i <= 12; i += 2) {
      final mIdx = (now.month - 1 + i) % 12;
      monthLabels.add(months[mIdx]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📅 PRÓXIMAS DOSES — 12 MESES',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 24),
          // Custom timeline track container
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Horizontal line track
                  Container(
                    height: 2,
                    margin: const EdgeInsets.only(top: 23),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.error.withOpacity(0.6),
                          AppTheme.warning.withOpacity(0.6),
                          AppTheme.success.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  // Dots
                  ...timelineEvents.map((evt) {
                    // Position calculations (clamp between 0.05 and 0.95 to stay inside the track)
                    double pct = evt.daysRemaining / 365.0;
                    if (pct < 0) pct = 0.0;
                    if (pct > 1) pct = 1.0;
                    final leftOffset = 0.05 + 0.9 * pct;

                    final color = switch (evt.status) {
                      _VaccineStatus.vencida => AppTheme.error,
                      _VaccineStatus.vencendo => AppTheme.warning,
                      _VaccineStatus.emDia => AppTheme.success,
                    };

                    final timeLabel = evt.daysRemaining < 0
                        ? 'Atrasado'
                        : evt.daysRemaining <= 30
                            ? '${evt.daysRemaining} dias'
                            : '${(evt.daysRemaining / 30.0).round()} meses';

                    return Positioned(
                      left: leftOffset * trackWidth - 12,
                      top: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Label above
                          Text(
                            evt.name.split(' ').first,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Dot
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                evt.code,
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF050D10),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Sublabel below
                          Text(
                            timeLabel,
                            style: GoogleFonts.inter(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          const SizedBox(height: 48),
          // Months row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: monthLabels.map((lbl) {
              return Text(
                lbl,
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Grouped Vaccine List ──────────────────────────────────────────

  Widget _buildGroupedList(BuildContext context, Map<String, List<HealthLogModel>> grouped) {
    if (grouped.isEmpty) return const SizedBox.shrink();

    // Group keys mapping to match mockup titles
    String getGroupTitle(String rawType) {
      final type = rawType.toLowerCase();
      if (type.contains('v10') || type.contains('polivalente')) {
        return 'V10 — POLIVALENTE';
      } else if (type.contains('raiva') || type.contains('antirrábica')) {
        return 'ANTIRRÁBICA';
      } else if (type.contains('antipulgas') || type.contains('antiparasitário') || type.contains('bravecto')) {
        return 'ANTIPARASITÁRIO';
      } else {
        return rawType.toUpperCase();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'HISTÓRICO POR VACINA',
              style: GoogleFonts.inter(
                color: AppTheme.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                color: AppTheme.success.withOpacity(0.15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...grouped.entries.map((entry) {
          final groupTitle = getGroupTitle(entry.key);
          final logs = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  groupTitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...logs.map((log) => _buildVaccineCard(context, log)),
              const SizedBox(height: 16),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildVaccineCard(BuildContext context, HealthLogModel log) {
    final status = _vaccineStatus(log);
    final isAntiparasitic = log.logType == 'Antipulgas' || log.logType == 'Antiparasitário';
    final validityDays = isAntiparasitic ? 90 : 365;
    final nextDue = log.date.add(Duration(days: validityDays));

    final statusColor = switch (status) {
      _VaccineStatus.vencida => AppTheme.error,
      _VaccineStatus.vencendo => AppTheme.warning,
      _VaccineStatus.emDia => AppTheme.success,
    };

    final rightLabel = switch (status) {
      _VaccineStatus.vencida => 'VENCEU',
      _VaccineStatus.vencendo => 'VENCE EM',
      _VaccineStatus.emDia => 'PRÓXIMA',
    };

    final rightDateColor = switch (status) {
      _VaccineStatus.vencida => AppTheme.textTertiary,
      _VaccineStatus.vencendo => AppTheme.warning,
      _VaccineStatus.emDia => Colors.white,
    };

    final nextText = DateFormat('dd/MM/yyyy').format(nextDue) + (status == _VaccineStatus.vencida ? ' ✓' : '');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1B22),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // Vaccine info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      log.vaccines.isNotEmpty ? log.vaccines.first : log.logType,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '📄',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    children: [
                      const TextSpan(text: 'Aplicada '),
                      TextSpan(
                        text: DateFormat('dd/MM/yyyy').format(log.date),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      TextSpan(text: ' · Lote ${_extractLot(log)}\n'),
                      TextSpan(
                        text: 'Dr(a). ${log.vetName ?? "Não informado"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      TextSpan(text: ' · CRMV-${(log.professionalCrmv != null && log.professionalCrmv!.isNotEmpty) ? log.professionalCrmv : "N/A"}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Next due column
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                rightLabel,
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                nextText,
                style: GoogleFonts.inter(
                  color: rightDateColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
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
            AppTheme.background.withOpacity(0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          // Navigate to health event registration
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HealthTypeSelectorScreen(dogId: dog.id),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.success,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.success.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline, color: Color(0xFF050D10), size: 18),
              const SizedBox(width: 8),
              Text(
                'REGISTRAR VACINAÇÃO',
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

  List<HealthLogModel> _extractVaccineLogs(List<HealthLogModel> logs) {
    return logs
        .where((log) =>
            log.dogId == dog.id &&
            (log.logType == 'Vacina' ||
                log.vaccines.isNotEmpty ||
                log.logType == 'Antipulgas' ||
                log.logType == 'Antiparasitário'))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Map<String, List<HealthLogModel>> _groupByType(List<HealthLogModel> logs) {
    final grouped = <String, List<HealthLogModel>>{};
    for (final log in logs) {
      final type = log.vaccines.isNotEmpty ? log.vaccines.first : log.logType;
      grouped.putIfAbsent(type, () => []).add(log);
    }
    return grouped;
  }

  _VaccineStatus _vaccineStatus(HealthLogModel log) {
    final isAntiparasitic = log.logType == 'Antipulgas' || log.logType == 'Antiparasitário';
    final validityDays = isAntiparasitic ? 90 : 365;
    final nextDue = log.date.add(Duration(days: validityDays));
    final now = DateTime.now();

    if (now.isAfter(nextDue)) return _VaccineStatus.vencida;
    if (nextDue.difference(now).inDays <= 30) return _VaccineStatus.vencendo;
    return _VaccineStatus.emDia;
  }

  String _extractLot(HealthLogModel log) {
    final obs = log.healthObservations;
    final regExp = RegExp(r'lote:?\s*([^\s,;·\n]+)', caseSensitive: false);
    final match = regExp.firstMatch(obs);
    if (match != null && match.groupCount >= 1) {
      return match.group(1)!;
    }
    return 'N/A';
  }
}

enum _VaccineStatus { emDia, vencendo, vencida }

class _TimelineEvent {
  final String name;
  final DateTime nextDue;
  final int daysRemaining;
  final String code;
  final _VaccineStatus status;

  _TimelineEvent({
    required this.name,
    required this.nextDue,
    required this.daysRemaining,
    required this.code,
    required this.status,
  });
}
