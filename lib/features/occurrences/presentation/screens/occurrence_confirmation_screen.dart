import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';

class OccurrenceConfirmationData {
  final String occurrenceId;
  final String typeName;
  final String durationLabel;
  final String? locationAddress;
  final String dogName;
  final String handlerName;
  final int eventCount;
  final List<OccurrenceResult> results;
  final Map<String, dynamic>? details;

  const OccurrenceConfirmationData({
    required this.occurrenceId,
    required this.typeName,
    required this.durationLabel,
    this.locationAddress,
    required this.dogName,
    required this.handlerName,
    required this.eventCount,
    required this.results,
    this.details,
  });
}

class OccurrenceConfirmationScreen extends StatelessWidget {
  final OccurrenceConfirmationData data;

  const OccurrenceConfirmationScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),
                      _buildSuccessIcon(),
                      const SizedBox(height: 16),
                      _buildSuccessTitle(),
                      const SizedBox(height: 6),
                      _buildSuccessSubtitle(),
                      const SizedBox(height: 24),
                      _buildSummaryCard(),
                      if (_hasResults) ...[
                        const SizedBox(height: 12),
                        _buildResultsCard(),
                      ],
                      const SizedBox(height: 16),
                      _buildActionButtons(context),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              _buildBottomCta(context),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasResults =>
      data.results.isNotEmpty &&
      !data.results.contains(OccurrenceResult.noOccurrence);

  Widget _buildSuccessIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(38),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.success.withAlpha(102), width: 3),
      ),
      child: const Icon(Icons.check_rounded, color: AppTheme.success, size: 42),
    );
  }

  Widget _buildSuccessTitle() {
    return Text(
      'Ocorrência finalizada',
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildSuccessSubtitle() {
    return Text(
      'REGISTRO INSTITUCIONAL CRIADO',
      style: GoogleFonts.inter(
        color: AppTheme.success,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.shield_outlined,
            label: 'Natureza',
            value: data.typeName,
          ),
          _SummaryRow(
            icon: Icons.schedule_outlined,
            label: 'Duração',
            value: data.durationLabel,
          ),
          if (data.locationAddress != null &&
              data.locationAddress!.isNotEmpty)
            _SummaryRow(
              icon: Icons.location_on_outlined,
              label: 'Local',
              value: data.locationAddress!,
            ),
          _SummaryRow(
            icon: Icons.pets_outlined,
            label: 'Binômio',
            value: '${data.dogName} · ${data.handlerName}',
          ),
          _SummaryRow(
            icon: Icons.list_alt_outlined,
            label: 'Eventos registrados',
            value: '${data.eventCount} evento${data.eventCount != 1 ? "s" : ""}',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard() {
    final activeResults =
        data.results.where((r) => r != OccurrenceResult.noOccurrence).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESULTADOS DA OCORRÊNCIA',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...activeResults.map((r) => _buildResultItem(r)),
        ],
      ),
    );
  }

  Widget _buildResultItem(OccurrenceResult result) {
    final detail = _getResultDetail(result);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check, color: AppTheme.success, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail.isNotEmpty ? '${result.label} · $detail' : result.label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getResultDetail(OccurrenceResult result) {
    if (data.details == null) return '';
    final key = result.toMap();
    final detail = data.details![key];
    if (detail == null) return '';

    if (result == OccurrenceResult.drugSeized && detail is List) {
      final drugs = detail.cast<Map<String, dynamic>>();
      if (drugs.isEmpty) return '';
      if (drugs.length == 1) {
        final d = drugs.first;
        final parts = <String>[];
        if ((d['weight_grams'] ?? '').toString().isNotEmpty) {
          parts.add('${d["weight_grams"]}g');
        }
        if ((d['type'] ?? '').toString().isNotEmpty) {
          parts.add('${d["type"]}');
        }
        return parts.join(' de ');
      }
      return '${drugs.length} substâncias';
    }

    if (detail is Map<String, dynamic>) {
      if (result == OccurrenceResult.personDetained) {
        final qty = detail['quantity'] ?? '';
        final dest = detail['destination'] ?? '';
        final parts = <String>[];
        if (qty.toString().isNotEmpty) parts.add('$qty pessoa(s)');
        if (dest.toString().isNotEmpty) parts.add(dest.toString());
        return parts.join(' · ');
      }
      if (result == OccurrenceResult.boCreated) {
        return detail['number']?.toString() ?? '';
      }
    }
    return '';
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.description_outlined,
            label: 'Gerar PDF',
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Geração de PDF disponível em breve',
                      style: GoogleFonts.inter()),
                  backgroundColor: AppTheme.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            icon: Icons.share_outlined,
            label: 'Compartilhar',
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Compartilhamento disponível em breve',
                      style: GoogleFonts.inter()),
                  backgroundColor: AppTheme.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomCta(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
          ],
          stops: const [0.0, 0.2],
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.mediumImpact();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: AppTheme.background,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            'VOLTAR AO TURNO',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withAlpha(10)),
              ),
            ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withAlpha(77)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
