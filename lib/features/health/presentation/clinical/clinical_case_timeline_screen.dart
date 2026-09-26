import 'package:flutter/material.dart';

import '../../data/clinical/firebase_clinical_event_gateway.dart';
import '../../domain/clinical_event_gateway.dart';
import '../../domain/clinical_event_read_model.dart';
import 'widgets/clinical_event_card.dart';

/// Tela somente-leitura da Timeline de Eventos Clínicos de um Caso (ClinicalCase).
///
/// Restrição de nomenclatura (CLINICAL-DEBT-01):
/// Nomeada como "Eventos Clínicos" e NÃO "Histórico completo do caso", pois operações
/// de ciclo de vida globais do ClinicalCase podem não gerar um ClinicalEvent sintético.
///
/// Escopo:
/// - Loading, Empty, Success, Error / Retry.
/// - Eventos ordenados por ocorrência descrescente.
/// - Apresentação de rascunhos, finalizados e cancelados.
/// - Suporte à expansão de emendas clínicas.
/// - Estritamente somente-leitura (sem ações de mutação, edição ou cancelamento).
class ClinicalCaseTimelineScreen extends StatefulWidget {
  const ClinicalCaseTimelineScreen({
    super.key,
    required this.dogId,
    required this.caseId,
    this.caseTitle,
    this.gateway,
  });

  final String dogId;
  final String caseId;
  final String? caseTitle;
  final ClinicalEventGateway? gateway;

  @override
  State<ClinicalCaseTimelineScreen> createState() =>
      _ClinicalCaseTimelineScreenState();
}

class _ClinicalCaseTimelineScreenState
    extends State<ClinicalCaseTimelineScreen> {
  late final ClinicalEventGateway _gateway;
  Stream<List<ClinicalEventReadModel>>? _eventsStream;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseClinicalEventGateway();
    _subscribe();
  }

  void _subscribe() {
    setState(() {
      _eventsStream = _gateway.watchCaseEvents(
        dogId: widget.dogId,
        caseId: widget.caseId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Eventos Clínicos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.caseTitle != null
                  ? '${widget.caseTitle} (${widget.caseId})'
                  : 'Caso: ${widget.caseId} • K9: ${widget.dogId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<ClinicalEventReadModel>>(
        stream: _eventsStream,
        builder: (context, snapshot) {
          // Loading State
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Carregando eventos clínicos...'),
                ],
              ),
            );
          }

          // Error State
          if (snapshot.hasError) {
            final error = snapshot.error;
            final message = error is ClinicalEventReadException
                ? error.message
                : 'Não foi possível carregar os eventos clínicos.';

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Falha ao carregar linha do tempo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _subscribe,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }

          final events = snapshot.data ?? const <ClinicalEventReadModel>[];

          // Empty State
          if (events.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _subscribe(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_note_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhum evento clínico registrado',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Este caso clínico ainda não possui eventos registrados na linha do tempo.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Success State with Events List
          return RefreshIndicator(
            onRefresh: () async => _subscribe(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return ClinicalEventCard(
                  key: ValueKey('event_${event.id}'),
                  event: event,
                  gateway: _gateway,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
