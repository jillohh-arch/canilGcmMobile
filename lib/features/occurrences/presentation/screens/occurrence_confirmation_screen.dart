import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

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
  final String integrityHash;

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
    required this.integrityHash,
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
                      const SizedBox(height: 12),
                      _buildIntegrityCard(context),
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
        color: AppTheme.textPrimary,
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
        color: AppTheme.textPrimary.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
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
          if (data.locationAddress != null && data.locationAddress!.isNotEmpty)
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
            value:
                '${data.eventCount} evento${data.eventCount != 1 ? "s" : ""}',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard() {
    final activeResults = data.results
        .where((r) => r != OccurrenceResult.noOccurrence)
        .toList();

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
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrityCard(BuildContext context) {
    final shortHash = data.integrityHash.length > 16
        ? '${data.integrityHash.substring(0, 16)}...'
        : data.integrityHash;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                'INTEGRIDADE VERIFICADA',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: data.integrityHash));
              AppFeedback.info(context, 'Hash copiado');
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'SHA-256: $shortHash',
                    style: GoogleFonts.sourceCodePro(
                      color: AppTheme.textPrimary.withAlpha(179),
                      fontSize: 11,
                    ),
                  ),
                ),
                Icon(
                  Icons.copy_outlined,
                  color: AppTheme.textPrimary.withAlpha(97),
                  size: 14,
                ),
              ],
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
        final qty = detail['count'] ?? detail['quantity'] ?? '';
        final dest = detail['referral'] ?? detail['destination'] ?? '';
        final parts = <String>[];
        if (qty.toString().isNotEmpty) parts.add('$qty pessoa(s)');
        if (dest.toString().isNotEmpty) parts.add(dest.toString());
        return parts.join(' · ');
      }
      if (result == OccurrenceResult.boCreated) {
        return detail['bo_number']?.toString() ??
            detail['number']?.toString() ??
            '';
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
            onTap: () => _generateAndPreviewPdf(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            icon: Icons.share_outlined,
            label: 'Compartilhar',
            onTap: () => _generateAndSharePdf(context),
          ),
        ),
      ],
    );
  }

  Future<void> _generateAndPreviewPdf(BuildContext context) async {
    HapticFeedback.lightImpact();
    AppFeedback.loading(context, 'Gerando PDF...');

    try {
      final bytes = await _buildPdfBytes(context, auditAction: 'pdf_previewed');
      if (!context.mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Ocorrencia_${data.occurrenceId.substring(0, 8)}.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(context, 'Erro ao gerar PDF: $e');
    }
  }

  Future<void> _generateAndSharePdf(BuildContext context) async {
    HapticFeedback.lightImpact();
    AppFeedback.loading(context, 'Preparando PDF...');

    try {
      final bytes = await _buildPdfBytes(context, auditAction: 'pdf_shared');
      if (!context.mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Ocorrencia_${data.occurrenceId.substring(0, 8)}.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(context, 'Erro ao compartilhar: $e');
    }
  }

  Future<Uint8List> _buildPdfBytes(
    BuildContext context, {
    required String auditAction,
  }) async {
    final occVM = context.read<OccurrenceViewModel>();
    final dogVM = context.read<DogViewModel>();
    final authVM = context.read<AuthViewModel>();

    // Buscar ocorrência: tenta na lista local, depois openOccurrence, depois Firestore
    Occurrence? occ;
    final localMatch = occVM.occurrences.where(
      (o) => o.id == data.occurrenceId,
    );
    if (localMatch.isNotEmpty) {
      occ = localMatch.first;
    }
    occ ??= occVM.openOccurrence;
    occ ??= await occVM.getById(data.occurrenceId);

    if (occ == null) {
      throw Exception('Ocorrência não encontrada');
    }

    final events = await occVM.getEvents(data.occurrenceId);

    // Buscar cão
    final dogId = occ.dogId;
    final dogs = dogVM.dogs.where((d) => d.id == dogId);
    final dog = dogs.isNotEmpty
        ? dogs.first
        : (dogVM.dogs.isNotEmpty ? dogVM.dogs.first : null);

    if (dog == null) {
      throw Exception('Dados do cão não disponíveis');
    }

    final handlerRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';

    final bytes = await occVM.generatePdf(
      occurrence: occ,
      events: events,
      dog: dog,
      handlerName: data.handlerName,
      handlerRa: handlerRa,
    );

    final pdfUrl = await _cachePdfInStorageIfNeeded(occVM, occ, bytes);
    await occVM.recordPdfAccess(
      occurrenceId: occ.id,
      action: auditAction,
      pdfUrl: pdfUrl,
    );
    return bytes;
  }

  Future<String?> _cachePdfInStorageIfNeeded(
    OccurrenceViewModel occurrenceVM,
    Occurrence occurrence,
    Uint8List bytes,
  ) async {
    final existingUrl = occurrence.pdfExportUrl?.trim();
    if (existingUrl?.isNotEmpty == true) return existingUrl;

    try {
      final url = await StorageService().uploadBytes(
        bytes,
        'occurrences/${occurrence.id}/pdf_final.pdf',
        mimeType: 'application/pdf',
      );
      if (url == null) return null;
      await occurrenceVM.updateOccurrence(occurrence.id, {
        'pdf_export_url': url,
        'pdf_generated_at': DateTime.now().toIso8601String(),
      });
      await occurrenceVM.recordPdfAccess(
        occurrenceId: occurrence.id,
        action: 'pdf_cached',
        pdfUrl: url,
      );
      return url;
    } catch (_) {
      // A visualização/compartilhamento do PDF não deve falhar se o cache remoto
      // estiver indisponível. A próxima geração tenta salvar novamente.
      return null;
    }
  }

  // TODO migração manual: _showLoadingSnackbar possuía SnackBar com widget Row
  // customizado (CircularProgressIndicator + texto). AppFeedback.loading()
  // cobre o caso de uso, mas o visual difere do original.
  //
  // void _showLoadingSnackbar(BuildContext context, String message) {
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       content: Row(
  //         children: [
  //           const SizedBox(
  //             width: 16,
  //             height: 16,
  //             child: CircularProgressIndicator(
  //               strokeWidth: 2,
  //               color: AppTheme.textPrimary,
  //             ),
  //           ),
  //           const SizedBox(width: 12),
  //           Text(message, style: GoogleFonts.inter()),
  //         ],
  //       ),
  //       backgroundColor: AppTheme.primary,
  //       duration: const Duration(seconds: 30),
  //     ),
  //   );
  // }

  Widget _buildBottomCta(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.background.withAlpha(0), AppTheme.background],
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
                bottom: BorderSide(color: AppTheme.textPrimary.withAlpha(10)),
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
                color: AppTheme.textPrimary,
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
