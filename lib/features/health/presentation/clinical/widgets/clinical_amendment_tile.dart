import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/clinical_event_read_model.dart';

/// Widget de exibição de uma Emenda Clínica (ClinicalAmendment).
///
/// Apresenta o tipo da emenda (Correção, Adendo, Complemento),
/// o motivo justificado, autoria e instante de gravação.
class ClinicalAmendmentTile extends StatelessWidget {
  const ClinicalAmendmentTile({super.key, required this.amendment});

  final ClinicalAmendmentReadModel amendment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final formattedDate = amendment.recordedAt != null
        ? dateFormat.format(amendment.recordedAt!.toLocal())
        : 'Data não informada';

    final typeLabel = amendment.type.isKnown && amendment.type.value != null
        ? amendment.type.value!.labelPtBr
        : (amendment.type.raw ?? 'Emenda');

    final (badgeBg, badgeFg) = switch (amendment.type.value) {
      ClinicalAmendmentType.correction => (
        Colors.orange.shade50,
        Colors.orange.shade800,
      ),
      ClinicalAmendmentType.addendum => (
        Colors.blue.shade50,
        Colors.blue.shade800,
      ),
      ClinicalAmendmentType.complement => (
        Colors.purple.shade50,
        Colors.purple.shade800,
      ),
      null => (Colors.grey.shade100, Colors.grey.shade800),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Tipo + Ordinal + Data
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeFg.withValues(alpha: 0.3)),
                ),
                child: Text(
                  amendment.ordinal != null
                      ? '#${amendment.ordinal} $typeLabel'
                      : typeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: badgeFg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                formattedDate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Motivo da emenda
          Text(
            amendment.reason,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade900,
            ),
          ),

          // Autor
          if (amendment.recordedBy != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  '${amendment.recordedBy!.name} (${amendment.recordedBy!.internalRole})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],

          // Alerta de qualidade se aplicável
          if (amendment.hasQualityIssues) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Inconsistências: ${amendment.dataQualityIssues.join(", ")}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.amber.shade900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
