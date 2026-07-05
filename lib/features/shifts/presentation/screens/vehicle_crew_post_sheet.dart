import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/animation_constants.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/hud_status_dot.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_service.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';

/// Bottom sheet full-height com fluxo de 2 passos para assumir posto na guarnição.
class VehicleCrewPostSheet extends StatefulWidget {
  const VehicleCrewPostSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VehicleCrewPostSheet(),
    );
  }

  @override
  State<VehicleCrewPostSheet> createState() => _VehicleCrewPostSheetState();
}

class _VehicleCrewPostSheetState extends State<VehicleCrewPostSheet> {
  final VehicleService _vehicleService = VehicleService();
  final VehicleCrewService _crewService = VehicleCrewService();
  Vehicle? _selectedVehicle;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: _selectedVehicle == null
                    ? _VehicleSelectionStep(
                        vehicleService: _vehicleService,
                        crewService: _crewService,
                        onVehicleSelected: (vehicle) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedVehicle = vehicle);
                        },
                      )
                    : _PostBoardStep(
                        vehicle: _selectedVehicle!,
                        crewService: _crewService,
                        onBack: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedVehicle = null);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// PASSO 1: Seleção da viatura
/// ─────────────────────────────────────────────────────────────
class _VehicleSelectionStep extends StatelessWidget {
  final VehicleService vehicleService;
  final VehicleCrewService crewService;
  final ValueChanged<Vehicle> onVehicleSelected;

  const _VehicleSelectionStep({
    required this.vehicleService,
    required this.crewService,
    required this.onVehicleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withAlpha(60)),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASSUMIR VIATURA',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Escolha a viatura para assumir um posto',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
        const Divider(color: AppTheme.outlineVariant, height: 1),
        // Lista de viaturas
        Expanded(
          child: StreamBuilder<List<Vehicle>>(
            stream: vehicleService.watchActiveVehicles(),
            builder: (context, snapshot) {
              final vehicles = snapshot.data ?? [];

              if (snapshot.connectionState == ConnectionState.waiting &&
                  vehicles.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                );
              }

              if (vehicles.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nenhuma viatura ativa disponível.',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: vehicles.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final vehicle = vehicles[index];
                  return _VehicleCrewSummaryCard(
                    vehicle: vehicle,
                    crewService: crewService,
                    onTap: () => onVehicleSelected(vehicle),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Card mostrando resumo da guarnição de uma viatura.
class _VehicleCrewSummaryCard extends StatelessWidget {
  final Vehicle vehicle;
  final VehicleCrewService crewService;
  final VoidCallback onTap;

  const _VehicleCrewSummaryCard({
    required this.vehicle,
    required this.crewService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final crewId = vehicle.id;

    return StreamBuilder<List<VehicleCrewMember>>(
      stream: crewService.watchMembers(crewId),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final activeMembers = members.where((m) => m.isActive).toList();
        final occupancy = activeMembers.length;

        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: HudDurations.fast,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfacePanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withAlpha(50)),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.label,
                        style: GoogleFonts.robotoMono(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (vehicle.modelName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          vehicle.modelName,
                          style: GoogleFonts.inter(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _OccupancyBadge(
                  occupancy: occupancy,
                  crewSize: vehicle.crewSize,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Badge de ocupação da guarnição.
class _OccupancyBadge extends StatelessWidget {
  final int occupancy;
  final int crewSize;

  const _OccupancyBadge({
    required this.occupancy,
    required this.crewSize,
  });

  @override
  Widget build(BuildContext context) {
    final full = occupancy >= crewSize;
    final color = full ? AppTheme.warning : AppTheme.success;
    final label = full ? 'CHEIA' : '$occupancy/$crewSize';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: GoogleFonts.robotoMono(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// PASSO 2: Quadro de postos da viatura
/// ─────────────────────────────────────────────────────────────
class _PostBoardStep extends StatelessWidget {
  final Vehicle vehicle;
  final VehicleCrewService crewService;
  final VoidCallback onBack;

  const _PostBoardStep({
    required this.vehicle,
    required this.crewService,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final crewId = vehicle.id;

    return Column(
      children: [
        // Header com status da guarnição
        _PostBoardHeader(vehicle: vehicle, crewService: crewService),
        const Divider(color: AppTheme.outlineVariant, height: 1),
        // Botão "Selecionar outra viatura" - ação discreta
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Trocar viatura'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textTertiary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: GoogleFonts.inter(fontSize: 12),
              ),
            ),
          ),
        ),
        // Quadro de postos
        Expanded(
          child: StreamBuilder<List<VehicleCrewMember>>(
            stream: crewService.watchMembers(crewId),
            builder: (context, snapshot) {
              final members = snapshot.data ?? [];
              final activeMembersList = members.where((m) => m.isActive).toList()
                ..sort((a, b) => a.role.compareTo(b.role));
              final activeMembers = {
                for (final m in activeMembersList) m.role: m
              };

              // Verificar se o usuário logado é condutor de binômio ativo
              final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
              final hasBinomioActive = shiftVM.hasActiveShift &&
                  shiftVM.activeDogId != null &&
                  shiftVM.activeDogId!.trim().isNotEmpty;

              return _PostBoard(
                vehicle: vehicle,
                activeMembers: activeMembers,
                hasBinomioActive: hasBinomioActive,
                onPostSelected: (role) =>
                    _confirmAndAssumePost(context, vehicle, role),
                onLeaveVehicle: () => _confirmLeaveVehicle(context, vehicle),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndAssumePost(
    BuildContext context,
    Vehicle vehicle,
    String role,
  ) async {
    final roleLabel = _roleLabel(role);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Assumir posto?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Deseja assumir o posto de $roleLabel na ${vehicle.label}?',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Assumir',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Chamar assumeVehicle via ShiftViewModel com o nome do condutor
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final currentHandlerId = shiftVM.handlerId;
    final memberName = userVM.displayNameFor(ra: currentHandlerId ?? '');
    await shiftVM.assumeVehicle(vehicle, role: role, name: memberName);

    if (!context.mounted) return;

    final error = shiftVM.error;
    if (error != null) {
      AppFeedback.error(context, error);
    } else {
      AppFeedback.success(context, 'Posto de $roleLabel assumido na ${vehicle.label}.');
      Navigator.pop(context); // Fecha o sheet
    }
  }

  Future<void> _confirmLeaveVehicle(BuildContext context, Vehicle vehicle) async {
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final crewRole = shiftVM.crewRole;
    final roleLabel = crewRole != null ? _roleLabel(crewRole) : 'seu posto';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Sair da viatura?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Seu posto de $roleLabel na ${vehicle.label} será liberado. O turno continua ativo.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sair',
              style: GoogleFonts.inter(
                color: AppTheme.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await shiftVM.leaveVehicle();

    if (!context.mounted) return;

    final error = shiftVM.error;
    if (error != null) {
      AppFeedback.error(context, error);
    } else {
      AppFeedback.success(context, 'Posto liberado. O turno continua ativo.');
      Navigator.pop(context); // Fecha o sheet
    }
  }
}

/// Header do quadro de postos com status OPERACIONAL/INCOMPLETA.
class _PostBoardHeader extends StatelessWidget {
  final Vehicle vehicle;
  final VehicleCrewService crewService;

  const _PostBoardHeader({
    required this.vehicle,
    required this.crewService,
  });

  @override
  Widget build(BuildContext context) {
    final crewId = vehicle.id;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.label,
                      style: GoogleFonts.robotoMono(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (vehicle.modelName.isNotEmpty)
                      Text(
                        vehicle.modelName,
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              // Status chip
              FutureBuilder<String>(
                future: crewService.getCrewOperationalStatus(crewId),
                builder: (context, snapshot) {
                  final status = snapshot.data ?? 'empty';
                  return _OperationalStatusChip(status: status);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip de status operacional.
class _OperationalStatusChip extends StatelessWidget {
  final String status;

  const _OperationalStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'operational' => ('OPERACIONAL', AppTheme.success),
      'incomplete' => ('INCOMPLETA', AppTheme.warning),
      _ => ('DISPONIVEL', AppTheme.primary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'operational')
            const Padding(
              padding: EdgeInsets.only(right: 5),
              child: Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 12),
            ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 4 postos humanos (K9 é vínculo, não posto).
/// Role 'k9' mantido no enum/rule por retrocompatibilidade.
/// Cada member com dog_id preenchido é o condutor responsável pelo cão.
class _PostBoard extends StatelessWidget {
  final Vehicle vehicle;
  final Map<String, VehicleCrewMember> activeMembers;
  final bool hasBinomioActive;
  final void Function(String role) onPostSelected;
  final VoidCallback onLeaveVehicle;

  const _PostBoard({
    required this.vehicle,
    required this.activeMembers,
    required this.hasBinomioActive,
    required this.onPostSelected,
    required this.onLeaveVehicle,
  });

  static const _roles = ['motorista', 'encarregado', 'auxiliar_1', 'auxiliar_2'];

  @override
  Widget build(BuildContext context) {
    // Verificar se o usuário logado está nesta guarnição
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final currentCrewId = shiftVM.vehicleCrewId;
    final currentHandlerId = shiftVM.handlerId;
    final isInThisCrew = currentCrewId == vehicle.id;

    // Identificar o membro com cão embarcado (condutor K9 = vínculo)
    VehicleCrewMember? k9Member;
    for (final m in activeMembers.values) {
      if (m.dogId != null && m.dogId!.trim().isNotEmpty) {
        k9Member = m;
        break;
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _roles.length + 1, // 4 postos + 1 linha K9
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index < _roles.length) {
                final role = _roles[index];
                final member = activeMembers[role];
                final isOccupied = member != null;
                // Badge K9 se o membro tem cão embarcado
                final hasK9 = isOccupied && member.dogId!.trim().isNotEmpty;
                // Verificar se este slot é do usuário atual
                final isCurrentUser = isOccupied && member.handlerId == currentHandlerId;

                return _PostSlot(
                  role: role,
                  member: member,
                  isOccupied: isOccupied,
                  hasK9: hasK9,
                  isCurrentUser: isCurrentUser,
                  onTap: isOccupied ? null : () => onPostSelected(role),
                );
              } else {
                // Linha K9: vínculo, não posto
                return _K9Line(
                  k9Member: k9Member,
                  hasBinomioActive: hasBinomioActive,
                );
              }
            },
          ),
        ),
        // Botão "Sair da viatura"
        if (isInThisCrew)
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLeaveVehicle,
                icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                label: const Text('SAIR DA VIATURA'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  side: const BorderSide(color: AppTheme.warning),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Slot individual de posto.
class _PostSlot extends StatelessWidget {
  final String role;
  final VehicleCrewMember? member;
  final bool hasK9; // badge K9 se este membro é o condutor do cão
  final bool isOccupied;
  final bool isCurrentUser; // destaca o slot do usuário atual
  final VoidCallback? onTap;

  const _PostSlot({
    required this.role,
    required this.member,
    required this.hasK9,
    required this.isOccupied,
    required this.isCurrentUser,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: HudDurations.fast,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isOccupied ? AppTheme.surfacePanel : AppTheme.surfacePanelAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentUser
                ? AppTheme.primary.withAlpha(180)
                : AppTheme.outlineVariant,
            width: isCurrentUser ? 2 : 1,
          ),
        ),
        child: isOccupied
            ? _OccupiedSlot(member: member!, role: role, hasK9: hasK9, isCurrentUser: isCurrentUser)
            : _VacantSlot(role: role),
      ),
    );
  }
}

/// Slot ocupado com info do membro e badge K9 quando aplicável.
class _OccupiedSlot extends StatelessWidget {
  final VehicleCrewMember member;
  final String role;
  final bool hasK9;
  final bool isCurrentUser;

  const _OccupiedSlot({
    required this.member,
    required this.role,
    required this.hasK9,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final userVM = Provider.of<UserViewModel>(context);
    final memberName = member.name ?? userVM.displayNameFor(ra: member.handlerId);
    // Cor do dot: cyan para o usuário atual, verde para os demais
    final dotColor = isCurrentUser ? AppTheme.primary : AppTheme.success;

    return Row(
      children: [
        // Dot de status ativo
        HudStatusDot(color: dotColor, size: 8, ringMaxSize: 16),
        const SizedBox(width: 12),
        // Role label
        Container(
          width: 100,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.textTertiary.withAlpha(15),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            _roleLabel(role),
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Badge K9 se este membro é o condutor do cão
        if (hasK9)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: Text(
              'K9',
              style: GoogleFonts.robotoMono(
                color: AppTheme.primary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        if (hasK9) const SizedBox(width: 8),
        // Avatar placeholder com iniciais do nome
        _OccupiedAvatar(member: member),
        const SizedBox(width: 10),
        // Nome + RA
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memberName,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'RA ${member.handlerId}',
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slot vago com botão ASSUMIR.
class _VacantSlot extends StatelessWidget {
  final String role;

  const _VacantSlot({required this.role});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Espaço vazio
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.textTertiary.withAlpha(80)),
          ),
        ),
        const SizedBox(width: 16),
        // Role label
        Container(
          width: 100,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.textTertiary.withAlpha(15),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            _roleLabel(role),
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Avatar placeholder vazio com borda dashed
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.background,
            border: Border.all(
              color: AppTheme.textTertiary.withAlpha(60),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: const Icon(Icons.person_outline, color: AppTheme.textTertiary, size: 16),
        ),
        const SizedBox(width: 10),
        // Status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vago',
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        // Botão ASSUMIR
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primary.withAlpha(60)),
          ),
          child: Text(
            'ASSUMIR',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Linha de vínculo K9 (não é posto — aparece abaixo dos 4 puestos).
class _K9Line extends StatelessWidget {
  final VehicleCrewMember? k9Member;
  final bool hasBinomioActive;

  const _K9Line({
    required this.k9Member,
    required this.hasBinomioActive,
  });

  @override
  Widget build(BuildContext context) {
    // Buscar nome do cão via DogService se tivermos o dogId
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: k9Member != null
            ? AppTheme.primary.withAlpha(8)
            : AppTheme.surfacePanelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: k9Member != null
              ? AppTheme.primary.withAlpha(40)
              : AppTheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          // Ícone K9
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: k9Member != null
                  ? AppTheme.primary.withAlpha(20)
                  : AppTheme.textTertiary.withAlpha(15),
            ),
            child: Icon(
              Icons.pets_rounded,
              color: k9Member != null ? AppTheme.primary : AppTheme.textTertiary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'K9 EMBARCADO',
                  style: GoogleFonts.robotoMono(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                if (k9Member != null) ...[
                  // Cão embarcado: foto/nome do cão + condutor responsável
                  FutureBuilder<String?>(
                    future: _getDogName(k9Member!.dogId!),
                    builder: (context, snap) {
                      final dogName = snap.data ?? k9Member!.dogId;
                      final handlerName = k9Member!.name ?? 'RA ${k9Member!.handlerId}';
                      final roleCapitalized = _roleLabelCapitalized(k9Member!.role);
                      return Text(
                        '$dogName — Conduzido por $handlerName ($roleCapitalized)',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ] else ...[
                  Text(
                    hasBinomioActive
                        ? 'Sem K9 nesta guarnição'
                        : 'Sem K9 embarcado',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _getDogName(String dogId) async {
    try {
      final dogService = DogService();
      final dog = await dogService.watchDog(dogId).first;
      return dog?.name;
    } catch (_) {
      return dogId; // Fallback: mostra o ID
    }
  }
}

/// Label legível para cada função.
String _roleLabel(String role) {
  return switch (role) {
    'motorista' => 'MOTORISTA',
    'encarregado' => 'ENCARREGADO',
    'auxiliar_1' => 'AUXILIAR 1',
    'auxiliar_2' => 'AUXILIAR 2',
    'k9' => 'K9',
    _ => role.toUpperCase(),
  };
}

/// Label capitalizado para cada função (não grita).
String _roleLabelCapitalized(String role) {
  return switch (role) {
    'motorista' => 'Motorista',
    'encarregado' => 'Encarregado',
    'auxiliar_1' => 'Auxiliar 1',
    'auxiliar_2' => 'Auxiliar 2',
    'k9' => 'K9',
    _ => role,
  };
}

/// Avatar do slot ocupado mostrando iniciais do nome.
class _OccupiedAvatar extends StatelessWidget {
  final VehicleCrewMember member;

  const _OccupiedAvatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final memberName = member.name;
    final initials = _getInitials(memberName ?? member.handlerId);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.success.withAlpha(15),
        border: Border.all(color: AppTheme.success.withAlpha(180)),
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(
            color: AppTheme.success,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '--';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    final first = parts.first.substring(0, 1).toUpperCase();
    final last = parts.last.isNotEmpty ? parts.last.substring(0, 1).toUpperCase() : '';
    return '$first$last';
  }
}
