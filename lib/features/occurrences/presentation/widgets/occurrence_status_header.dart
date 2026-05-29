import 'package:flutter/material.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceStatusHeader extends StatelessWidget {
  final OccurrenceStatus status;
  final DateTime? signatureRequestAt;
  final DateTime? signatureDeadline;
  final int teamSize;
  final int signedCount;
  final bool showDeadlineWarning;

  const OccurrenceStatusHeader({
    super.key,
    required this.status,
    this.signatureRequestAt,
    this.signatureDeadline,
    this.teamSize = 1,
    this.signedCount = 0,
    this.showDeadlineWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status principal
        _buildStatusChip(context),

        // Informações adicionais para awaiting_signatures
        if (status == OccurrenceStatus.awaitingSignatures) ...[
          const SizedBox(height: 8),
          _buildSignatureInfo(context),
        ],

        // Prazo vencendo
        if (showDeadlineWarning && status == OccurrenceStatus.awaitingSignatures)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prazo de assinatura vencendo em ${_formatDeadline()}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    Color? bgColor;
    String text;
    IconData icon;

    switch (status) {
      case OccurrenceStatus.inProgress:
        bgColor = Theme.of(context).colorScheme.primaryContainer;
        text = 'Em Andamento';
        icon = Icons.edit;
        break;
      case OccurrenceStatus.finalizing:
        bgColor = Theme.of(context).colorScheme.secondaryContainer;
        text = 'Finalizando';
        icon = Icons.pending_actions;
        break;
      case OccurrenceStatus.awaitingSignatures:
        bgColor = Theme.of(context).colorScheme.tertiaryContainer;
        text = 'Aguardando Assinaturas';
        icon = Icons.request_quote;
        break;
      case OccurrenceStatus.finalized:
        bgColor = Theme.of(context).colorScheme.primaryContainer;
        text = 'Finalizada';
        icon = Icons.verified;
        break;
      case OccurrenceStatus.finalizedWithPending:
        bgColor = Theme.of(context).colorScheme.errorContainer;
        text = 'Finalizada com Pendências';
        icon = Icons.warning;
        break;
      case OccurrenceStatus.canceled:
        bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        text = 'Cancelada';
        icon = Icons.cancel;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureInfo(BuildContext context) {
    final remaining = teamSize - 1 - signedCount;

    return Row(
      children: [
        Icon(
          Icons.group,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '$signedCount assinatura(s) de ${teamSize - 1} integrante(s)',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (remaining > 0) ...[
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$remaining pendente(s)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDeadline() {
    if (signatureDeadline == null) return '';

    final now = DateTime.now();
    final deadline = signatureDeadline!;
    final difference = deadline.difference(now);

    if (difference.inDays > 0) {
      return 'em ${difference.inDays} dia(s)';
    } else if (difference.inHours > 0) {
      return 'em ${difference.inHours} hora(s)';
    } else if (difference.inMinutes > 0) {
      return 'em ${difference.inMinutes} minuto(s)';
    } else {
      return 'já venceu';
    }
  }
}
