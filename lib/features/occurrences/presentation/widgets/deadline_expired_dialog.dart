import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';

class DeadlineExpiredDialog extends StatefulWidget {
  final OccurrenceFinalizationViewModel viewModel;

  const DeadlineExpiredDialog({super.key, required this.viewModel});

  @override
  State<DeadlineExpiredDialog> createState() => _DeadlineExpiredDialogState();
}

class _DeadlineExpiredDialogState extends State<DeadlineExpiredDialog> {
  bool _isExtendingDeadline = false;
  bool _isFinalizingWithPending = false;
  bool _isRevertingToDraft = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.warning_amber,
              color: Theme.of(context).colorScheme.onErrorContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Prazo de assinatura vencido',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'O prazo para assinar a ocorrência venceu. O titular pode aguardar, selar com pendência ou voltar para edição.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protocolo: ${widget.viewModel.occurrence?.id.substring(0, 8) ?? ''}...',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vencido em: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.viewModel.occurrence?.signatureDeadline ?? DateTime.now())}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Assinaturas: ${widget.viewModel.signatures.where((s) => s.status == SignatureStatus.signed).length} de ${widget.viewModel.team.length - 1} integrantes',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : _revertToDraft,
          child: _isRevertingToDraft
              ? const _SmallProgress()
              : const Text('Voltar para draft'),
        ),
        TextButton(
          onPressed: _isBusy ? null : _extendDeadline,
          child: _isExtendingDeadline
              ? const _SmallProgress()
              : const Text('Aguardar mais 48h'),
        ),
        FilledButton(
          onPressed: _isBusy ? null : _finalizeWithPending,
          child: _isFinalizingWithPending
              ? const _SmallProgress(onPrimary: true)
              : const Text('Finalizar com pendência'),
        ),
      ],
    );
  }

  bool get _isBusy =>
      _isExtendingDeadline || _isFinalizingWithPending || _isRevertingToDraft;

  Future<void> _revertToDraft() async {
    setState(() => _isRevertingToDraft = true);
    await widget.viewModel.revertToDraft(
      onSuccess: (message) {
        if (!mounted) return;
        _showSnack('Ocorrência revertida para draft: $message');
        Navigator.pop(context);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isRevertingToDraft = false);
        _showSnack('Erro: $error', isError: true);
      },
    );
  }

  Future<void> _extendDeadline() async {
    setState(() => _isExtendingDeadline = true);
    await widget.viewModel.extendDeadline(
      extension: const Duration(hours: 48),
      onSuccess: (message) {
        if (!mounted) return;
        _showSnack(message);
        Navigator.pop(context);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isExtendingDeadline = false);
        _showSnack('Erro ao estender prazo: $error', isError: true);
      },
    );
  }

  Future<void> _finalizeWithPending() async {
    setState(() => _isFinalizingWithPending = true);
    await widget.viewModel.finalizeWithPending(
      onSuccess: (message) {
        if (!mounted) return;
        _showSnack(message);
        Navigator.pop(context);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isFinalizingWithPending = false);
        _showSnack('Erro ao finalizar: $error', isError: true);
      },
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppFeedback.error(context, message);
    } else {
      AppFeedback.success(context, message);
    }
  }
}

class _SmallProgress extends StatelessWidget {
  final bool onPrimary;

  const _SmallProgress({this.onPrimary = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: onPrimary ? AppTheme.textPrimary : null,
      ),
    );
  }
}
