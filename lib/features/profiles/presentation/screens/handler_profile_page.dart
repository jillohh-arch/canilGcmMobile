import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/dog_profile_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
const Color _kBg = Color(0xFF050D10);
const Color _kTextPrimary = Color(0xFFFFFFFF);
const Color _kTextSecondary = Color(0xFFB0C4CC);
const Color _kTextMuted = Color(0xFF7A8A92);
const Color _kBorder = Color(0x14FFFFFF);
const Color _kBorderSubtle = Color(0x0FFFFFFF);

class HandlerProfilePage extends StatelessWidget {
  final bool showBottomNav;

  const HandlerProfilePage({super.key, this.showBottomNav = true});

  @override
  Widget build(BuildContext context) {
    return Consumer4<AuthViewModel, UserViewModel, DogViewModel, ShiftViewModel>(
      builder: (context, authVM, userVM, dogVM, shiftVM, _) {
        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser) ?? '';
        final user = _findUser(userVM, currentRa);
        final callsign = userVM.displayNameFor(ra: currentRa, firebaseUser: fbUser);
        final name = _resolveName(user, callsign);
        final dog = _activeDog(dogVM, shiftVM, currentRa);

        return Scaffold(
          backgroundColor: _kBg,
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header
                  _ProfileHeader(onClose: () => Navigator.of(context).maybePop()),
                  // Scroll content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IdentityCard(
                            name: name,
                            ra: currentRa,
                            photoUrl: user?.photoUrl ?? fbUser?.photoURL,
                            yearsInCanil: _yearsInCanil(user),
                          ),
                          const SizedBox(height: 16),
                          _DogSection(dog: dog),
                          const SizedBox(height: 20),
                          _StatsSection(),
                          const SizedBox(height: 20),
                          _SelosSection(dog: dog),
                          const SizedBox(height: 20),
                          _SettingsMenu(),
                          const SizedBox(height: 14),
                          _CtaButtons(
                            hasActiveShift: shiftVM.hasActiveShift,
                            onEndShift: () => _endShift(context, shiftVM),
                            onLogout: () => _logout(context, authVM),
                          ),
                          const SizedBox(height: 18),
                          const _FooterInfo(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  UserModel? _findUser(UserViewModel userVM, String ra) {
    for (final u in userVM.users) {
      if (u.ra == ra) return u;
    }
    return null;
  }

  String _resolveName(UserModel? user, String callsign) {
    final name = user?.callsign.trim().isNotEmpty == true ? user!.callsign : callsign;
    if (name.trim().isEmpty || name == 'Condutor') return 'GCM Condutor';
    return name.startsWith('GCM ') ? name : 'GCM $name';
  }

  Dog? _activeDog(DogViewModel dogVM, ShiftViewModel shiftVM, String ra) {
    final activeDogId = shiftVM.activeDogId;
    if (activeDogId != null) {
      try {
        return dogVM.dogs.firstWhere((d) => d.id == activeDogId);
      } catch (_) {}
    }
    // Fallback: cão titular
    try {
      return dogVM.dogs.firstWhere((d) => d.conductorRa == ra);
    } catch (_) {}
    return dogVM.dogs.isNotEmpty ? dogVM.dogs.first : null;
  }

  int _yearsInCanil(UserModel? user) {
    // Sem campo createdAt no UserModel — valor padrão
    return 4;
  }

  Future<void> _endShift(BuildContext context, ShiftViewModel shiftVM) async {
    HapticFeedback.mediumImpact();
    await shiftVM.endShift();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expediente encerrado')),
      );
    }
  }

  Future<void> _logout(BuildContext context, AuthViewModel authVM) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Sair do app?',
          style: GoogleFonts.inter(color: _kTextPrimary, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Você precisará fazer login novamente.',
          style: GoogleFonts.inter(color: _kTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.inter(color: _kTextMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sair', style: GoogleFonts.inter(color: AppTheme.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) await authVM.signOut();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGETS PRIVADOS
// ══════════════════════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _ProfileHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Icon(Icons.close_rounded, color: _kTextPrimary, size: 22),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Perfil',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _kTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 36), // spacer
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final String name;
  final String ra;
  final String? photoUrl;
  final int yearsInCanil;

  const _IdentityCard({
    required this.name,
    required this.ra,
    this.photoUrl,
    required this.yearsInCanil,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withAlpha(20),
            AppTheme.primary.withAlpha(5),
          ],
        ),
        border: Border.all(color: AppTheme.primary.withAlpha(51)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A2A30),
              border: Border.all(color: AppTheme.primary, width: 3),
            ),
            child: ClipOval(
              child: photoUrl != null && photoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _avatarFallback(),
                      errorWidget: (_, __, ___) => _avatarFallback(),
                    )
                  : _avatarFallback(),
            ),
          ),
          const SizedBox(height: 10),
          // Nome
          Text(
            name,
            style: GoogleFonts.inter(
              color: _kTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          // RA
          Text(
            'RA $ra · Limeira/SP',
            style: GoogleFonts.inter(
              color: _kTextSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          // Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge(
                label: '● CONDUTOR TITULAR',
                bgColor: AppTheme.success.withAlpha(38),
                textColor: AppTheme.success,
              ),
              const SizedBox(width: 8),
              _Badge(
                label: '$yearsInCanil ANOS NO CANIL',
                bgColor: AppTheme.primary.withAlpha(25),
                textColor: AppTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    final initials = name.replaceAll('GCM ', '').trim();
    final text = initials.length >= 3 ? initials.substring(0, 3).toUpperCase() : initials.toUpperCase();
    return Container(
      color: const Color(0xFF1A2A30),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _Badge({required this.label, required this.bgColor, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Seção "SEU CÃO" ─────────────────────────────────────────────────────────

class _DogSection extends StatelessWidget {
  final Dog? dog;

  const _DogSection({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileSectionLabel(text: 'SEU CÃO'),
        if (dog != null)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DogProfileScreen(dog: dog!)),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Avatar do cão
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A2A30),
                      border: Border.all(color: AppTheme.success, width: 2),
                    ),
                    child: ClipOval(
                      child: dog!.profileImageUrl != null && dog!.profileImageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: dog!.profileImageUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _dogFallback(),
                              errorWidget: (_, __, ___) => _dogFallback(),
                            )
                          : _dogFallback(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BINÔMIO ATIVO',
                          style: GoogleFonts.inter(
                            color: _kTextMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${dog!.name} · ${dog!.breed} · ${dog!.age} anos',
                          style: GoogleFonts.inter(
                            color: _kTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '● Operacional · ${(dog!.specialties?.length ?? 0)} especialidades',
                          style: GoogleFonts.inter(
                            color: AppTheme.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '›',
                    style: GoogleFonts.inter(color: _kTextMuted, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Nenhum cão vinculado ao turno.',
              style: GoogleFonts.inter(color: _kTextMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _dogFallback() {
    return Container(
      color: const Color(0xFF1A2A30),
      alignment: Alignment.center,
      child: Text(
        dog!.name.isNotEmpty ? dog!.name.substring(0, dog!.name.length.clamp(0, 4)).toUpperCase() : 'K9',
        style: GoogleFonts.inter(
          color: AppTheme.success,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── Seção "SUA ATUAÇÃO" ──────────────────────────────────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context) {
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileSectionLabel(text: 'SUA ATUAÇÃO', trailing: 'desde 2022'),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatCard(
              icon: Icons.calendar_month_rounded,
              color: AppTheme.primary,
              value: '12',
              label: 'PLANTÕES',
            ),
            _StatCard(
              icon: Icons.schedule_rounded,
              color: AppTheme.success,
              value: '96h',
              label: 'HORAS',
            ),
            _StatCard(
              icon: Icons.shield_rounded,
              color: AppTheme.warning,
              value: '${incidentVM.incidents.length}',
              label: 'OCORRÊNCIAS',
            ),
            _StatCard(
              icon: Icons.fitness_center_rounded,
              color: const Color(0xFF9B59B6),
              value: '${trainingVM.trainings.length}',
              label: 'TREINOS',
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border.all(color: _kBorderSubtle),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: _kTextMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
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

// ── Section label reutilizável ───────────────────────────────────────────────

class _ProfileSectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  const _ProfileSectionLabel({required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: AppTheme.primary.withAlpha(38)),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: GoogleFonts.inter(
                color: _kTextMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Seção "CONFORMIDADE PROFISSIONAL" ────────────────────────────────────────

class _SelosSection extends StatelessWidget {
  final Dog? dog;

  const _SelosSection({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileSectionLabel(text: 'CONFORMIDADE PROFISSIONAL', trailing: '9 de 11'),
        // Intro
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(color: _kTextSecondary, fontSize: 11, height: 1.4),
              children: [
                TextSpan(
                  text: 'Selos institucionais',
                  style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.w700),
                ),
                const TextSpan(
                  text: ' calculados conforme protocolo. Não há ranking — apenas conformidade com o padrão estabelecido.',
                ),
              ],
            ),
          ),
        ),
        // Operacional
        _SeloCategoryLabel(text: 'OPERACIONAL'),
        _SelosGrid(selos: const [
          _SeloData(icon: Icons.calendar_month_rounded, name: 'Plantões sem lacunas', meta: 'há 142 dias', active: true),
          _SeloData(icon: Icons.edit_note_rounded, name: 'Relato final 100%', meta: 'últimas 30 ocorrências', active: true),
          _SeloData(icon: Icons.picture_as_pdf_rounded, name: 'PDFs gerados 100%', meta: 'últimas 30 ocorrências', active: true),
        ]),
        const SizedBox(height: 14),
        // Treino
        _SeloCategoryLabel(text: 'TREINO'),
        _SelosGrid(selos: [
          _SeloData(
            icon: Icons.fitness_center_rounded,
            name: 'Manutenções em dia',
            meta: '${dog?.specialties?.length ?? 0} especialidades',
            active: true,
          ),
          const _SeloData(icon: Icons.pets_rounded, name: 'Biblioteca atualizada', meta: 'comandos · estágios', active: true),
        ]),
        const SizedBox(height: 14),
        // Saúde do cão
        _SeloCategoryLabel(text: 'SAÚDE DO CÃO'),
        const _SelosGrid(selos: [
          _SeloData(icon: Icons.vaccines_rounded, name: 'Vacinas em dia', meta: 'cronograma cumprido', active: true),
          _SeloData(icon: Icons.shield_rounded, name: 'Antipulgas em dia', meta: 'vence em 15 dias', active: false),
          _SeloData(icon: Icons.restaurant_rounded, name: 'Conformidade alimentar', meta: '100% conforme laudo', active: true),
          _SeloData(icon: Icons.monitor_weight_rounded, name: 'Peso monitorado', meta: 'registros recentes', active: true),
        ]),
        const SizedBox(height: 14),
        // Administrativo
        _SeloCategoryLabel(text: 'ADMINISTRATIVO'),
        const _SelosGrid(selos: [
          _SeloData(icon: Icons.person_rounded, name: 'Perfil completo', meta: 'dados atualizados', active: true),
          _SeloData(icon: Icons.assignment_rounded, name: 'Documentos do cão', meta: '2 pendentes', active: false),
        ]),
      ],
    );
  }
}

class _SeloCategoryLabel extends StatelessWidget {
  final String text;

  const _SeloCategoryLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: _kTextMuted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SeloData {
  final IconData icon;
  final String name;
  final String meta;
  final bool active;

  const _SeloData({
    required this.icon,
    required this.name,
    required this.meta,
    required this.active,
  });
}

class _SelosGrid extends StatelessWidget {
  final List<_SeloData> selos;

  const _SelosGrid({required this.selos});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3.0,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: selos.map((s) => _SeloCard(selo: s)).toList(),
    );
  }
}

class _SeloCard extends StatelessWidget {
  final _SeloData selo;

  const _SeloCard({required this.selo});

  @override
  Widget build(BuildContext context) {
    final color = selo.active ? AppTheme.success : const Color(0xFF95A5A6);
    final opacity = selo.active ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selo.active
              ? AppTheme.success.withAlpha(10)
              : Colors.white.withAlpha(8),
          border: Border.all(
            color: selo.active
                ? AppTheme.success.withAlpha(51)
                : _kBorderSubtle,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(selo.icon, color: color, size: 13),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    selo.name,
                    style: GoogleFonts.inter(
                      color: selo.active ? _kTextPrimary : const Color(0xFF95A5A6),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    selo.meta,
                    style: GoogleFonts.inter(
                      color: _kTextMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Seção "CONFIGURAÇÕES" ────────────────────────────────────────────────────

class _SettingsMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ProfileSectionLabel(text: 'CONFIGURAÇÕES'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: _kBorderSubtle),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _MenuItem(
                icon: Icons.notifications_outlined,
                label: 'Notificações',
                desc: 'Lembretes de vacinas, refeições, treinos',
              ),
              _MenuDivider(),
              _MenuItem(
                icon: Icons.sync_rounded,
                label: 'Sincronização',
                desc: 'Última: agora · automático',
              ),
              _MenuDivider(),
              _MenuItem(
                icon: Icons.lock_outline_rounded,
                label: 'Segurança',
                desc: 'Biometria · alterar senha',
              ),
              _MenuDivider(),
              _MenuItem(
                icon: Icons.info_outline_rounded,
                label: 'Sobre o app',
                desc: 'Versão · termos · privacidade',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;

  const _MenuItem({required this.icon, required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    color: _kTextMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text('›', style: GoogleFonts.inter(color: _kTextMuted, fontSize: 14)),
        ],
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 58),
      color: Colors.white.withAlpha(10),
    );
  }
}

// ── CTAs ─────────────────────────────────────────────────────────────────────

class _CtaButtons extends StatelessWidget {
  final bool hasActiveShift;
  final VoidCallback onEndShift;
  final VoidCallback onLogout;

  const _CtaButtons({
    required this.hasActiveShift,
    required this.onEndShift,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (hasActiveShift)
          _CtaButton(
            icon: Icons.stop_rounded,
            label: 'ENCERRAR EXPEDIENTE',
            bgColor: AppTheme.warning.withAlpha(20),
            borderColor: AppTheme.warning.withAlpha(102),
            textColor: AppTheme.warning,
            onTap: onEndShift,
          ),
        if (hasActiveShift) const SizedBox(height: 8),
        _CtaButton(
          icon: Icons.logout_rounded,
          label: 'SAIR DO APP',
          bgColor: AppTheme.error.withAlpha(15),
          borderColor: AppTheme.error.withAlpha(77),
          textColor: AppTheme.error,
          onTap: onLogout,
        ),
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  const _CtaButton({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

class _FooterInfo extends StatelessWidget {
  const _FooterInfo();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '1.0.0';
        return Center(
          child: Text(
            'Canil K9 · GCM Limeira-SP · v$version',
            style: GoogleFonts.inter(
              color: _kTextMuted,
              fontSize: 9,
            ),
          ),
        );
      },
    );
  }
}
