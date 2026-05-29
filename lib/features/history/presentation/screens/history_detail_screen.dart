
// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/amendment.dart';
import 'package:canil_gcm/features/occurrences/data/amendment_repository.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/create_amendment_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/history/presentation/widgets/gps_track_detail_widget.dart';
import 'package:canil_gcm/core/services/occurrence_location_service.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/occurrence_displacement_map.dart';

// --- Design tokens from mockup ---
const Color _bg = Color(0xFF050D10);
const Color _cyan = Color(0xFF4DD0E1);
const Color _textPrimary = Color(0xFFFFFFFF);
const Color _textSecondary = Color(0xFFB0C4CC);
const Color _textMuted = Color(0xFF5A7280);
const Color _green = Color(0xFF2ECC71);
const Color _amber = Color(0xFFF1C40F);
const Color _red = Color(0xFFE74C3C);

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;
  const HistoryDetailScreen({super.key, required this.entry});
  @override
  Widget build(BuildContext context) => RegistroDetalhePage(entry: entry);
}

class RegistroDetalhePage extends StatelessWidget {
  final HistoryEntry entry;
  const RegistroDetalhePage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final detail = RecordDetail.fromEntry(entry);

    // Determine the specialized body widget
    final Widget specificBody;
    final lowerTitle = detail.title.toLowerCase();

    if (detail.type == HistoryEntryType.occurrence) {
      specificBody = HistoryOccurrenceBody(detail: detail);
    } else if (detail.type == HistoryEntryType.training) {
      if (lowerTitle.contains('detec') || lowerTitle.contains('faro')) {
        specificBody = HistoryDetectionBody(detail: detail);
      } else if (lowerTitle.contains('guarda') ||
          lowerTitle.contains('protec')) {
        specificBody = HistoryGuardaProtecaoBody(detail: detail);
      } else if (lowerTitle.contains('busca') ||
          lowerTitle.contains('captura') ||
          lowerTitle.contains('rastro') ||
          lowerTitle.contains('rastreio')) {
        specificBody = HistoryBuscaCapturaBody(detail: detail);
      } else {
        specificBody = HistoryObedienciaBody(detail: detail);
      }
    } else if (detail.type == HistoryEntryType.health) {
      specificBody = HistorySaudeBody(detail: detail);
    } else if (detail.type == HistoryEntryType.nutrition) {
      specificBody = HistoryNutricaoBody(detail: detail);
    } else {
      specificBody = HistoryObedienciaBody(detail: detail); // Fallback
    }

    return HistoryDetailScaffold(
      detail: detail,
      body: specificBody,
      onPdfTap: () => _handlePdfAction(context, detail, share: false),
      onShareTap: () => _handlePdfAction(context, detail, share: true),
      onMenuTap: () => _openRecordMenu(context),
    );
  }

  Future<void> _handlePdfAction(
    BuildContext context,
    RecordDetail detail, {
    required bool share,
  }) async {
    final original = detail.source.originalModel;
    if (original is! Occurrence) {
      _notify(context, 'PDF disponível apenas para ocorrências.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            share ? 'Preparando compartilhamento...' : 'Gerando PDF...',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF0F2026),
          behavior: SnackBarBehavior.floating,
        ),
      );

    final occurrenceVM = context.read<OccurrenceViewModel>();
    final dogVM = context.read<DogViewModel>();
    final authVM = context.read<AuthViewModel>();
    try {
      final latestOcc = await occurrenceVM.getById(original.id) ?? original;
      final events = await occurrenceVM.getEvents(original.id);
      final matchingDogs = dogVM.dogs.where((d) => d.id == latestOcc.dogId);
      final dog = matchingDogs.isNotEmpty ? matchingDogs.first : null;
      if (dog == null) throw Exception('Dados do cão não disponíveis');

      final bytes = await occurrenceVM.generatePdf(
        occurrence: latestOcc,
        events: events,
        dog: dog,
        handlerName: detail.handlerName,
        handlerRa: HandlerIdentityService.raFromUser(authVM.user) ?? '',
      );

      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      final filename = 'Ocorrencia_${original.id.substring(0, 8)}.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        await Printing.layoutPdf(onLayout: (_) => bytes, name: filename);
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar PDF: $e',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            backgroundColor: const Color(0xFFE74C3C),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _openRecordMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cyan.withAlpha(77)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MenuRow(
                  icon: Icons.edit_outlined,
                  label: 'Editar registro',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _notify(context, 'Edição do registro preparada.');
                  },
                ),
                Divider(height: 1, color: _cyan.withAlpha(30)),
                _MenuRow(
                  icon: Icons.copy_all_outlined,
                  label: 'Copiar resumo operacional',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _notify(context, 'Resumo operacional copiado.');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.inter(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFF0F2026),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
  }
}

// =============================================================================
// HISTORY DETAIL SCAFFOLD (THE SHELL)
// =============================================================================

class HistoryDetailScaffold extends StatelessWidget {
  final RecordDetail detail;
  final Widget body;
  final VoidCallback onPdfTap;
  final VoidCallback onShareTap;
  final VoidCallback onMenuTap;

  const HistoryDetailScaffold({
    super.key,
    required this.detail,
    required this.body,
    required this.onPdfTap,
    required this.onShareTap,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: _bg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIdentificationCard(context),
                        const SizedBox(height: 16),
                        body,
                        if (detail.type == HistoryEntryType.occurrence &&
                            detail.source.originalModel is Occurrence)
                          _AmendmentsSection(
                            occurrence:
                                detail.source.originalModel as Occurrence,
                          ),
                        const SizedBox(height: 16),
                        _buildIntegrityBlock(context),
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
              child: _CtaBar(onPdfTap: onPdfTap, onShareTap: onShareTap),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: _cyan.withAlpha(10),
        border: Border(bottom: BorderSide(color: _cyan.withAlpha(31))),
      ),
      child: Padding(
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
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.typeLabel.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: _cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Boxed share button
            GestureDetector(
              onTap: onShareTap,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    Icons.share_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentificationCard(BuildContext context) {
    final isFinalized =
        detail.status.toLowerCase().contains('final') ||
        detail.status.toLowerCase().contains('progre');
    final badgeColor = isFinalized ? _green : _amber;
    final badgeText = detail.status.toUpperCase();

    // Secondary line representation
    String secondInfoLabel = 'OPERAÇÃO';
    String secondInfoValue = '13:33 → 13:40';
    if (detail.type == HistoryEntryType.training) {
      secondInfoLabel = 'LINHA';
      secondInfoValue =
          detail.source.details['Linha'] ??
          detail.source.details['Tipo'] ??
          'Geral';
    } else if (detail.type == HistoryEntryType.health) {
      secondInfoLabel = 'TIPO';
      secondInfoValue = detail.source.details['Tipo'] ?? 'Evento';
    } else if (detail.type == HistoryEntryType.nutrition) {
      secondInfoLabel = 'PERÍODO';
      secondInfoValue = detail.source.details['Período'] ?? 'Alimentação';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1B22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${detail.typeLabel} · ${detail.status}',
                      style: GoogleFonts.inter(
                        color: _textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFinalized
                          ? Icons.check_rounded
                          : Icons.info_outline_rounded,
                      color: badgeColor,
                      size: 10,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: GoogleFonts.inter(
                        color: badgeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _identMetaCol('DATA', _fmtDate(detail.dateTime)),
              _identMetaCol(secondInfoLabel, secondInfoValue),
              _identMetaCol('DURAÇÃO', detail.duration),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 12),
          Row(
            children: [
              // Overlapping avatars
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF16242A),
                  border: Border.all(color: _green, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    detail.dogName.isNotEmpty
                        ? detail.dogName[0].toUpperCase()
                        : '🐕',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(-8, 0),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF16242A),
                    border: Border.all(color: _cyan, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      detail.handlerName.isNotEmpty
                          ? detail.handlerName[0].toUpperCase()
                          : '👤',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4), // Compensation
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 11.5,
                    ),
                    children: [
                      TextSpan(
                        text: detail.dogName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: ' · GCM '),
                      TextSpan(
                        text: detail.handlerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: ' · Canil K9 Limeira'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identMetaCol(String key, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key,
          style: GoogleFonts.inter(
            color: _textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: GoogleFonts.ibmPlexMono(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrityBlock(BuildContext context) {
    final isOcc = detail.type == HistoryEntryType.occurrence;
    final occurrenceHash = detail.source.originalModel is Occurrence
        ? (detail.source.originalModel as Occurrence).integrityHash?.trim()
        : null;
    final isFinalizedOcc =
        isOcc && detail.status.toLowerCase().contains('final');
    final hasOccurrenceHash = occurrenceHash?.isNotEmpty == true;

    final count = detail.auditEvents.length;

    // Determine values based on status
    final Color blockColor;
    final IconData blockIcon;
    final String blockTitle;
    final Widget blockBody;

    if (isOcc) {
      if (isFinalizedOcc && hasOccurrenceHash) {
        blockColor = _green;
        blockIcon = Icons.verified_user_outlined;
        blockTitle = 'DOCUMENTO ÍNTEGRO · SHA-256';

        blockBody = Padding(
          padding: const EdgeInsets.only(top: 9),
          child: SelectableText(
            occurrenceHash!,
            style: GoogleFonts.ibmPlexMono(
              color: _textSecondary,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
        );
      } else if (isFinalizedOcc) {
        blockColor = _amber;
        blockIcon = Icons.warning_amber_rounded;
        blockTitle = 'DOCUMENTO FINALIZADO SEM HASH';
        blockBody = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'O registro esta finalizado, mas o hash de integridade nao foi encontrado neste documento.',
            style: GoogleFonts.inter(
              color: _textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        );
      } else {
        blockColor = _amber;
        blockIcon = Icons.pending_actions_outlined;
        blockTitle = 'DOCUMENTO EM ANDAMENTO';
        blockBody = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Aguardando finalização do registro para geração da assinatura criptográfica e do hash SHA-256.',
            style: GoogleFonts.inter(
              color: _textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        );
      }
    } else {
      // Training, Health, Nutrition
      blockColor = _cyan;
      blockIcon = Icons.cloud_done_outlined;
      blockTitle = 'REGISTRO SINCRONIZADO';
      blockBody = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Este registro de ${detail.typeLabel} está homologado e sincronizado com os servidores do Canil Municipal K9 de Limeira. Não requer criptografia individual.',
          style: GoogleFonts.inter(
            color: _textSecondary,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: blockColor.withAlpha(10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: blockColor.withAlpha(38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(blockIcon, color: blockColor, size: 14),
              const SizedBox(width: 8),
              Text(
                blockTitle,
                style: GoogleFonts.inter(
                  color: blockColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          blockBody,
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withAlpha(15)),
          const SizedBox(height: 11),
          InkWell(
            onTap: () => _showAuditTrail(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                    children: [
                      const TextSpan(text: 'Trilha de auditoria · '),
                      TextSpan(
                        text: '$count ${count == 1 ? 'registro' : 'registros'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
          if (isFinalizedOcc) ...[
            const SizedBox(height: 11),
            Container(height: 1, color: Colors.white.withAlpha(15)),
            const SizedBox(height: 11),
            InkWell(
              onTap: () => _openCreateAmendment(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.post_add_rounded, color: _amber, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Adicionar retificação',
                        style: GoogleFonts.inter(
                          color: _amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _amber.withAlpha(150),
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openCreateAmendment(BuildContext context) {
    if (detail.source.originalModel is! Occurrence) return;
    final occ = detail.source.originalModel as Occurrence;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateAmendmentScreen(occurrence: occ),
      ),
    );
  }

  void _showAuditTrail(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withAlpha(180),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: _cyan, width: 1.2)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: _cyan,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Trilha de Auditoria',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final event in detail.auditEvents) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: _green,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.action,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (event.user.isNotEmpty)
                                    Text(
                                      'Por: ${event.user}',
                                      style: GoogleFonts.inter(
                                        color: _textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${_fmtDate(event.timestamp)} ${_fmtTime(event.timestamp)}',
                              style: GoogleFonts.ibmPlexMono(
                                color: _textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// BODY 1: OCORRÊNCIA
// =============================================================================

class HistoryOccurrenceBody extends StatelessWidget {
  final RecordDetail detail;

  const HistoryOccurrenceBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final outcomes = detail.source.details['_outcomes'] as List? ?? [];
    final mediaList = detail.source.details['_mediaAttachments'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats
        Row(
          children: [
            _statItem('${detail.internalEvents.length}', 'EVENTOS'),
            const SizedBox(width: 8),
            _statItem('${mediaList.length}', 'MÍDIAS'),
            const SizedBox(width: 8),
            _statItem('${outcomes.length}', 'RESULTADOS'),
          ],
        ),        // Resultados/Outcomes list
        if (outcomes.isNotEmpty) ...[
          const _SectionLabel('RESULTADOS'),
          const SizedBox(height: 8),
          ...outcomes.map((o) {
            String label = 'Resultado';
            String desc = '';
            if (o is Map) {
              label = o['label']?.toString() ?? 'Resultado';
              desc = o['detail']?.toString() ?? '';
            } else if (o is String) {
              final res = OccurrenceResult.fromMap(o);
              label = res.label;
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _green.withAlpha(12),
                border: Border.all(color: _green.withAlpha(46)),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _green.withAlpha(27),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.check_rounded, color: _green, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (desc.isNotEmpty)
                          Text(
                            desc,
                            style: GoogleFonts.inter(
                              color: _textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // Mapa de deslocamento
        _OccurrenceDisplacementSection(occurrenceId: detail.id),
        const SizedBox(height: 16),

        // Timeline
        _OccurrenceTimelineSection(occurrenceId: detail.id, fallback: detail),
        const SizedBox(height: 16),

        // Relato
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('RELATO INSTITUCIONAL'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Mídias
        if (mediaList.isNotEmpty) ...[
          const _SectionLabel('MÍDIAS'),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: mediaList.length,
              itemBuilder: (context, idx) {
                final map = mediaList[idx] as Map;
                final url = map['url']?.toString() ?? '';
                final timestampStr = map['timestamp'] != null
                    ? DateFormat(
                        'HH:mm',
                      ).format((map['timestamp'] as Timestamp).toDate())
                    : '13:38';
                return Container(
                  width: 96,
                  height: 96,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                    color: const Color(0xFF0E1B20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        if (url.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            width: 96,
                            height: 96,
                            placeholder: (context, url) =>
                                Container(color: Colors.white10),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.image, color: Colors.white24),
                            ),
                          )
                        else
                          const Center(
                            child: Icon(Icons.image, color: Colors.white24),
                          ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Text(
                            timestampStr,
                            style: GoogleFonts.ibmPlexMono(
                              color: _textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _statItem(String number, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: Colors.white.withAlpha(15)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              number,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color: _textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0E1C22)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 26) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// BODY 2: DETECÇÃO (PROTOCOLO RAGONHA)
// =============================================================================

class HistoryDetectionBody extends StatelessWidget {
  final RecordDetail detail;

  const HistoryDetectionBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final session = detail.source.originalModel as TrainingSessionModel?;
    final metadata = session?.metadata ?? const {};

    final line =
        metadata['line']?.toString() ??
        detail.source.details['Linha'] ??
        'Drogas';
    final phase =
        metadata['phase']?.toString() ??
        detail.source.details['current_phase'] ??
        'Fase 3';
    final consecutive = metadata['consecutiveHits'] ?? 10;
    final attempts =
        metadata['attempts'] as List? ??
        ['hit', 'hit', 'hit', 'hit', 'hit', 'hit', 'hit'];

    final requiredHits = _getRequiredHitsForPhase(phase);
    final hitsCount = attempts.where((e) => e == 'hit').length;
    final missesCount = attempts.where((e) => e == 'miss').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PROTOCOLO RAGONHA'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(15)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _chip('LINHA: ${line.toUpperCase()}', true, color: _cyan),
                  const SizedBox(width: 6),
                  _chip('⭐ ${phase.toUpperCase()}', true, color: _amber),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                            children: [
                              TextSpan(
                                text: '$consecutive',
                                style: const TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: ' / $requiredHits',
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'acertos consecutivos sem erro',
                          style: GoogleFonts.inter(
                            color: _textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _green.withAlpha(30),
                      border: Border.all(color: _green.withAlpha(80)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '✓ CRITÉRIO ATINGIDO',
                          style: GoogleFonts.inter(
                            color: _green,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '99,99983% confiança',
                          style: GoogleFonts.inter(
                            color: _textSecondary,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildRoadmap(phase),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Série desta sessão
        const _SectionLabel('SÉRIE DESTA SESSÃO'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${attempts.length} repetições',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$hitsCount acertos · $missesCount erros',
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final item in attempts) ...[
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: item == 'hit'
                            ? _green.withAlpha(40)
                            : _red.withAlpha(40),
                        border: Border.all(
                          color: item == 'hit' ? _green : _red,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          item == 'hit' ? '✓' : '⊘',
                          style: TextStyle(
                            color: item == 'hit' ? _green : _red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.white.withAlpha(10)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: _cyan,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(
                          color: _textSecondary,
                          fontSize: 11.5,
                        ),
                        children: [
                          const TextSpan(text: 'Sessão concluída com '),
                          TextSpan(
                            text: '$hitsCount acertos',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: ' consecutivos. '),
                          TextSpan(
                            text: 'Estágio $phase consolidado.',
                            style: const TextStyle(
                              color: _green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Configuração
        const _SectionLabel('CONFIGURAÇÃO'),
        const SizedBox(height: 8),
        _buildConfigGrid({
          'Ambiente': metadata['environment']?.toString() ?? 'Galpão',
          'Ocultações': metadata['ocultacoes']?.toString() ?? '$hitsCount',
          'Distratores': metadata['distratores']?.toString() ?? '3',
        }),
        const SizedBox(height: 16),

        // Observações
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('OBSERVAÇÕES'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRoadmap(String activePhase) {
    final activeIndex = _phaseIndex(activePhase);
    final phases = const ['F1', 'F2', 'F3', 'F4', 'F5'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(phases.length, (index) {
        final done = index < activeIndex;
        final current = index == activeIndex;
        final border = done ? _green : (current ? _amber : Colors.white24);
        final bg = done
            ? _green.withAlpha(40)
            : (current ? _amber.withAlpha(40) : Colors.transparent);
        final textColor = done ? _green : (current ? _amber : _textMuted);

        return Expanded(
          child: Row(
            children: [
              if (index > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: index <= activeIndex ? _green : Colors.white10,
                  ),
                ),
              Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bg,
                      border: Border.all(color: border, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        done ? '✓' : phases[index],
                        style: TextStyle(
                          color: textColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phases[index],
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (index < phases.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: index < activeIndex ? _green : Colors.white10,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  int _phaseIndex(String phase) {
    final lower = phase.toLowerCase();
    if (lower.contains('1')) return 0;
    if (lower.contains('2')) return 1;
    if (lower.contains('3')) return 2;
    if (lower.contains('4')) return 3;
    if (lower.contains('5')) return 4;
    return 2;
  }

  int _getRequiredHitsForPhase(String phase) {
    final lower = phase.toLowerCase();
    if (lower.contains('1')) return 3;
    if (lower.contains('2')) return 3;
    if (lower.contains('3')) return 10;
    if (lower.contains('4')) return 3;
    if (lower.contains('5')) return 5;
    return 10;
  }

  Widget _chip(String label, bool selected, {Color color = _cyan}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color.withAlpha(30) : Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? color : Colors.white.withAlpha(25),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: selected ? color : _textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// =============================================================================
// BODY 3: GUARDA & PROTEÇÃO
// =============================================================================

class HistoryGuardaProtecaoBody extends StatelessWidget {
  final RecordDetail detail;

  const HistoryGuardaProtecaoBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final session = detail.source.originalModel as TrainingSessionModel?;
    final metadata = session?.metadata ?? const {};

    final activeImpulse = metadata['impulse']?.toString() ?? 'Defesa';
    final figurante = metadata['figurante']?.toString() ?? 'GCM Souza';
    final equipment = metadata['equipment']?.toString() ?? 'Manga';
    final cmdLarga = metadata['commands'] is List
        ? (metadata['commands'] as List).join(', ')
        : 'Parcial';

    final capabilities =
        metadata['capabilities'] as List? ??
        ['Mordida firme', 'Boca cheia', 'Estabilização'];

    // Evaluation scores mapping
    final evaluation = metadata['evaluation'] as Map? ?? {};
    final int biteQuality =
        (evaluation['biteQuality'] ??
                evaluation['Qualidade da mordida'] ??
                evaluation['Mordida (qualidade técnica)'] ??
                4)
            as int;
    final int controlLarga =
        (evaluation['controlLarga'] ??
                evaluation['Controle / comando "Larga"'] ??
                evaluation['Controle (resposta a comandos)'] ??
                3)
            as int;
    final int courageConfront =
        (evaluation['courageConfront'] ??
                evaluation['Coragem no confronto'] ??
                evaluation['Drive (intensidade)'] ??
                4)
            as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('IMPULSOS · ESTADO ATUAL'),
        const SizedBox(height: 8),
        _buildImpulseRow(
          'Caça',
          '🦌',
          'Consolidado',
          _green,
          activeImpulse.contains('Caça'),
        ),
        const SizedBox(height: 6),
        _buildImpulseRow(
          'Defesa',
          '🛡',
          'Desenvolvendo',
          _amber,
          activeImpulse.contains('Defesa'),
        ),
        const SizedBox(height: 6),
        _buildImpulseRow(
          'Agressão',
          '⚔',
          'Não iniciado',
          _textMuted,
          activeImpulse.contains('Agressão'),
        ),
        const SizedBox(height: 16),

        // Figurante evaluation
        const _SectionLabel('AVALIAÇÃO DO FIGURANTE'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white12,
                    ),
                    child: const Center(
                      child: Text('👤', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          figurante,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Figurante · veste a manga',
                          style: GoogleFonts.inter(
                            color: _textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildRatingRow('Qualidade da mordida', biteQuality),
              _buildRatingRow('Controle / comando "Larga"', controlLarga),
              _buildRatingRow('Coragem no confronto', courageConfront),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Capacidades reforçadas
        const _SectionLabel('CAPACIDADES REFORÇADAS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: capabilities.map((cap) {
            final name = cap.toString();
            final isDone = name.toLowerCase().contains('firme');
            final color = isDone ? _green : _amber;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                border: Border.all(color: color.withAlpha(60)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDone)
                    const Icon(Icons.check_rounded, color: _green, size: 10)
                  else
                    const Text(
                      '◑',
                      style: TextStyle(color: _amber, fontSize: 10),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Configuração
        const _SectionLabel('CONFIGURAÇÃO'),
        const SizedBox(height: 8),
        _buildConfigGrid({
          'Equipamento': equipment,
          'Ambiente': metadata['environment']?.toString() ?? 'Pátio',
          'Comando larga': cmdLarga,
        }),
        const SizedBox(height: 16),

        // Observações
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('OBSERVAÇÕES'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImpulseRow(
    String name,
    String emoji,
    String stateText,
    Color stateColor,
    bool isActive,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? stateColor.withAlpha(15) : Colors.white.withAlpha(5),
        border: Border.all(
          color: isActive
              ? stateColor.withAlpha(50)
              : Colors.white.withAlpha(12),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: stateColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  stateText,
                  style: GoogleFonts.inter(
                    color: stateColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: stateColor.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'TRABALHADO HOJE',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRatingRow(String title, int value) {
    final isControl =
        title.toLowerCase().contains('larga') ||
        title.toLowerCase().contains('controle');
    final activeColor = isControl ? _amber : _green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(color: _textSecondary, fontSize: 12),
          ),
          Row(
            children: List.generate(5, (idx) {
              final active = idx < value;
              return Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? activeColor : Colors.white10,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BODY 4: BUSCA & CAPTURA
// =============================================================================

class HistoryBuscaCapturaBody extends StatelessWidget {
  final RecordDetail detail;

  const HistoryBuscaCapturaBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final session = detail.source.originalModel as TrainingSessionModel?;
    final metadata = session?.metadata ?? const {};

    final distance =
        metadata['distance']?.toString() ??
        detail.source.details['Distancia'] ??
        '340m';
    final age =
        metadata['trailAge']?.toString() ??
        detail.source.details['Idade da Trilha'] ??
        '30 min';
    final searchDuration =
        metadata['searchDuration']?.toString() ?? detail.duration;

    final odor = metadata['odor']?.toString() ?? 'Camiseta';
    final figurante = metadata['figurante']?.toString() ?? 'Souza';
    final env = metadata['environment']?.toString() ?? 'Urbano';

    final skills =
        metadata['skills'] as Map? ??
        {
          'Rastreamento': 'FIRME',
          'Indicação passiva': 'OK',
          'Contenção': 'PARCIAL',
          'Indicação em altura': 'NÃO TREINADO',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GPS Track (se presente)
        if (metadata['gps_track'] is Map)
          GpsTrackDetailWidget(
            gpsTrack: Map<String, dynamic>.from(metadata['gps_track'] as Map),
          ),

        const _SectionLabel('RASTRO PERCORRIDO'),
        const SizedBox(height: 8),
        Container(
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withAlpha(20)),
            color: const Color(0xFF0A161B),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MapGridPainter())),
              Positioned.fill(child: CustomPaint(painter: _TrailLinePainter())),
              Positioned(left: 45, top: 85, child: _StartDot()),
              Positioned(right: 70, top: 25, child: _EndPin()),
              Positioned(
                left: 12,
                bottom: 8,
                child: Text(
                  'início → localização do figurante',
                  style: GoogleFonts.ibmPlexMono(
                    color: _textMuted,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Metrics
        Row(
          children: [
            _metricItem(distance, 'DISTÂNCIA'),
            const SizedBox(width: 8),
            _metricItem(age, 'IDADE DO RASTRO'),
            const SizedBox(width: 8),
            _metricItem(searchDuration, 'TEMPO DE BUSCA'),
          ],
        ),
        const SizedBox(height: 16),

        // Habilidades
        const _SectionLabel('HABILIDADES TRABALHADAS'),
        const SizedBox(height: 8),
        for (final skill in skills.entries) ...[
          _buildSkillRow(skill.key.toString(), skill.value.toString()),
        ],
        const SizedBox(height: 16),

        // Configuração
        const _SectionLabel('CONFIGURAÇÃO'),
        const SizedBox(height: 8),
        _buildConfigGrid({
          'Objeto de odor': odor,
          'Figurante': figurante,
          'Ambiente': env,
        }),
        const SizedBox(height: 16),

        // Observações
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('OBSERVAÇÕES'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricItem(String number, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: Colors.white.withAlpha(15)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              number,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color: _textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillRow(String name, String state) {
    Color color = _cyan;
    IconData icon = Icons.check_circle_outline_rounded;

    if (name.toLowerCase().contains('rastre')) {
      icon = Icons.gesture_rounded;
    } else if (name.toLowerCase().contains('indic') &&
        name.toLowerCase().contains('passiv')) {
      icon = Icons.radio_button_checked_rounded;
    } else if (name.toLowerCase().contains('cont')) {
      icon = Icons.front_hand_outlined;
    } else if (name.toLowerCase().contains('altura')) {
      icon = Icons.height_rounded;
    }

    final isDone = state == 'OK' || state == 'FIRME';
    final isDev = state == 'PARCIAL';
    final isNo = state.contains('NÃO');

    if (isDone) color = _green;
    if (isDev) color = _amber;
    if (isNo) color = _textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDone
            ? _green.withAlpha(10)
            : (isDev ? _amber.withAlpha(10) : Colors.white.withAlpha(8)),
        border: Border.all(
          color: isDone
              ? _green.withAlpha(56)
              : (isDev ? _amber.withAlpha(56) : Colors.white.withAlpha(18)),
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withAlpha(27),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Icon(icon, color: color, size: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            state,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _cyan.withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width * 0.14, size.height * 0.70);
    path.cubicTo(
      size.width * 0.35,
      size.height * 0.65,
      size.width * 0.40,
      size.height * 0.40,
      size.width * 0.50,
      size.height * 0.46,
    );
    path.cubicTo(
      size.width * 0.60,
      size.height * 0.52,
      size.width * 0.72,
      size.height * 0.33,
      size.width * 0.80,
      size.height * 0.24,
    );

    final dashedPath = Path();
    const dashWidth = 6.0;
    const dashSpace = 4.0;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = dashWidth;
        dashedPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += length + dashSpace;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// BODY 5: OBEDIÊNCIA
// =============================================================================

class HistoryObedienciaBody extends StatelessWidget {
  final RecordDetail detail;

  const HistoryObedienciaBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final session = detail.source.originalModel as TrainingSessionModel?;
    final metadata = session?.metadata ?? const {};

    final list =
        metadata['commands'] as List? ??
        [
          'Junto',
          'Senta',
          'Fica',
          'Deita',
          'Vem (chamada)',
          'Latir sob comando',
        ];
    final commands = list.map((e) => e.toString()).toList();

    final operacionais = commands.where((name) {
      final l = name.toLowerCase();
      return l.contains('junto') || l.contains('senta') || l.contains('fica');
    }).toList();

    final posicionais = commands.where((name) {
      final l = name.toLowerCase();
      return l.contains('deita') || l.contains('vem') || l.contains('latir');
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GPS Track (se presente)
        if (metadata['gps_track'] is Map)
          GpsTrackDetailWidget(
            gpsTrack: Map<String, dynamic>.from(metadata['gps_track'] as Map),
          ),

        const _SectionLabel('MODO DA SESSÃO'),
        const SizedBox(height: 8),
        _buildConfigGrid({
          'Guia': metadata['guia']?.toString() ?? 'Sem guia',
          'Distração': metadata['distracao']?.toString() ?? 'Alta',
          'Distância': metadata['distancia']?.toString() ?? '15 m',
        }),
        const SizedBox(height: 16),

        const _SectionLabel('COMANDOS · ESTÁGIO'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            _legendItem('● 1 Iniciante', _textMuted),
            _legendItem('● 3 Praticando', _amber),
            _legendItem('● 4 Consolidando', _cyan),
            _legendItem('● 5 Operacional', _green),
          ],
        ),
        const SizedBox(height: 12),

        if (operacionais.isNotEmpty) ...[
          _categoryLabel('OPERACIONAIS'),
          for (final cmd in operacionais) _buildCmdRow(cmd),
        ],
        if (posicionais.isNotEmpty) ...[
          _categoryLabel('POSICIONAIS'),
          for (final cmd in posicionais) _buildCmdRow(cmd),
        ],
        const SizedBox(height: 16),

        // Observações
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('OBSERVAÇÕES'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _legendItem(String text, Color color) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _categoryLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 9),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: const Color(0xFF7D8D99),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCmdRow(String name) {
    final nameLower = name.toLowerCase();
    int level = 3;
    bool hasEvolved = false;

    if (nameLower.contains('junto') || nameLower.contains('senta')) {
      level = 5;
    } else if (nameLower.contains('fica') || nameLower.contains('deita')) {
      level = 4;
      if (nameLower.contains('fica')) hasEvolved = true;
    } else if (nameLower.contains('vem') || nameLower.contains('latir')) {
      level = 3;
      if (nameLower.contains('latir')) hasEvolved = true;
    }

    Color color = _cyan;
    String label = 'CONSOLIDANDO';

    if (level == 5) {
      color = _green;
      label = 'OPERACIONAL';
    } else if (level == 4) {
      color = _cyan;
      label = 'CONSOLIDANDO';
    } else if (level == 3) {
      color = _amber;
      label = 'PRATICANDO';
    } else {
      color = _textMuted;
      label = 'INICIANTE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        border: Border.all(color: Colors.white.withAlpha(12)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              children: [
                TextSpan(text: name),
                if (hasEvolved)
                  const TextSpan(
                    text: ' ↑',
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: List.generate(5, (idx) {
              final active = idx < level;
              return Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? color : Colors.white10,
                ),
              );
            }),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BODY 6: SAÚDE
// =============================================================================

class HistorySaudeBody extends StatelessWidget {
  final RecordDetail detail;

  const HistorySaudeBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final original = detail.source.originalModel;
    HealthLogModel? log;
    if (original is HealthLogModel) {
      log = original;
    }

    final type = log?.logType ?? detail.source.details['Tipo'] ?? 'Exame';
    final lot =
        detail.source.details['Lote'] ??
        detail.source.details['lote'] ??
        'LOTE: 22/045/Z';
    final expiration =
        detail.source.details['Validade'] ??
        detail.source.details['validade'] ??
        'VAL: 10/2026';
    final nextBooster = log?.nextDueDate != null
        ? _fmtDate(log!.nextDueDate!)
        : '—';
    final vetName = log?.vetName ?? detail.author;
    final crmv = log?.professionalCrmv ?? 'CRMV 4421';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('DETALHES DE SAÚDE'),
        const SizedBox(height: 8),
        _buildConfigGrid({
          'Tipo de Evento': type,
          'Lote / Fabricante': lot,
          'Validade': expiration,
        }),
        const SizedBox(height: 16),

        // Reforço/Agenda card
        if (log?.nextDueDate != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _amber.withAlpha(15),
              border: Border.all(color: _amber.withAlpha(50)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  color: _amber,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reforço / Próxima dose agenda',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Agendado para $nextBooster',
                        style: GoogleFonts.inter(
                          color: _textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Veterinário responsável
        const _SectionLabel('RESPONSÁVEL TÉCNICO'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(12)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.assignment_ind_outlined, color: _cyan, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vetName,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      crmv,
                      style: GoogleFonts.inter(color: _textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Documentos anexos
        const _SectionLabel('DOCUMENTOS ANEXOS'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(12)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: _red, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'comprovante_evento.pdf',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'PDF · 245 KB',
                      style: GoogleFonts.inter(color: _textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.download_rounded, color: _cyan, size: 18),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Observações
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('OBSERVAÇÕES MÉDICAS'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// BODY 7: NUTRIÇÃO
// =============================================================================

class HistoryNutricaoBody extends StatelessWidget {
  final RecordDetail detail;

  const HistoryNutricaoBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final original = detail.source.originalModel;
    Feeding? feeding;
    if (original is Feeding) {
      feeding = original;
    }

    final served = feeding?.amountGrams ?? 350;
    final prescribed = feeding?.prescriptionAtTime ?? 350;
    final conforms = feeding?.isConform ?? true;
    final divergenceVal = (served - prescribed).abs();
    final divergenceText =
        '${divergenceVal}g (${conforms ? 'Sem divergência' : 'Divergência'})';
    final racaoName =
        detail.source.details['Ração'] ?? 'Ração Premium K9 Adulto';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('REFEIÇÃO SERVIDA'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(15)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SERVIDO',
                        style: GoogleFonts.inter(
                          color: _textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${served}g',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'PRESCRITO',
                        style: GoogleFonts.inter(
                          color: _textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${prescribed}g',
                        style: GoogleFonts.inter(
                          color: _textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.white.withAlpha(10)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ração Utilizada',
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    racaoName,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Conformidade',
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: conforms
                          ? _green.withAlpha(20)
                          : _amber.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: conforms ? _green : _amber),
                    ),
                    child: Text(
                      conforms
                          ? 'EM CONFORMIDADE'
                          : 'DIVERGENTE ($divergenceText)',
                      style: GoogleFonts.inter(
                        color: conforms ? _green : _amber,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Vínculo ao Laudo Nutricional Vigente
        const _SectionLabel('VÍNCULO CLÍNICO'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(12)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.assignment_turned_in_outlined,
                color: _cyan,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Laudo Nutricional Vigente',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Prescrição Dra. Patrícia Lima · CRMV 8812 · Ativo',
                      style: GoogleFonts.inter(
                        color: _textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Foto do pote/registro
        const _SectionLabel('FOTO DE VERIFICAÇÃO'),
        const SizedBox(height: 8),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(15)),
            color: const Color(0xFF0A161B),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.restaurant_rounded,
                  color: _textMuted,
                  size: 24,
                ),
                const SizedBox(height: 6),
                Text(
                  'Foto da refeição registrada',
                  style: GoogleFonts.inter(color: _textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Acompanhamento do dia
        if (detail.notes.isNotEmpty) ...[
          const _SectionLabel('ACOMPANHAMENTO DO DIA'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.notes,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// REUSABLE HELPER BLOCKS & WIDGETS
// =============================================================================

Widget _buildConfigGrid(Map<String, String> values) {
  return GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 1.8,
    children: values.entries.map((e) {
      final isWarning =
          e.value.toLowerCase().contains('parcial') ||
          e.value.toLowerCase().contains('alta');
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(5),
          border: Border.all(color: Colors.white.withAlpha(12)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              e.key.toUpperCase(),
              style: GoogleFonts.inter(
                color: _textMuted,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              e.value,
              style: GoogleFonts.inter(
                color: isWarning ? _amber : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }).toList(),
  );
}

// =============================================================================
// HELPER CLASSES & METHODS IMPLEMENTATIONS
// =============================================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          color: _textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _cyan, size: 20),
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}

class _CtaBar extends StatelessWidget {
  final VoidCallback onPdfTap;
  final VoidCallback onShareTap;

  const _CtaBar({required this.onPdfTap, required this.onShareTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_bg, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onPdfTap,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Gerar PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cyan,
                foregroundColor: _bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onShareTap,
              icon: const Icon(Icons.share_outlined, size: 16),
              label: const Text('Compartilhar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _cyan,
                side: const BorderSide(color: _cyan, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OccurrenceDisplacementSection extends StatefulWidget {
  final String occurrenceId;

  const _OccurrenceDisplacementSection({required this.occurrenceId});

  @override
  State<_OccurrenceDisplacementSection> createState() =>
      _OccurrenceDisplacementSectionState();
}

class _OccurrenceDisplacementSectionState
    extends State<_OccurrenceDisplacementSection> {
  late Future<List<OccurrenceLocation>> _locationsFuture;

  @override
  void initState() {
    super.initState();
    _locationsFuture = _loadLocations();
  }

  Future<List<OccurrenceLocation>> _loadLocations() async {
    if (widget.occurrenceId.isEmpty) return [];
    final events = await context
        .read<OccurrenceViewModel>()
        .getEvents(widget.occurrenceId);
    return OccurrenceLocationService.clusterEvents(events);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OccurrenceLocation>>(
      future: _locationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: _cyan,
              ),
            ),
          );
        }
        final locations = snapshot.data ?? [];
        if (locations.isEmpty) return const SizedBox.shrink();
        return OccurrenceDisplacementMap(locations: locations);
      },
    );
  }
}

class _OccurrenceTimelineSection extends StatefulWidget {
  final String occurrenceId;
  final RecordDetail fallback;

  const _OccurrenceTimelineSection({
    required this.occurrenceId,
    required this.fallback,
  });

  @override
  State<_OccurrenceTimelineSection> createState() =>
      _OccurrenceTimelineSectionState();
}

class _OccurrenceTimelineSectionState
    extends State<_OccurrenceTimelineSection> {
  late Future<List<OccurrenceEvent>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEvents();
  }

  @override
  void didUpdateWidget(covariant _OccurrenceTimelineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.occurrenceId != widget.occurrenceId) {
      setState(() {
        _eventsFuture = _loadEvents();
      });
    }
  }

  Future<List<OccurrenceEvent>> _loadEvents() {
    if (widget.occurrenceId.isEmpty) {
      return Future.value(<OccurrenceEvent>[]);
    }
    return context.read<OccurrenceViewModel>().getEvents(widget.occurrenceId);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.occurrenceId.isEmpty) {
      return _buildTimelineList(
        widget.fallback.internalEvents
            .map(
              (e) => OccurrenceEvent(
                id: '',
                occurrenceId: '',
                category: OccurrenceEventCategory.other,
                timestamp: e.time,
                title: e.title,
                description: e.subtitle,
                createdAt: e.time,
                updatedAt: e.time,
              ),
            )
            .toList(),
      );
    }

    return FutureBuilder<List<OccurrenceEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _cyan));
        }

        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return _buildTimelineList(
            widget.fallback.internalEvents
                .map(
                  (e) => OccurrenceEvent(
                    id: '',
                    occurrenceId: '',
                    category: OccurrenceEventCategory.other,
                    timestamp: e.time,
                    title: e.title,
                    description: e.subtitle,
                    createdAt: e.time,
                    updatedAt: e.time,
                  ),
                )
                .toList(),
          );
        }

        events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return _buildTimelineList(events);
      },
    );
  }

  Widget _buildTimelineList(List<OccurrenceEvent> events) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('LINHA DO TEMPO'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 6),
          child: Column(
            children: List.generate(events.length, (idx) {
              final ev = events[idx];
              final isLast = idx == events.length - 1;

              Color nodeColor = _cyan;
              final titleLower = (ev.title ?? '').toLowerCase();
              final descLower = (ev.description ?? '').toLowerCase();

              if (titleLower.contains('busca') ||
                  titleLower.contains('varredura') ||
                  titleLower.contains('inici')) {
                nodeColor = _amber;
              } else if (titleLower.contains('apreend') ||
                  titleLower.contains('detido') ||
                  titleLower.contains('finaliz') ||
                  titleLower.contains('conclu') ||
                  descLower.contains('apreend')) {
                nodeColor = _green;
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.only(right: 10, top: 1),
                      alignment: Alignment.topRight,
                      child: Text(
                        DateFormat('HH:mm').format(ev.timestamp),
                        style: GoogleFonts.ibmPlexMono(
                          color: _textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: nodeColor,
                            border: Border.all(color: _bg, width: 2),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.white.withAlpha(20),
                            ),
                          ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ev.title ?? 'Evento',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (ev.description != null &&
                                ev.description!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                ev.description!,
                                style: GoogleFonts.inter(
                                  color: _textSecondary,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),

      ],
    );
  }
}

String _fmtDate(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

String _fmtTime(DateTime date) {
  return DateFormat('HH:mm').format(date);
}

class _StartDot extends StatelessWidget {
  const _StartDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1C40F), // Amber
        border: Border.all(color: const Color(0xFF050D10), width: 2),
      ),
    );
  }
}

class _EndPin extends StatelessWidget {
  const _EndPin();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.785398, // -45 degrees in radians
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF2ECC71), // Green
          border: Border.all(color: const Color(0xFF050D10), width: 2),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(7),
            topRight: Radius.circular(7),
            bottomLeft: Radius.circular(7),
            bottomRight: Radius.zero,
          ),
        ),
      ),
    );
  }
}

// ─── Seção de Retificações ──────────────────────────────────────────────────

class _AmendmentsSection extends StatefulWidget {
  final Occurrence occurrence;

  const _AmendmentsSection({required this.occurrence});

  @override
  State<_AmendmentsSection> createState() => _AmendmentsSectionState();
}

class _AmendmentsSectionState extends State<_AmendmentsSection> {
  final _repository = AmendmentRepository();
  List<Amendment>? _amendments;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAmendments();
  }

  Future<void> _loadAmendments() async {
    final amendments =
        await _repository.listByOccurrence(widget.occurrence.id);
    if (mounted) {
      setState(() {
        _amendments = amendments;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_amendments == null || _amendments!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_edu, color: _amber, size: 14),
              const SizedBox(width: 8),
              Text(
                'RETIFICAÇÕES (${_amendments!.length})',
                style: GoogleFonts.inter(
                  color: _amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._amendments!.map((a) => _AmendmentCard(amendment: a)),
        ],
      ),
    );
  }
}

class _AmendmentCard extends StatelessWidget {
  final Amendment amendment;

  const _AmendmentCard({required this.amendment});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${amendment.createdAt.day.toString().padLeft(2, '0')}/'
        '${amendment.createdAt.month.toString().padLeft(2, '0')}/'
        '${amendment.createdAt.year} '
        '${amendment.createdAt.hour.toString().padLeft(2, '0')}:'
        '${amendment.createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amber.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _amber.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${amendment.sequenceNumber}',
                  style: GoogleFonts.inter(
                    color: _amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dateStr,
                  style: GoogleFonts.inter(
                    color: Colors.white.withAlpha(120),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${amendment.createdByName} (RA: ${amendment.createdByRa})',
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(160),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            amendment.reason,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          ...amendment.corrections.entries.map((entry) {
            final fieldLabel = _fieldLabel(entry.key);
            final correction = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fieldLabel.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: _amber.withAlpha(180),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.remove_circle_outline,
                            color: Colors.redAccent.withAlpha(150), size: 12),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${correction.oldValue ?? '(vazio)'}',
                            style: GoogleFonts.inter(
                              color: Colors.white.withAlpha(100),
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: const Color(0xFF4CAF50).withAlpha(180),
                            size: 12),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${correction.newValue}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (correction.description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        correction.description!,
                        style: GoogleFonts.inter(
                          color: Colors.white.withAlpha(80),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            'Hash: ${amendment.integrityHash.substring(0, 16)}...',
            style: TextStyle(
              color: _amber.withAlpha(100),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _fieldLabel(String key) {
    const labels = {
      'type_name': 'Natureza',
      'location_address': 'Endereço',
      'dog_name': 'Cão',
      'handler_name': 'Condutor',
      'final_report': 'Relatório final',
      'initial_observation': 'Observação inicial',
    };
    return labels[key] ?? key;
  }
}
