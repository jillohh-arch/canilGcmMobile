import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_team_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/deadline_expired_dialog.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/team_header_widget.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/team_management_widget.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/occurrence_status_header.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/signature_confirmation_dialog.dart';

class OccurrenceTeamScreen extends StatefulWidget {
  final String occurrenceId;

  const OccurrenceTeamScreen({super.key, required this.occurrenceId});

  @override
  State<OccurrenceTeamScreen> createState() => _OccurrenceTeamScreenState();
}

class _OccurrenceTeamScreenState extends State<OccurrenceTeamScreen> {
  late OccurrenceFinalizationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = OccurrenceFinalizationViewModel(
      occurrenceRepository: OccurrenceRepository(FirebaseFirestore.instance),
      signatureRepository: SignatureRepository(),
    );
    _viewModel.addListener(_syncAppBarActions);
    _viewModel.initialize(occurrenceId: widget.occurrenceId);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_syncAppBarActions);
    _viewModel.dispose();
    super.dispose();
  }

  void _syncAppBarActions() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCloseForSignatures = _canCurrentUserCloseForSignatures();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Participação da Guarnição'),
        actions: [
          // Botão para adicionar membro
          // Botão para fechar para assinaturas
          if (canCloseForSignatures)
            IconButton(
              onPressed: _showCloseForSignaturesDialog,
              icon: const Icon(Icons.lock),
              tooltip: 'Fechar para assinaturas',
            ),
        ],
      ),
      body: ChangeNotifierProvider<OccurrenceTeamViewModel>.value(
        value: _viewModel,
        child: Consumer<OccurrenceTeamViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (viewModel.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao carregar',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      viewModel.error!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        viewModel.clearError();
                        viewModel.initialize(occurrenceId: widget.occurrenceId);
                      },
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              );
            }

            if (viewModel.occurrence == null) {
              return const Center(child: Text('Ocorrência não encontrada'));
            }

            final occurrence = viewModel.occurrence!;
            final canSignOccurrence = _canCurrentUserSign(viewModel);
            final canControlSignatures = _isCurrentUserTitular(occurrence);
            final canEditTeam = _canCurrentUserManageTeam();
            final canDeclineParticipation = _canCurrentUserDeclineParticipation(
              occurrence,
            );
            final showActions =
                canDeclineParticipation ||
                (occurrence.status == OccurrenceStatus.awaitingSignatures &&
                    (canSignOccurrence ||
                        (canControlSignatures &&
                            _viewModel.isDeadlineExpired)));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header com status
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OccurrenceStatusHeader(
                    status: occurrence.status,
                    signatureRequestAt: occurrence.signatureRequestAt,
                    signatureDeadline: occurrence.signatureDeadline,
                    teamSize: occurrence.team.length,
                    signedCount: viewModel.signatures
                        .where((s) => s.status == SignatureStatus.signed)
                        .length,
                    showDeadlineWarning: viewModel.shouldShowDeadlineWarning,
                  ),
                ),

                // Seção da equipe
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TeamHeaderWidget(
                          team: occurrence.team,
                          avatarSize: 40,
                          showRoleLabels: true,
                        ),

                        const SizedBox(height: 16),

                        TeamManagementWidget(
                          team: occurrence.team,
                          signatures: viewModel.signatures,
                          declinedHandlerIds: occurrence.declinedHandlerIds
                              .toSet(),
                          canAddMembers:
                              canEditTeam && viewModel.canAddTeamMembers,
                          canRemoveMembers:
                              canEditTeam && viewModel.canRemoveMembers,
                          onAddMember: _handleAddMember,
                          onRemoveMember: _handleRemoveMember,
                          onRefresh: () => viewModel.initialize(
                            occurrenceId: widget.occurrenceId,
                          ),
                        ),

                        // Botões de ação
                        if (showActions)
                          Container(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ações',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                if (canDeclineParticipation) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _showDeclineParticipationDialog,
                                      icon: const Icon(
                                        Icons.person_off_outlined,
                                      ),
                                      label: const Text('Recusar participação'),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (canSignOccurrence) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _openReviewScreen,
                                      icon: const Icon(Icons.draw_rounded),
                                      label: const Text('Revisar e assinar'),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (canControlSignatures &&
                                    _viewModel.isDeadlineExpired) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _showDeadlineExpiredDialog,
                                      icon: const Icon(Icons.warning_amber),
                                      label: const Text(
                                        'Resolver prazo vencido',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCloseForSignaturesDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fechar para Assinaturas'),
        content: const Text(
          'Tem certeza que deseja fechar esta ocorrência para assinaturas? '
          'Após esta ação, não será possível adicionar mais integrantes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _viewModel.closeForSignatures(
                signatureDeadline: const Duration(hours: 48),
                onSuccess: _showSnackMessage,
                onError: (error) =>
                    _showSnackMessage('Erro: $error', isError: true),
              );
            },
            child: const Text('Fechar para Assinaturas'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  void _showSignatureDialog() {
    final occurrence = _viewModel.occurrence;
    if (occurrence == null || !_canCurrentUserSign(_viewModel)) {
      AppFeedback.warning(
        context,
        'Não há assinatura pendente para este usuário.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SignatureConfirmationDialog(
        occurrence: occurrence,
        viewModel: _viewModel,
        onSuccess: _handleSignatureSuccess,
      ),
    );
  }

  void _openReviewScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OccurrenceReviewScreen(occurrenceId: widget.occurrenceId),
      ),
    );
  }

  void _showDeclineParticipationDialog() {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recusar participação'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Justificativa',
            hintText: 'Informe o motivo da recusa',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                _showSnackMessage(
                  'Informe uma justificativa para recusar.',
                  isError: true,
                );
                return;
              }
              Navigator.pop(dialogContext);
              _declineParticipation(reason);
            },
            child: const Text('Recusar'),
          ),
        ],
      ),
    ).whenComplete(reasonController.dispose);
  }

  Future<void> _declineParticipation(String reason) async {
    try {
      await OccurrenceTransitionService().declineParticipation(
        occurrenceId: widget.occurrenceId,
        reason: reason,
      );
      await _viewModel.initialize(occurrenceId: widget.occurrenceId);
      _showSnackMessage('Participação recusada com justificativa.');
    } catch (error) {
      _showSnackMessage('Erro ao recusar participação: $error', isError: true);
    }
  }

  void _showDeadlineExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DeadlineExpiredDialog(viewModel: _viewModel),
    );
  }

  // ignore: unused_element
  void _showRevertToDraftDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Voltar para Draft'),
        content: const Text(
          'Tem certeza que deseja reverter esta ocorrência para draft? '
          'Todas as assinaturas serão perdidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _viewModel.revertToDraft(
                onSuccess: _showSnackMessage,
                onError: (error) =>
                    _showSnackMessage('Erro: $error', isError: true),
              );
            },
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  void _showMarkExpiredDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Marcar como Expirado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selecione um integrante para marcar como expirado:'),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Escolha um integrante'),
              value: null,
              items: _viewModel.team
                  .where((m) => m.role != TeamRole.titular)
                  .map(
                    (member) => DropdownMenuItem(
                      value: member.handlerId,
                      child: Text('Handler ${member.handlerId}'),
                    ),
                  )
                  .toList(),
              onChanged: (handlerId) {
                if (handlerId != null) {
                  Navigator.pop(dialogContext);
                  _viewModel.markSignatureExpired(
                    handlerId: handlerId,
                    reason: 'Não assinou no prazo',
                    onSuccess: _showSnackMessage,
                    onError: (error) =>
                        _showSnackMessage('Erro: $error', isError: true),
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _handleAddMember(Map<String, dynamic> handler) {
    _handleSelectedMember(handler);
  }

  void _handleSelectedMember(Map<String, dynamic> handler) {
    final handlerId = handler['ra']?.toString().trim() ?? '';
    if (handlerId.isEmpty) return;

    _viewModel.addTeamMember(
      handlerId: handlerId,
      addedBy: _currentRa(),
      displayName: handler['name']?.toString(),
      handlerEmail: handler['email']?.toString(),
      authUid: handler['authUid']?.toString(),
      onSuccess: (message) {
        AppFeedback.success(context, message);
      },
      onError: (error) {
        AppFeedback.error(context, 'Erro: $error');
      },
    );
  }

  void _handleRemoveMember(String handlerId) {
    _viewModel.removeTeamMember(
      handlerId: handlerId,
      onSuccess: (message) {
        AppFeedback.success(context, message);
      },
      onError: (error) {
        AppFeedback.error(context, 'Erro: $error');
      },
    );
  }

  void _handleSignatureSuccess() {
    _viewModel.initialize(occurrenceId: widget.occurrenceId);
    _showSnackMessage('Assinatura registrada com sucesso.');
  }

  void _showSnackMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppFeedback.error(context, message);
    } else {
      AppFeedback.success(context, message);
    }
  }

  bool _canCurrentUserManageTeam() {
    final occurrence = _viewModel.occurrence;
    final currentRa = _currentRaOrNull();
    if (occurrence == null || currentRa == null) return false;
    return occurrence.status == OccurrenceStatus.inProgress &&
        (occurrence.team.any((member) => member.handlerId == currentRa) ||
            occurrence.primaryHandlerRa == currentRa ||
            occurrence.primaryHandlerId == currentRa);
  }

  bool _canCurrentUserDeclineParticipation(Occurrence occurrence) {
    final currentRa = _currentRaOrNull();
    if (currentRa == null) return false;
    if (occurrence.primaryHandlerRa == currentRa ||
        occurrence.primaryHandlerId == currentRa) {
      return false;
    }
    if (occurrence.status != OccurrenceStatus.inProgress &&
        occurrence.status != OccurrenceStatus.finalizing) {
      return false;
    }
    if (occurrence.declinedHandlerIds.contains(currentRa)) return false;
    return occurrence.team.any((member) => member.handlerId == currentRa);
  }

  bool _canCurrentUserCloseForSignatures() {
    final occurrence = _viewModel.occurrence;
    if (occurrence == null || !_viewModel.canCloseForSignatures) return false;
    return _isCurrentUserTitular(occurrence);
  }

  bool _canCurrentUserSign(OccurrenceTeamViewModel viewModel) {
    final occurrence = viewModel.occurrence;
    final currentRa = _currentRaOrNull();
    if (occurrence == null ||
        currentRa == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }

    OccurrenceTeamMember? currentMember;
    for (final member in occurrence.team) {
      if (member.handlerId == currentRa) {
        currentMember = member;
        break;
      }
    }
    if (currentMember == null || currentMember.role == TeamRole.titular) {
      return false;
    }

    for (final signature in viewModel.signatures) {
      if (signature.handlerId != currentRa) continue;
      return signature.status == SignatureStatus.pending;
    }
    return true;
  }

  bool _isCurrentUserTitular(Occurrence occurrence) {
    final currentRa = _currentRaOrNull();
    if (currentRa == null) return false;
    return occurrence.team.any(
          (member) =>
              member.handlerId == currentRa && member.role == TeamRole.titular,
        ) ||
        occurrence.primaryHandlerRa == currentRa ||
        occurrence.primaryHandlerId == currentRa;
  }

  String? _currentRaOrNull() {
    return HandlerIdentityService.raFromUser(FirebaseAuth.instance.currentUser);
  }

  String _currentRa() {
    return _currentRaOrNull() ?? 'desconhecido';
  }
}
