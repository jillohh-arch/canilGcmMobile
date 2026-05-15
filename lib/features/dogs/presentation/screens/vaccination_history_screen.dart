import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';

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
              'Carteira de Vacinação',
              style: GoogleFonts.inter(
                color: AppTheme.success,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${dog.name} • ${vaccineLogs.length} registros',
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
                color: AppTheme.success, size: 20),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Exportação PDF em desenvolvimento',
                      style: GoogleFonts.inter(fontSize: 12)),
                  backgroundColor: AppTheme.success,
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
                _buildTimelineHorizontal(context, vaccineLogs),
                const SizedBox(height: 20),
                _buildGroupedList(context, grouped),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyButton(context),
          ),
        ],
      ),
    );
  }

  // ─── Timeline horizontal ───────────────────────────────────────────

  Widget _buildTimelineHorizontal(
      BuildContext context, List<HealthLogModel> logs) {
    // Agrupa por vacina e pega a mais recente de cada tipo
    final latestByType = <String, HealthLogModel>{};
    for (final log in logs) {
      final type = log.vaccines.isNotEmpty ? log.vaccines.first : log.logType;
      if (!latestByType.containsKey(type) ||
          log.date.isAfter(latestByType[type]!.date)) {
        latestByType[type] = log;
      }
    }

    if (latestByType.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            border: Border.all(color: Colors.white.withAlpha(20)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'Nenhuma vacinação registrada',
              style: GoogleFonts.inter(
                  color: AppTheme.textTertiary, fontSize: 12),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRÓXIMAS DOSES',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: latestByType.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final type = latestByType.keys.elementAt(i);
                final log = latestByType[type]!;
                final status = _vaccineStatus(log);
                return _buildTimelineCard(type, log, status);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(
      String type, HealthLogModel log, _VaccineStatus status) {
    final color = switch (status) {
      _VaccineStatus.emDia => AppTheme.success,
      _VaccineStatus.vencendo => AppTheme.warning,
      _VaccineStatus.vencida => AppTheme.error,
    };

    final label = switch (status) {
      _VaccineStatus.emDia => 'Em dia',
      _VaccineStatus.vencendo => 'Vence em breve',
      _VaccineStatus.vencida => 'Vencida',
    };

    return Container(
      width: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        border: Border.all(color: color.withAlpha(50)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.vaccines_outlined, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            type,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Lista agrupada ────────────────────────────────────────────────

  Widget _buildGroupedList(
      BuildContext context, Map<String, List<HealthLogModel>> grouped) {
    if (grouped.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HISTÓRICO POR VACINA',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          ...grouped.entries.map((entry) =>
              _buildVaccineGroup(context, entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildVaccineGroup(
      BuildContext context, String type, List<HealthLogModel> logs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        border: Border.all(color: Colors.white.withAlpha(15)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: AppTheme.textTertiary,
          collapsedIconColor: AppTheme.textTertiary,
          title: Row(
            children: [
              Icon(Icons.vaccines_outlined, color: AppTheme.success, size: 16),
              const SizedBox(width: 8),
              Text(
                type,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${logs.length}',
                  style: GoogleFonts.inter(
                    color: AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          children: logs.map((log) => _buildVaccineItem(log)).toList(),
        ),
      ),
    );
  }

  Widget _buildVaccineItem(HealthLogModel log) {
    final status = _vaccineStatus(log);
    final statusColor = switch (status) {
      _VaccineStatus.emDia => AppTheme.success,
      _VaccineStatus.vencendo => AppTheme.warning,
      _VaccineStatus.vencida => AppTheme.error,
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        border: Border(
          left: BorderSide(color: statusColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: statusColor, size: 14),
              const SizedBox(width: 6),
              Text(
                DateFormat('dd/MM/yyyy').format(log.date),
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (log.vetName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Dr(a). ${log.vetName}',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
          if (log.healthObservations.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              log.healthObservations,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
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
          // Abre o DynamicActivitySheet com categoria Saúde pré-selecionada
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registro de vacinação via Saúde',
                  style: GoogleFonts.inter(fontSize: 12)),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
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
                color: AppTheme.success.withAlpha(51),
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
    // Estima próxima dose: vacinas = 1 ano, antipulgas = 3 meses
    final isAntiparasitic = log.logType == 'Antipulgas' ||
        log.logType == 'Antiparasitário';
    final validityDays = isAntiparasitic ? 90 : 365;
    final nextDue = log.date.add(Duration(days: validityDays));
    final now = DateTime.now();

    if (now.isAfter(nextDue)) return _VaccineStatus.vencida;
    if (nextDue.difference(now).inDays <= 30) return _VaccineStatus.vencendo;
    return _VaccineStatus.emDia;
  }
}

enum _VaccineStatus { emDia, vencendo, vencida }
