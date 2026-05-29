import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_team_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/deadline_expired_dialog.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/team_header_widget.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/team_management_widget.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/occurrence_status_header.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/handler_search_dialog.dart';
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
      notificationService: NotificationService(),
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
    final canManageTeam = _canCurrentUserManageTeam();
    final canCloseForSignatures = _canCurrentUserCloseForSignatures();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Equipe'),
        actions: [
          // Botão para adicionar membro
          if (canManageTeam && _viewModel.canAddTeamMembers)
            IconButton(
              onPressed: _showAddMemberDialog,
              icon: const Icon(Icons.person_add),
              tooltip: 'Adicionar integrante',
            ),
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
                    teamSize: occurrence.teamSizeMax,
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
                        if (occurrence.status ==
                                OccurrenceStatus.awaitingSignatures &&
                            (canSignOccurrence || canControlSignatures))
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
                                if (canSignOccurrence) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _showSignatureDialog,
                                      icon: const Icon(Icons.draw_rounded),
                                      label: const Text('Assinar ocorrência'),
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
                                if (canControlSignatures)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _showRevertToDraftDialog,
                                          icon: const Icon(Icons.undo),
                                          label: const Text(
                                            'Voltar para draft',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _showMarkExpiredDialog,
                                          icon: const Icon(Icons.warning_amber),
                                          label: const Text(
                                            'Marcar como expirado',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.errorContainer,
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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

  void _showAddMemberDialog() {
    showDialog(
      context: context,
      builder: (context) => HandlerSearchDialog(
        currentTeam: _viewModel.team
            .map(
              (m) => {
                'handler_id': m.handlerId,
                'name': 'Handler ${m.handlerId}',
                'image_url': '',
              },
            )
            .toList(),
        onSelected: (handler) {
          _handleSelectedMember(handler);
        },
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

  void _showSignatureDialog() {
    final occurrence = _viewModel.occurrence;
    if (occurrence == null || !_canCurrentUserSign(_viewModel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não há assinatura pendente para este usuário.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
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

  void _showDeadlineExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DeadlineExpiredDialog(viewModel: _viewModel),
    );
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  void _handleRemoveMember(String handlerId) {
    _viewModel.removeTeamMember(
      handlerId: handlerId,
      onSuccess: (message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  void _handleSignatureSuccess() {
    _viewModel.initialize(occurrenceId: widget.occurrenceId);
    _showSnackMessage('Assinatura registrada com sucesso.');
  }

  void _showSnackMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
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
