import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/training/data/training_promotion_service.dart';
import 'package:canil_gcm/features/training/domain/training_promotion_request.dart';

class TrainingPromotionRequestScreen extends StatefulWidget {
  final String requestId;

  const TrainingPromotionRequestScreen({super.key, required this.requestId});

  @override
  State<TrainingPromotionRequestScreen> createState() =>
      _TrainingPromotionRequestScreenState();
}

class _TrainingPromotionRequestScreenState
    extends State<TrainingPromotionRequestScreen> {
  final TrainingPromotionService _service = TrainingPromotionService();
  bool _checkingRole = true;
  bool _isInstructor = false;
  bool _deciding = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final result = await _service.currentUserIsInstructorK9(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _isInstructor = result;
      _checkingRole = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Validacao de evolucao'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: StreamBuilder<TrainingPromotionRequest?>(
        stream: _service.watchRequest(widget.requestId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final request = snapshot.data;
          if (request == null) {
            return _empty('Solicitacao nao encontrada.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _header(request),
              const SizedBox(height: 14),
              _statusCard(request),
              const SizedBox(height: 14),
              _marksCard(request),
              const SizedBox(height: 18),
              if (_checkingRole)
                const Center(child: CircularProgressIndicator())
              else if (request.isPending && _isInstructor)
                _decisionActions(request)
              else if (request.isPending)
                _notice(
                  'Aguardando Instrutor K9',
                  'Esta solicitacao so pode ser decidida por usuario com claim Instrutor K9.',
                  AppTheme.warning,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Text(
        message,
        style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _header(TrainingPromotionRequest request) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(AppTheme.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROMOCAO DE MODULO',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${request.dogName} - ${request.moduleName}',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Solicitado por ${request.requesterName.isEmpty ? request.requesterRa : request.requesterName}',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(TrainingPromotionRequest request) {
    final color = request.isApproved
        ? AppTheme.success
        : request.isRejected
        ? AppTheme.error
        : AppTheme.warning;
    final label = request.isApproved
        ? 'Aprovada'
        : request.isRejected
        ? 'Reprovada'
        : 'Pendente';
    return _notice(
      label,
      request.isRejected && request.decisionReason != null
          ? request.decisionReason!
          : request.isApproved
          ? 'A progressao sera aplicada pela Cloud Function.'
          : 'Primeiro Instrutor K9 a decidir resolve a solicitacao.',
      color,
    );
  }

  Widget _marksCard(TrainingPromotionRequest request) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(AppTheme.textMuted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SNAPSHOT DOS MARCOS',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          ...request.marksSnapshot.map(_markRow),
        ],
      ),
    );
  }

  Widget _markRow(Map<String, dynamic> mark) {
    final achieved = mark['achieved'] == true;
    final required = mark['required'] != false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: achieved
            ? AppTheme.success.withAlpha(18)
            : AppTheme.textPrimary.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: achieved
              ? AppTheme.success.withAlpha(70)
              : AppTheme.textPrimary.withAlpha(22),
        ),
      ),
      child: Row(
        children: [
          Icon(
            achieved
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            color: achieved ? AppTheme.success : AppTheme.textMuted,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${mark['label'] ?? mark['milestone_id']}'
              '${required ? ' - obrigatorio' : ' - opcional'}',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decisionActions(TrainingPromotionRequest request) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _deciding ? null : () => _reject(request),
            icon: const Icon(Icons.close_rounded),
            label: const Text('APONTAR FALTA'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _deciding ? null : () => _approve(request),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('APROVAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(String title, String body, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(Color color) {
    return BoxDecoration(
      color: AppTheme.surfaceWhiteOverlayWeak,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withAlpha(65)),
    );
  }

  Future<void> _approve(TrainingPromotionRequest request) async {
    await _decide(request, approve: true);
  }

  Future<void> _reject(TrainingPromotionRequest request) async {
    final reason = await _reasonDialog();
    if (reason == null || reason.trim().isEmpty) return;
    await _decide(request, approve: false, reason: reason);
  }

  Future<void> _decide(
    TrainingPromotionRequest request, {
    required bool approve,
    String? reason,
  }) async {
    setState(() => _deciding = true);
    try {
      await _service.decideRequest(
        requestId: request.id,
        approve: approve,
        reason: reason,
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        approve ? 'Aprovação registrada.' : 'Reprovação registrada.',
        type: approve ? AppFeedbackType.success : AppFeedbackType.warning,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        error,
        fallback: 'Não foi possível decidir a solicitação.',
      );
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  Future<String?> _reasonDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('O que faltou?'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Motivo obrigatorio para orientar nova rodada',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
