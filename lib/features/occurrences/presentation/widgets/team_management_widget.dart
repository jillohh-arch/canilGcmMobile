import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/handler_search_dialog.dart';

class TeamManagementWidget extends StatefulWidget {
  final List<OccurrenceTeamMember> team;
  final List<OccurrenceSignature> signatures;
  final bool canAddMembers;
  final bool canRemoveMembers;
  final ValueChanged<Map<String, dynamic>> onAddMember;
  final Function(String) onRemoveMember;
  final Function() onRefresh;

  const TeamManagementWidget({
    super.key,
    required this.team,
    required this.signatures,
    required this.canAddMembers,
    required this.canRemoveMembers,
    required this.onAddMember,
    required this.onRemoveMember,
    required this.onRefresh,
  });

  @override
  State<TeamManagementWidget> createState() => _TeamManagementWidgetState();
}

class _TeamManagementWidgetState extends State<TeamManagementWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) {
            final hasServiceDog = widget.team.any((m) => m.hasServiceDog);
            return _buildContent(context, hasServiceDog: hasServiceDog);
          },
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, {required bool hasServiceDog}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hasServiceDog ? 'Guarnição' : 'Equipe',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (widget.canAddMembers)
              IconButton(
                onPressed: () => _showAddMemberDialog(),
                icon: const Icon(Icons.add),
                tooltip: 'Adicionar integrante',
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Lista da equipe
        if (widget.team.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hasServiceDog
                  ? 'Nenhuma guarnição vinculada'
                  : 'Nenhum integrante adicionado',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.team.length,
            separatorBuilder: (context, index) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final member = widget.team[index];
              final signature = widget.signatures.firstWhere(
                (s) => s.handlerId == member.handlerId,
                orElse: () => OccurrenceSignature(
                  handlerId: member.handlerId,
                  status: SignatureStatus.pending,
                  signatureMethod: SignatureMethod.biometric,
                  signatureHash: '',
                ),
              );

              return _TeamMemberCard(
                member: member,
                signature: signature,
                canRemove:
                    widget.canRemoveMembers && member.role != TeamRole.titular,
                onRemove: () => widget.onRemoveMember(member.handlerId),
              );
            },
          ),

        const SizedBox(height: 16),

        // Status geral
        _buildStatusSummary(),
      ],
    );
  }

  void _showAddMemberDialog() {
    showDialog(
      context: context,
      builder: (context) => HandlerSearchDialog(
        currentTeam: widget.team
            .map(
              (m) => {
                'handler_id': m.handlerId,
                'name': 'Handler ${m.handlerId}', // Nome temporário
                'image_url': '',
              },
            )
            .toList(),
        onSelected: (handler) {
          widget.onAddMember(handler);
        },
      ),
    );
  }

  Widget _buildStatusSummary() {
    if (widget.team.isEmpty) return const SizedBox.shrink();

    final signedCount = widget.signatures
        .where((s) => s.status == SignatureStatus.signed)
        .length;
    final pendingCount =
        widget.team.length - 1 - signedCount; // Descontando o titular

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$signedCount assinatura(s) coletada(s) de ${widget.team.length - 1} integrante(s)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (pendingCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$pendingCount pendente(s)',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  final OccurrenceTeamMember member;
  final OccurrenceSignature signature;
  final bool canRemove;
  final VoidCallback onRemove;

  const _TeamMemberCard({
    required this.member,
    required this.signature,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com informações do membro
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  _avatarText(member),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          member.displayName?.trim().isNotEmpty == true
                              ? member.displayName!.trim()
                              : 'RA ${member.handlerId}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: member.role == TeamRole.titular
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            member.role == TeamRole.titular
                                ? 'Titular'
                                : 'Integrante',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: member.role == TeamRole.titular
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RA ${member.handlerId}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (member.dogName?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'K9 ${member.dogName!.trim()}'
                        '${member.dogMatricula?.trim().isNotEmpty == true ? ' · matrícula ${member.dogMatricula!.trim()}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Adicionado em ${DateFormat('dd/MM/yyyy HH:mm').format(member.addedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Botão de remover
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  color: Theme.of(context).colorScheme.error,
                  tooltip: 'Remover da equipe',
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Status da assinatura
          Row(
            children: [
              Icon(
                _getSignatureIcon(),
                color: _getSignatureColor(context),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getSignatureText(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _getSignatureColor(context),
                  ),
                ),
              ),
              if (signature.status == SignatureStatus.expired &&
                  signature.reason != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                    size: 16,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _avatarText(OccurrenceTeamMember member) {
    final name = member.displayName?.trim();
    final source = name?.isNotEmpty == true ? name! : member.handlerId;
    if (source.length <= 2) return source.toUpperCase();
    return source.substring(0, 2).toUpperCase();
  }

  IconData _getSignatureIcon() {
    switch (signature.status) {
      case SignatureStatus.signed:
        return Icons.check_circle;
      case SignatureStatus.expired:
        return Icons.cancel;
      case SignatureStatus.pending:
        return Icons.schedule;
    }
  }

  Color _getSignatureColor(BuildContext context) {
    switch (signature.status) {
      case SignatureStatus.signed:
        return Theme.of(context).colorScheme.primary;
      case SignatureStatus.expired:
        return Theme.of(context).colorScheme.error;
      case SignatureStatus.pending:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _getSignatureText() {
    switch (signature.status) {
      case SignatureStatus.signed:
        return 'Assinado em ${DateFormat('dd/MM/yyyy HH:mm').format(signature.signedAt!)}';
      case SignatureStatus.expired:
        return signature.reason != null
            ? 'Não assinou: ${signature.reason}'
            : 'Assinatura expirada';
      case SignatureStatus.pending:
        return 'Aguardando assinatura';
    }
  }
}
