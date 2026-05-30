import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_transition_service.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class VehicleCrewProfileScreen extends StatefulWidget {
  final String crewId;

  const VehicleCrewProfileScreen({super.key, required this.crewId});

  @override
  State<VehicleCrewProfileScreen> createState() =>
      _VehicleCrewProfileScreenState();
}

class _VehicleCrewProfileScreenState extends State<VehicleCrewProfileScreen> {
  final VehicleCrewService _crewService = VehicleCrewService();
  final VehicleCrewTransitionService _transitionService =
      VehicleCrewTransitionService();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final authVM = context.watch<AuthViewModel>();
    final userVM = context.watch<UserViewModel>();
    final dogVM = context.watch<DogViewModel>();
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Equipe'),
      ),
      body: StreamBuilder<VehicleCrew?>(
        stream: _crewService.watchCrew(widget.crewId),
        builder: (context, crewSnapshot) {
          final crew = crewSnapshot.data;
          if (crewSnapshot.connectionState == ConnectionState.waiting &&
              crew == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (crew == null) {
            return const Center(
              child: Text(
                'Guarnição não encontrada.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return StreamBuilder<List<VehicleCrewMember>>(
            stream: _crewService.watchMembers(crew.id),
            builder: (context, membersSnapshot) {
              final members =
                  membersSnapshot.data ?? const <VehicleCrewMember>[];
              final currentMember = _memberFor(members, currentRa);
              final activeCount = members
                  .where((member) => member.isActive)
                  .length;
              final reservedCount = members
                  .where((member) => member.isActive || member.isPending)
                  .length;
              final dog = _dogFor(dogVM, crew.serviceDogId);
              final isTitular = crew.titularHandlerId == currentRa;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _VehicleCard(crew: crew),
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: 'CONDUTORES',
                    trailing: '$activeCount de ${crew.crewSize}',
                  ),
                  const SizedBox(height: 10),
                  ...members.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MemberCard(
                        member: member,
                        user: userVM.findByRa(member.handlerId),
                        isCurrentUser: member.handlerId == currentRa,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SectionHeader(title: 'CÃO DE SERVIÇO'),
                  const SizedBox(height: 10),
                  _ServiceDogCard(dog: dog, fallbackId: crew.serviceDogId),
                  if (currentMember?.isPending == true) ...[
                    const SizedBox(height: 18),
                    _InvitationResponseCard(
                      submitting: _submitting,
                      onAccept: () => _respondToInvitation(accept: true),
                      onDecline: _declineInvitation,
                    ),
                  ],
                  if (isTitular) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: reservedCount >= crew.crewSize || _submitting
                          ? null
                          : () => _showInviteDialog(
                              crew: crew,
                              members: members,
                              currentRa: currentRa,
                            ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(
                        reservedCount >= crew.crewSize
                            ? 'Guarnição completa'
                            : 'Adicionar parceiro à guarnição',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                          color: AppTheme.primary.withAlpha(115),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'A capacidade da viatura reserva vagas para convites pendentes. '
                    'O parceiro entra na guarnição somente depois do aceite.',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showInviteDialog({
    required VehicleCrew crew,
    required List<VehicleCrewMember> members,
    required String currentRa,
  }) async {
    final selected = await showModalBottomSheet<UserModel>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      builder: (context) =>
          _AvailableHandlersSheet(currentRa: currentRa, members: members),
    );
    if (selected == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _transitionService.inviteMember(
        crewId: crew.id,
        handlerId: selected.ra,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Convite enviado para RA ${selected.ra}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar o convite: $error'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _respondToInvitation({
    required bool accept,
    String? reason,
  }) async {
    setState(() => _submitting = true);
    try {
      await _transitionService.respondToInvitation(
        crewId: widget.crewId,
        accept: accept,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Você entrou na guarnição.'
                : 'Convite recusado com justificativa.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível responder ao convite: $error'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _declineInvitation() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recusar convite'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo obrigatório',
            hintText: 'Informe por que não entrará na guarnição',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.of(context).pop(text);
            },
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    await _respondToInvitation(accept: false, reason: reason);
  }

  VehicleCrewMember? _memberFor(
    List<VehicleCrewMember> members,
    String handlerId,
  ) {
    for (final member in members) {
      if (member.handlerId == handlerId) return member;
    }
    return null;
  }

  Dog? _dogFor(DogViewModel dogVM, String dogId) {
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog;
    }
    return null;
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleCrew crew;

  const _VehicleCard({required this.crew});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: Border.all(color: AppTheme.primary.withAlpha(48)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crew.vehicleLabel,
                      style: GoogleFonts.robotoMono(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (crew.vehicleModel?.isNotEmpty == true)
                      Text(
                        crew.vehicleModel!,
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: 'cap.', value: '${crew.crewSize} + K9'),
              if (crew.vehicleUnit?.isNotEmpty == true)
                _InfoChip(label: 'unidade', value: crew.vehicleUnit!),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(12),
        border: Border.all(color: Colors.white.withAlpha(16)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: GoogleFonts.robotoMono(
          color: AppTheme.textSecondary,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: Colors.white.withAlpha(18))),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(
            trailing!,
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  final VehicleCrewMember member;
  final UserModel? user;
  final bool isCurrentUser;

  const _MemberCard({
    required this.member,
    required this.user,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final name = user?.callsign.trim().isNotEmpty == true
        ? user!.callsign.trim()
        : 'RA ${member.handlerId}';
    final statusColor = member.isPending
        ? AppTheme.warning
        : member.isDeclined
        ? AppTheme.error
        : AppTheme.success;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppTheme.primary.withAlpha(10)
            : Colors.white.withAlpha(7),
        border: Border.all(
          color: member.isPending
              ? AppTheme.warning.withAlpha(96)
              : Colors.white.withAlpha(18),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _InitialsAvatar(text: name, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'RA ${member.handlerId}',
                  style: GoogleFonts.robotoMono(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(
            text: isCurrentUser
                ? 'VOCE'
                : member.isPending
                ? 'CONVITE ENVIADO'
                : member.isDeclined
                ? 'RECUSADO'
                : member.isTitular
                ? 'TITULAR'
                : 'NA EQUIPE',
            color: isCurrentUser ? AppTheme.primary : statusColor,
          ),
        ],
      ),
    );
  }
}

class _ServiceDogCard extends StatelessWidget {
  final Dog? dog;
  final String fallbackId;

  const _ServiceDogCard({required this.dog, required this.fallbackId});

  @override
  Widget build(BuildContext context) {
    final name = dog?.name ?? fallbackId;
    final meta = [
      if (dog?.registrationNumber?.isNotEmpty == true)
        'matrícula ${dog!.registrationNumber}',
      if (dog?.breed.isNotEmpty == true) dog!.breed,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(8),
        border: Border.all(color: AppTheme.success.withAlpha(52)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _InitialsAvatar(text: name, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name  K9',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: GoogleFonts.robotoMono(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitationResponseCard extends StatelessWidget {
  final bool submitting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InvitationResponseCard({
    required this.submitting,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withAlpha(12),
        border: Border.all(color: AppTheme.warning.withAlpha(80)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Convite pendente',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Confirme se você vai compor esta guarnição durante o turno.',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting ? null : onAccept,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aceitar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: submitting ? null : onDecline,
                  child: const Text('Recusar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailableHandlersSheet extends StatefulWidget {
  final String currentRa;
  final List<VehicleCrewMember> members;

  const _AvailableHandlersSheet({
    required this.currentRa,
    required this.members,
  });

  @override
  State<_AvailableHandlersSheet> createState() =>
      _AvailableHandlersSheetState();
}

class _AvailableHandlersSheetState extends State<_AvailableHandlersSheet> {
  final TextEditingController _searchController = TextEditingController();
  UserModel? _selected;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userVM = context.watch<UserViewModel>();
    final unavailable = {
      for (final member in widget.members)
        if (member.isActive || member.isPending) member.handlerId,
    };
    final query = _query.trim().toLowerCase();
    final handlers =
        userVM.users.where((user) {
          final ra = user.ra.trim();
          if (ra.isEmpty || ra == widget.currentRa) return false;
          if (unavailable.contains(ra)) return false;
          if (query.isEmpty) return true;
          return ra.toLowerCase().contains(query) ||
              user.callsign.toLowerCase().contains(query) ||
              user.name.toLowerCase().contains(query) ||
              user.unit.toLowerCase().contains(query);
        }).toList()..sort((a, b) {
          final byName = _handlerLabel(
            a,
          ).toLowerCase().compareTo(_handlerLabel(b).toLowerCase());
          return byName != 0 ? byName : a.ra.compareTo(b.ra);
        });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adicionar à guarnição',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Condutores cadastrados para receber convite. O parceiro entra na guarnição somente depois do aceite.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Buscar por nome, guerra ou RA',
                filled: true,
                fillColor: Colors.white.withAlpha(7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withAlpha(18)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withAlpha(18)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: handlers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        userVM.isLoading
                            ? 'Carregando condutores cadastrados...'
                            : 'Nenhum condutor cadastrado disponível.',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: handlers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final handler = handlers[index];
                        final selected = _selected?.ra == handler.ra;
                        return ListTile(
                          onTap: () => setState(() => _selected = handler),
                          selected: selected,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: selected
                                  ? AppTheme.primary
                                  : Colors.white.withAlpha(18),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: _InitialsAvatar(
                            text: _handlerLabel(handler),
                            color: AppTheme.primary,
                          ),
                          title: Text(_handlerLabel(handler)),
                          subtitle: Text(_handlerSubtitle(handler)),
                          trailing: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textTertiary,
                          ),
                        );
                      },
                    ),
            ),
            FilledButton.icon(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.of(context).pop(_selected),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar convite'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _handlerLabel(UserModel user) {
    final callsign = user.callsign.trim();
    if (callsign.isNotEmpty) return callsign;
    final name = user.name.trim();
    if (name.isNotEmpty) return name;
    return 'RA ${user.ra}';
  }

  String _handlerSubtitle(UserModel user) {
    final parts = <String>[
      'RA ${user.ra}',
      if (user.name.trim().isNotEmpty) user.name.trim(),
      if (user.unit.trim().isNotEmpty) user.unit.trim(),
    ];
    return parts.join(' - ');
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String text;
  final Color color;

  const _InitialsAvatar({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final normalized = text.trim();
    final initials = normalized.isEmpty
        ? '--'
        : normalized.length <= 3
        ? normalized.toUpperCase()
        : normalized.substring(0, 3).toUpperCase();
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(8),
        border: Border.all(color: color),
      ),
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
