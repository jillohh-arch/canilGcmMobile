import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/clinical_event_gateway.dart';
import '../../../domain/clinical_event_read_model.dart';
import '../../../domain/health_v1_enums.dart';
import 'clinical_amendment_tile.dart';

/// Card de exibição de um Evento Clínico canônico (ClinicalEvent).
///
/// Apresenta o status (draft, final, cancelled), tipo do evento em pt-BR,
/// instante de ocorrência, autoria interna e profissional, conteúdo clínico
/// estruturado, sinalizadores de anexos e suporte à expansão de emendas.
class ClinicalEventCard extends StatefulWidget {
  const ClinicalEventCard({super.key, required this.event, this.gateway});

  final ClinicalEventReadModel event;
  final ClinicalEventGateway? gateway;

  @override
  State<ClinicalEventCard> createState() => _ClinicalEventCardState();
}

class _ClinicalEventCardState extends State<ClinicalEventCard> {
  bool _isExpanded = false;
  bool _isLoadingAmendments = false;
  List<ClinicalAmendmentReadModel>? _amendments;
  String? _amendmentError;

  ClinicalEventReadModel get event => widget.event;

  Future<void> _toggleAmendments() async {
    if (_isExpanded) {
      setState(() => _isExpanded = false);
      return;
    }

    setState(() {
      _isExpanded = true;
    });

    if (_amendments != null || widget.gateway == null) {
      return;
    }

    setState(() {
      _isLoadingAmendments = true;
      _amendmentError = null;
    });

    try {
      final loaded = await widget.gateway!.readEventAmendments(
        dogId: event.dogId,
        caseId: event.caseId,
        eventId: event.id,
      );
      if (mounted) {
        setState(() {
          _amendments = loaded;
          _isLoadingAmendments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _amendmentError = 'Falha ao carregar emendas: $e';
          _isLoadingAmendments = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final occurredAtDisplay = event.occurredAt != null
        ? dateFormat.format(event.occurredAt!.toLocal())
        : 'Data não informada';

    final recordedAtDisplay = event.recordedAt != null
        ? dateFormat.format(event.recordedAt!.toLocal())
        : null;

    final typeLabel = _eventTypeLabel(event.type);
    final (statusLabel, statusBg, statusFg, statusBorder) = _statusStyle(
      event.status,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: event.hasQualityIssues
              ? Colors.amber.shade300
              : Colors.grey.shade200,
          width: event.hasQualityIssues ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Status Chip + Type + OccurredAt
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusBorder),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusFg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: event.isCancelled
                              ? Colors.grey.shade700
                              : null,
                          decoration: event.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 13,
                            color: event.occurredAt != null
                                ? Colors.grey.shade600
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            occurredAtDisplay,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: event.occurredAt != null
                                  ? Colors.grey.shade600
                                  : Colors.amber.shade900,
                              fontWeight: event.occurredAt == null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Content Summary
            _buildContentSummary(context),

            // Cancellation Notice (if cancelled)
            if (event.isCancelled) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          size: 16,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Cancelado: ${event.cancelReason ?? "Sem motivo informado"}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (event.cancelledAt != null ||
                        event.cancelledBy != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Por ${event.cancelledBy?.name ?? "Usuário"} em ${event.cancelledAt != null ? dateFormat.format(event.cancelledAt!.toLocal()) : "-"}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Footer: Authorship + Professional + Attachments
            Row(
              children: [
                if (event.recordedBy != null) ...[
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${event.recordedBy!.name} (${event.recordedBy!.internalRole})${recordedAtDisplay != null ? " • Reg: $recordedAtDisplay" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (event.attachmentRefs != null &&
                    event.attachmentRefs!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.attach_file,
                    size: 14,
                    color: Colors.blueGrey.shade600,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${event.attachmentRefs!.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),

            if (event.professional != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.medical_services_outlined,
                    size: 14,
                    color: Colors.teal.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${event.professional!.name ?? "Profissional"}'
                      '${event.professional!.formattedRegistration != null ? " (${event.professional!.formattedRegistration})" : ""}'
                      '${event.professional!.clinic != null && event.professional!.clinic!.isNotEmpty ? " • ${event.professional!.clinic}" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Data Quality Warning Banner
            if (event.hasQualityIssues) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.amber.shade900,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Qualidade: ${event.dataQualityIssues.join(", ")}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Amendments Section
            if (event.knownHasAmendments == true ||
                (event.amendmentCount ?? 0) > 0) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: _toggleAmendments,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_edu_outlined,
                        size: 16,
                        color: Colors.blue.shade800,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        event.amendmentCount != null &&
                                event.amendmentCount! > 1
                            ? '${event.amendmentCount} emendas registradas'
                            : 'Emenda registrada',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: Colors.blue.shade800,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 8),
                if (_isLoadingAmendments)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_amendmentError != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _amendmentError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red,
                      ),
                    ),
                  )
                else if (_amendments != null && _amendments!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _amendments!
                        .map((amend) => ClinicalAmendmentTile(amendment: amend))
                        .toList(),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Nenhum detalhe de emenda disponível',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContentSummary(BuildContext context) {
    final theme = Theme.of(context);
    final c = event.content;
    if (c.isEmpty) {
      return Text(
        'Sem conteúdo registrado',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final reason =
        c['reason']?.toString() ?? c['if_request_reason']?.toString();
    final diagnosis = c['diagnosis']?.toString();
    final findings = c['findings']?.toString();
    final title = c['title']?.toString();
    final notes = c['notes']?.toString() ?? c['general_notes']?.toString();

    final lines = <Widget>[];

    if (title != null && title.isNotEmpty) {
      lines.add(
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    if (diagnosis != null && diagnosis.isNotEmpty) {
      lines.add(
        Text(
          'Diagnóstico: $diagnosis',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (reason != null && reason.isNotEmpty) {
      lines.add(Text('Motivo: $reason', style: theme.textTheme.bodyMedium));
    }
    if (findings != null && findings.isNotEmpty) {
      lines.add(
        Text(
          'Achados: $findings',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade800,
          ),
        ),
      );
    }
    if (notes != null && notes.isNotEmpty) {
      lines.add(
        Text(
          notes,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade800,
          ),
        ),
      );
    }

    if (lines.isEmpty) {
      // Fallback para conteúdo genérico estruturado
      final entries = c.entries
          .take(4)
          .map((e) => '${e.key}: ${e.value}')
          .join(' • ');
      lines.add(
        Text(
          entries,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  static String _eventTypeLabel(ParsedHealthEnum<ClinicalEventType> type) {
    if (!type.isKnown || type.value == null) {
      return type.raw ?? 'Evento Clínico';
    }
    return switch (type.value!) {
      ClinicalEventType.consultation => 'Consulta Veterinária',
      ClinicalEventType.incident => 'Incidente Clínico',
      ClinicalEventType.vaccination => 'Vacinação',
      ClinicalEventType.examRequest => 'Solicitação de Exame',
      ClinicalEventType.examCollection => 'Coleta de Exame',
      ClinicalEventType.examResult => 'Resultado de Exame',
      ClinicalEventType.examInterpretation => 'Laudo de Exame',
      ClinicalEventType.treatmentStart => 'Início de Tratamento',
      ClinicalEventType.treatmentNote => 'Evolução de Tratamento',
      ClinicalEventType.doseNote => 'Aplicação de Dose',
      ClinicalEventType.reevaluation => 'Reavaliação Clínica',
      ClinicalEventType.discharge => 'Alta Clínica',
      ClinicalEventType.reopen => 'Reabertura de Caso',
      ClinicalEventType.restrictionIssued => 'Emissão de Restrição',
      ClinicalEventType.restrictionEnded => 'Encerramento de Restrição',
      ClinicalEventType.surgicalNote => 'Nota Cirúrgica',
      ClinicalEventType.generalNote => 'Nota Geral',
      ClinicalEventType.observation => 'Observação Clínica',
    };
  }

  static (String, Color, Color, Color) _statusStyle(
    ParsedHealthEnum<ClinicalEventStatus> status,
  ) {
    if (!status.isKnown || status.value == null) {
      return (
        status.raw ?? 'UNKNOWN',
        Colors.grey.shade100,
        Colors.grey.shade800,
        Colors.grey.shade300,
      );
    }
    return switch (status.value!) {
      ClinicalEventStatus.draft => (
        'RASCUNHO',
        Colors.amber.shade50,
        Colors.amber.shade900,
        Colors.amber.shade300,
      ),
      ClinicalEventStatus.finalised => (
        'FINAL',
        Colors.green.shade50,
        Colors.green.shade900,
        Colors.green.shade300,
      ),
      ClinicalEventStatus.cancelled => (
        'CANCELADO',
        Colors.red.shade50,
        Colors.red.shade900,
        Colors.red.shade300,
      ),
    };
  }
}
