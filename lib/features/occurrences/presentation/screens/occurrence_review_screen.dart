import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/signature_confirmation_dialog.dart';

class OccurrenceReviewScreen extends StatefulWidget {
  final String occurrenceId;

  const OccurrenceReviewScreen({super.key, required this.occurrenceId});

  @override
  State<OccurrenceReviewScreen> createState() => _OccurrenceReviewScreenState();
}

class _OccurrenceReviewScreenState extends State<OccurrenceReviewScreen> {
  final _occurrenceRepository = OccurrenceRepository(
    FirebaseFirestore.instance,
  );
  final _eventRepository = OccurrenceEventRepository(
    FirebaseFirestore.instance,
  );
  late final OccurrenceFinalizationViewModel _teamViewModel;

  bool _isLoading = true;
  bool _isRequestingCorrection = false;
  String? _error;
  Occurrence? _occurrence;
  List<OccurrenceEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    _teamViewModel = OccurrenceFinalizationViewModel(
      occurrenceRepository: _occurrenceRepository,
      signatureRepository: SignatureRepository(),
      notificationService: NotificationService(),
    );
    _load();
  }

  @override
  void dispose() {
    _teamViewModel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final occurrence = await _occurrenceRepository.getById(
        widget.occurrenceId,
      );
      final events = await _eventRepository.listByOccurrence(
        widget.occurrenceId,
      );
      await _teamViewModel.initialize(occurrenceId: widget.occurrenceId);

      if (!mounted) return;
      setState(() {
        _occurrence = occurrence;
        _events = events..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canSign {
    final occurrence = _occurrence;
    final currentRa = HandlerIdentityService.raFromUser(
      FirebaseAuth.instance.currentUser,
    );
    if (occurrence == null ||
        currentRa == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }
    final member = occurrence.team.where((item) => item.handlerId == currentRa);
    if (member.isEmpty || member.first.role == TeamRole.titular) return false;
    return _teamViewModel.signatures.any(
      (signature) =>
          signature.handlerId == currentRa &&
          signature.status == SignatureStatus.pending,
    );
  }

  bool get _canRequestCorrection {
    final occurrence = _occurrence;
    final currentRa = HandlerIdentityService.raFromUser(
      FirebaseAuth.instance.currentUser,
    );
    if (occurrence == null ||
        currentRa == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }
    return occurrence.team.any((member) => member.handlerId == currentRa) ||
        occurrence.primaryHandlerRa == currentRa ||
        occurrence.primaryHandlerId == currentRa;
  }

  void _showSignatureDialog() {
    final occurrence = _occurrence;
    if (occurrence == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SignatureConfirmationDialog(
        occurrence: occurrence,
        viewModel: _teamViewModel,
        onSuccess: () async {
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(content: Text('Assinatura registrada.')),
          );
        },
      ),
    );
  }

  void _showCorrectionDialog() {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Devolver para correção'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            hintText: 'Explique o que precisa ser corrigido',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _isRequestingCorrection
                ? null
                : () {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Informe o motivo da devolução.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext);
                    _requestCorrection(reason);
                  },
            child: const Text('Devolver'),
          ),
        ],
      ),
    ).whenComplete(reasonController.dispose);
  }

  Future<void> _requestCorrection(String reason) async {
    setState(() => _isRequestingCorrection = true);
    try {
      await OccurrenceTransitionService().requestCorrection(
        occurrenceId: widget.occurrenceId,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ActiveOccurrenceScreen(occurrenceId: widget.occurrenceId),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ocorrência devolvida para correção.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao devolver para correção: $error'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRequestingCorrection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = _occurrence;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar ocorrência'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : occurrence == null
          ? _ErrorState(message: 'Ocorrência não encontrada.', onRetry: _load)
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    children: [
                      _SectionCard(
                        icon: Icons.shield_outlined,
                        title: occurrence.typeName,
                        children: [
                          _InfoLine(label: 'Protocolo', value: occurrence.id),
                          _InfoLine(
                            label: 'Data',
                            value: DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(occurrence.startedAt),
                          ),
                          if (occurrence.vehicleLabel?.isNotEmpty == true)
                            _InfoLine(
                              label: 'Viatura',
                              value: occurrence.vehicleLabel!,
                            ),
                          if (occurrence.locationAddress?.isNotEmpty == true)
                            _InfoLine(
                              label: 'Local',
                              value: occurrence.locationAddress!,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.description_outlined,
                        title: 'Relato final',
                        children: [
                          Text(
                            occurrence.finalReport?.trim().isNotEmpty == true
                                ? occurrence.finalReport!.trim()
                                : 'Relato final não informado.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.timeline_outlined,
                        title: 'Linha do tempo',
                        children: _events.isEmpty
                            ? const [Text('Nenhum evento registrado.')]
                            : _events.map(_EventReviewTile.new).toList(),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.fact_check_outlined,
                        title: 'Resultados',
                        children: [
                          if (occurrence.results.isEmpty)
                            const Text('Nenhum resultado informado.')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: occurrence.results
                                  .map(
                                    (result) => Chip(label: Text(result.label)),
                                  )
                                  .toList(),
                            ),
                          if (occurrence.finalizationPhotos.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${occurrence.finalizationPhotos.length} foto(s) de finalização anexada(s).',
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.groups_outlined,
                        title: 'Equipe e assinaturas',
                        children: occurrence.team
                            .map(
                              (member) => _TeamReviewTile(
                                member: member,
                                signatures: _teamViewModel.signatures,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                _ActionBar(
                  canSign: _canSign,
                  canRequestCorrection: _canRequestCorrection,
                  isBusy: _isRequestingCorrection,
                  onSign: _showSignatureDialog,
                  onCorrection: _showCorrectionDialog,
                ),
              ],
            ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool canSign;
  final bool canRequestCorrection;
  final bool isBusy;
  final VoidCallback onSign;
  final VoidCallback onCorrection;

  const _ActionBar({
    required this.canSign,
    required this.canRequestCorrection,
    required this.isBusy,
    required this.onSign,
    required this.onCorrection,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canRequestCorrection && !isBusy
                    ? onCorrection
                    : null,
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('Devolver'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: canSign && !isBusy ? onSign : null,
                icon: const Icon(Icons.draw_rounded),
                label: const Text('Assinar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _EventReviewTile extends StatelessWidget {
  final OccurrenceEvent event;

  const _EventReviewTile(this.event);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('HH:mm').format(event.timestamp)} · ${event.category.label}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          Text(
            event.title?.trim().isNotEmpty == true
                ? event.title!.trim()
                : 'Sem título',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (event.description?.trim().isNotEmpty == true)
            Text(event.description!.trim()),
          if (event.placeLabel?.trim().isNotEmpty == true)
            Text('Local: ${event.placeLabel!.trim()}'),
          if (event.photoUrls.isNotEmpty)
            Text('${event.photoUrls.length} foto(s) anexada(s).'),
          const Divider(height: 18),
        ],
      ),
    );
  }
}

class _TeamReviewTile extends StatelessWidget {
  final OccurrenceTeamMember member;
  final List<OccurrenceSignature> signatures;

  const _TeamReviewTile({required this.member, required this.signatures});

  @override
  Widget build(BuildContext context) {
    final signature = signatures.where(
      (item) => item.handlerId == member.handlerId,
    );
    final status = member.role == TeamRole.titular
        ? 'Relator'
        : signature.isEmpty
        ? 'Aguardando assinatura'
        : signature.first.status.toMap();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(_initials(member))),
      title: Text(
        member.displayName?.trim().isNotEmpty == true
            ? member.displayName!.trim()
            : member.handlerId,
      ),
      subtitle: Text(
        'RA ${member.handlerId}'
        '${member.dogName?.trim().isNotEmpty == true ? ' · K9 ${member.dogName!.trim()}' : ''}',
      ),
      trailing: Text(status),
    );
  }

  String _initials(OccurrenceTeamMember member) {
    final source = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : member.handlerId;
    if (source.length <= 2) return source.toUpperCase();
    return source.substring(0, 2).toUpperCase();
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
