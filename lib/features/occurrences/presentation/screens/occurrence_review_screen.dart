import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
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
  final OccurrenceRepository? occurrenceRepository;
  final OccurrenceEventRepository? eventRepository;
  final SignatureRepository? signatureRepository;
  final OccurrenceTransitionService? transitionService;
  final String? currentHandlerRa;
  final OccurrenceFinalizationViewModel? teamViewModel;

  const OccurrenceReviewScreen({
    super.key,
    required this.occurrenceId,
    this.occurrenceRepository,
    this.eventRepository,
    this.signatureRepository,
    this.transitionService,
    this.currentHandlerRa,
    this.teamViewModel,
  });

  @override
  State<OccurrenceReviewScreen> createState() => _OccurrenceReviewScreenState();
}

class _OccurrenceReviewScreenState extends State<OccurrenceReviewScreen> {
  late final OccurrenceRepository _occurrenceRepository;
  late final OccurrenceEventRepository _eventRepository;
  late final OccurrenceTransitionService _transitionService;
  late final OccurrenceFinalizationViewModel _teamViewModel;

  bool _isLoading = true;
  bool _isRequestingCorrection = false;
  bool _isRespondingParticipation = false;
  String? _error;
  Occurrence? _occurrence;
  List<OccurrenceEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    _occurrenceRepository = widget.occurrenceRepository ??
        OccurrenceRepository(FirebaseFirestore.instance);
    _eventRepository = widget.eventRepository ??
        OccurrenceEventRepository(FirebaseFirestore.instance);
    _transitionService =
        widget.transitionService ?? OccurrenceTransitionService();
    _teamViewModel = widget.teamViewModel ??
        OccurrenceFinalizationViewModel(
          occurrenceRepository: _occurrenceRepository,
          signatureRepository:
              widget.signatureRepository ?? SignatureRepository(),
        );
    _load();
  }

  @override
  void dispose() {
    if (widget.teamViewModel == null) {
      _teamViewModel.dispose();
    }
    super.dispose();
  }

  String? _currentHandlerRa() {
    return widget.currentHandlerRa ??
        HandlerIdentityService.raFromUser(FirebaseAuth.instance.currentUser);
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
    final currentRa = _currentHandlerRa();
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
    final currentRa = _currentHandlerRa();
    if (occurrence == null ||
        currentRa == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }
    final member = occurrence.team.where((item) => item.handlerId == currentRa);
    if (member.isEmpty || member.first.role == TeamRole.titular) return false;
    final hasAlreadySigned = _teamViewModel.signatures.any(
      (signature) =>
          signature.handlerId == currentRa &&
          signature.status == SignatureStatus.signed,
    );
    if (hasAlreadySigned) {
      return false;
    }
    return true;
  }

  bool get _canRespondParticipation {
    final occurrence = _occurrence;
    final currentRa = _currentHandlerRa();
    if (occurrence == null || currentRa == null || !occurrence.status.isOpen) {
      return false;
    }
    if (occurrence.primaryHandlerRa == currentRa ||
        occurrence.primaryHandlerId == currentRa) {
      return false;
    }
    return occurrence.pendingHandlerIds.contains(currentRa);
  }

  void _showSignatureDialog() {
    final occurrence = _occurrence;
    if (occurrence == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SignatureConfirmationDialog(
        occurrence: occurrence,
        viewModel: _teamViewModel,
        currentHandlerRa: _currentHandlerRa(),
        onSuccess: () async {
          await _load();
          if (!mounted) return;
          AppFeedback.success(context, 'Assinatura registrada.');
          if (_occurrence != null && _occurrence!.status.isClosed) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop('signed_and_sealed');
            }
          }
        },
      ),
    );
  }

  Future<void> _showCorrectionDialog() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ReasonInputDialog(
        title: 'Devolver para correção',
        labelText: 'Motivo',
        hintText: 'Explique o que precisa ser corrigido',
        actionLabel: 'Devolver',
        validationErrorMessage: 'Informe o motivo da devolução.',
      ),
    );

    if (reason != null && mounted) {
      await _requestCorrection(reason);
    }
  }

  Future<void> _showDeclineParticipationDialog() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ReasonInputDialog(
        title: 'Recusar participação',
        labelText: 'Motivo da recusa',
        hintText: 'Explique por que não participou desta ocorrência',
        actionLabel: 'Recusar',
        validationErrorMessage: 'Informe o motivo da recusa.',
      ),
    );

    if (reason != null && mounted) {
      await _declineParticipation(reason);
    }
  }

  Future<void> _acceptParticipation() async {
    setState(() => _isRespondingParticipation = true);
    var didNavigate = false;
    try {
      await _occurrenceRepository.acceptParticipation(
        occurrenceId: widget.occurrenceId,
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Participação confirmada.');
      didNavigate = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ActiveOccurrenceScreen(occurrenceId: widget.occurrenceId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(context, error);
    } finally {
      if (mounted && !didNavigate) {
        setState(() => _isRespondingParticipation = false);
      }
    }
  }

  Future<void> _declineParticipation(String reason) async {
    setState(() => _isRespondingParticipation = true);
    try {
      await _transitionService.declineParticipation(
        occurrenceId: widget.occurrenceId,
        reason: reason,
      );
      await _load();
      if (!mounted) return;
      AppFeedback.success(context, 'Participação recusada.');
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(context, error);
    } finally {
      if (mounted) setState(() => _isRespondingParticipation = false);
    }
  }

  Future<void> _requestCorrection(String reason) async {
    setState(() => _isRequestingCorrection = true);
    var didPop = false;
    try {
      await _transitionService.requestCorrection(
        occurrenceId: widget.occurrenceId,
        reason: reason,
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Ocorrência devolvida para correção.');
      if (Navigator.of(context).canPop()) {
        didPop = true;
        Navigator.of(context).pop('returned_for_correction');
      } else {
        await _load();
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(context, error);
    } finally {
      if (mounted && !didPop) {
        setState(() => _isRequestingCorrection = false);
      }
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
                      if (occurrence.status.isClosed) ...[
                        _SectionCard(
                          icon: Icons.lock_outline,
                          title: 'Ocorrência selada',
                          children: const [
                            Text(
                              'Esta ocorrência foi finalizada e selada pelo encarregado. Não há ações pendentes de resposta ou assinatura.',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
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
                  canRespondParticipation: _canRespondParticipation,
                  canSign: _canSign,
                  canRequestCorrection: _canRequestCorrection,
                  isBusy: _isRequestingCorrection || _isRespondingParticipation,
                  onAcceptParticipation: _acceptParticipation,
                  onDeclineParticipation: _showDeclineParticipationDialog,
                  onSign: _showSignatureDialog,
                  onCorrection: _showCorrectionDialog,
                ),
              ],
            ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool canRespondParticipation;
  final bool canSign;
  final bool canRequestCorrection;
  final bool isBusy;
  final VoidCallback onAcceptParticipation;
  final VoidCallback onDeclineParticipation;
  final VoidCallback onSign;
  final VoidCallback onCorrection;

  const _ActionBar({
    required this.canRespondParticipation,
    required this.canSign,
    required this.canRequestCorrection,
    required this.isBusy,
    required this.onAcceptParticipation,
    required this.onDeclineParticipation,
    required this.onSign,
    required this.onCorrection,
  });

  @override
  Widget build(BuildContext context) {
    if (!canRespondParticipation && !canSign && !canRequestCorrection) {
      return const SizedBox.shrink();
    }

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
                onPressed: canRespondParticipation
                    ? (isBusy ? null : onDeclineParticipation)
                    : (canRequestCorrection && !isBusy ? onCorrection : null),
                icon: Icon(
                  canRespondParticipation
                      ? Icons.cancel_outlined
                      : Icons.assignment_return_outlined,
                ),
                label: Text(canRespondParticipation ? 'Recusar' : 'Devolver'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: canRespondParticipation
                    ? (isBusy ? null : onAcceptParticipation)
                    : (canSign && !isBusy ? onSign : null),
                icon: Icon(
                  canRespondParticipation
                      ? Icons.check_circle_outline
                      : Icons.draw_rounded,
                ),
                label: Text(canRespondParticipation ? 'Aceitar' : 'Assinar'),
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

class _ReasonInputDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String hintText;
  final String actionLabel;
  final String validationErrorMessage;

  const _ReasonInputDialog({
    required this.title,
    required this.labelText,
    required this.hintText,
    required this.actionLabel,
    required this.validationErrorMessage,
  });

  @override
  State<_ReasonInputDialog> createState() => _ReasonInputDialogState();
}

class _ReasonInputDialogState extends State<_ReasonInputDialog> {
  late final TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _validationError = widget.validationErrorMessage);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        onChanged: (_) {
          if (_validationError != null) {
            setState(() => _validationError = null);
          }
        },
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          errorText: _validationError,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
