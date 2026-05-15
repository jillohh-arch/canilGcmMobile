import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';

/// Tela 2.5 — Confirmação Final.
/// Mostra resumo da ocorrência finalizada, hash SHA-256, ações pós-finalização.
class OccurrenceConfirmationScreen extends StatelessWidget {
  final Incident incident;

  const OccurrenceConfirmationScreen({super.key, required this.incident});

  @override
  Widget build(BuildContext context) {
    final hash = _computeHash();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildSuccessHeader(),
              const SizedBox(height: 24),
              _buildSummaryCard(),
              const SizedBox(height: 16),
              _buildHashCard(hash),
              const SizedBox(height: 24),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header de sucesso ─────────────────────────────────────────────

  Widget _buildSuccessHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.success.withAlpha(20),
            border: Border.all(color: AppTheme.success.withAlpha(80), width: 2),
          ),
          child: Icon(Icons.check_rounded, color: AppTheme.success, size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          'OCORRÊNCIA REGISTRADA',
          style: GoogleFonts.inter(
            color: AppTheme.success,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Documento institucional criado',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ─── Card de resumo ────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final duration = incident.endedAt != null
        ? incident.endedAt!.difference(incident.startedAt)
        : DateTime.now().difference(incident.startedAt);
    final durationStr = _formatDuration(duration);
    final dateStr = DateFormat('dd/MM/yyyy').format(incident.startedAt);
    final startStr = _formatTime(incident.startedAt);
    final endStr = incident.endedAt != null
        ? _formatTime(incident.endedAt!)
        : _formatTime(DateTime.now());
    final eventCount = incident.progressUpdates.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border.all(color: AppTheme.success.withAlpha(40)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: AppTheme.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  incident.type ?? 'Ocorrência',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow(Icons.calendar_today, '$dateStr • $startStr — $endStr'),
          const SizedBox(height: 6),
          _summaryRow(Icons.timer_outlined, 'Duração: $durationStr'),
          const SizedBox(height: 6),
          _summaryRow(Icons.location_on_outlined, incident.location),
          const SizedBox(height: 6),
          _summaryRow(Icons.list_alt, '$eventCount eventos'),
          if (incident.outcomes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Resultados:',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ...incident.outcomes.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: AppTheme.success, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          o,
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.textTertiary, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Hash SHA-256 ──────────────────────────────────────────────────

  Widget _buildHashCard(String hash) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        border: Border.all(color: Colors.white.withAlpha(20)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined,
                  color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                'Integridade verificada',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'SHA-256:',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hash,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Ações ─────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        _actionButton(
          icon: Icons.picture_as_pdf_outlined,
          label: 'GERAR PDF',
          color: AppTheme.primary,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Geração de PDF em desenvolvimento',
                    style: GoogleFonts.inter(fontSize: 12)),
                backgroundColor: AppTheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _actionButton(
          icon: Icons.share_outlined,
          label: 'COMPARTILHAR',
          color: AppTheme.attention,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Compartilhamento em desenvolvimento',
                    style: GoogleFonts.inter(fontSize: 12)),
                backgroundColor: AppTheme.attention,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _actionButton(
          icon: Icons.arrow_back_rounded,
          label: 'VOLTAR AO TURNO',
          color: AppTheme.textTertiary,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          border: Border.all(color: color.withAlpha(60)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  String _computeHash() {
    final json = incident.toJson();
    final jsonStr = const JsonEncoder().convert(json);
    final bytes = utf8.encode(jsonStr);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}min';
    }
    return '${d.inMinutes}min';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
