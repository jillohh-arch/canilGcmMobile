import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/gamification/domain/badge_progress.dart';
import 'package:canil_gcm/features/gamification/domain/level_progress.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/gamification/domain/weekly_mission_progress.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/gamification/data/gamification_service.dart';
import 'package:canil_gcm/features/gamification/domain/badges_data.dart';
import 'package:canil_gcm/features/gamification/presentation/widgets/gamification_progress_widgets.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudPanelAlt = Color(0xFF111827);
const _hudCyan = Color(0xFF00E5FF);
const _hudAmber = Color(0xFFFBBF24);
const _hudGreen = Color(0xFF00E58A);
const _hudDanger = Color(0xFFFF3B6B);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _callsignController;
  bool _isEditMode = false;
  bool _isSaving = false;
  bool _isEndingShift = false;
  File? _newPhotoFile;
  Future<Map<String, BadgeProgress>>? _badgeProgressFuture;
  Future<List<WeeklyMissionProgress>>? _weeklyMissionFuture;
  String? _badgeProgressRa;
  String? _weeklyMissionRa;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _callsignController = TextEditingController();
  }

  void _ensureBadgeProgressLoaded(String? ra) {
    if (ra == null || ra.isEmpty) return;
    if (_badgeProgressRa == ra && _badgeProgressFuture != null) return;
    _badgeProgressRa = ra;
    _badgeProgressFuture = GamificationService().getBadgeProgress(ra);
  }

  void _ensureWeeklyMissionsLoaded(String? ra) {
    if (ra == null || ra.isEmpty) return;
    if (_weeklyMissionRa == ra && _weeklyMissionFuture != null) return;
    _weeklyMissionRa = ra;
    _weeklyMissionFuture = (() async {
      await GamificationService().syncWeeklyMissions(ra);
      return GamificationService().getWeeklyMissionProgress(ra);
    })();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _callsignController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (img != null && mounted) {
      setState(() => _newPhotoFile = File(img.path));
    }
  }

  Future<void> _saveChanges(
    UserModel? currentUser,
    AuthViewModel authVM,
    UserViewModel userVM,
  ) async {
    if (currentUser == null) return;
    setState(() => _isSaving = true);
    try {
      String? newPhotoUrl = currentUser.photoUrl;
      if (_newPhotoFile != null) {
        final storage = StorageService();
        newPhotoUrl = await storage.uploadProfileImage(
          _newPhotoFile!,
          'profile_photos',
        );
      }
      final updated = UserModel(
        ra: currentUser.ra,
        name: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : currentUser.name,
        callsign: _callsignController.text.trim().isNotEmpty
            ? _callsignController.text.trim()
            : currentUser.callsign,
        unit: currentUser.unit,
        accessLevel: currentUser.accessLevel,
        photoUrl: newPhotoUrl,
        userBadges: currentUser.userBadges,
        xp: currentUser.xp,
      );
      await userVM.saveUser(updated);
      if (mounted) {
        setState(() {
          _isEditMode = false;
          _newPhotoFile = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Perfil atualizado e sincronizado.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: _hudPanel,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: _hudGreen.withAlpha(150)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar perfil: $e'),
            backgroundColor: _hudPanel,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AuthViewModel, UserViewModel, ShiftViewModel>(
      builder: (context, authVM, userVM, shiftVM, _) {
        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final userModel = userVM.users.cast<UserModel?>().firstWhere(
          (u) => u?.ra == currentRa,
          orElse: () => null,
        );

        final callsign = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );
        final nameStr = userModel?.name ?? '';
        final raStr = userModel?.ra ?? currentRa ?? '--';
        final photoStr = _newPhotoFile != null
            ? null
            : (userModel?.photoUrl ?? fbUser?.photoURL);

        // Sync controllers when entering edit mode for the first time
        if (_isEditMode && _callsignController.text.isEmpty) {
          _callsignController.text = callsign;
          _nameController.text = nameStr;
        }

        final int xp = userModel?.xp ?? 0;
        final int level = GamificationService.calculateLevel(xp);
        final LevelProgress levelProgress =
            GamificationService.getLevelProgress(xp);
        _ensureBadgeProgressLoaded(currentRa);
        _ensureWeeklyMissionsLoaded(currentRa);

        return Scaffold(
          backgroundColor: _hudBackground,
          body: CustomScrollView(
            slivers: [
              // ── Immersive Hero Header ──
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: _hudBackground,
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  IconButton(
                    icon: Icon(
                      _isEditMode ? Icons.close_rounded : Icons.edit_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isEditMode = !_isEditMode;
                        if (!_isEditMode) {
                          _newPhotoFile = null;
                          _callsignController.text = callsign;
                          _nameController.text = nameStr;
                        } else {
                          _callsignController.text = callsign;
                          _nameController.text = nameStr;
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Blurred background photo
                      if (photoStr != null)
                        ClipRect(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 14,
                              sigmaY: 14,
                            ),
                            child: CachedNetworkImage(
                              imageUrl: photoStr,
                              fit: BoxFit.cover,
                              color: Colors.black.withValues(alpha: 0.31),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1A2A1A), Color(0xFF0C1A2E)],
                            ),
                          ),
                        ),

                      // Dark gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black45,
                              _hudBackground.withAlpha(220),
                            ],
                          ),
                        ),
                      ),

                      // Centered crisp avatar + name
                      SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(),
                            // Crisp CircleAvatar
                            GestureDetector(
                              onTap: _isEditMode ? _pickPhoto : null,
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _hudCyan,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _hudCyan.withAlpha(110),
                                          blurRadius: 30,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 52,
                                      backgroundColor: _hudPanelAlt,
                                      backgroundImage: _newPhotoFile != null
                                          ? FileImage(_newPhotoFile!)
                                                as ImageProvider
                                          : (photoStr != null
                                                ? CachedNetworkImageProvider(
                                                    photoStr,
                                                  )
                                                : null),
                                      child:
                                          (_newPhotoFile == null &&
                                              photoStr == null)
                                          ? Text(
                                              callsign.isNotEmpty
                                                  ? callsign[0].toUpperCase()
                                                  : 'O',
                                              style: GoogleFonts.inter(
                                                fontSize: 36,
                                                color: _hudCyan,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (_isEditMode)
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _hudCyan,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 16,
                                        color: _hudBackground,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              callsign.toUpperCase(),
                              style: GoogleFonts.oxanium(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.8,
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 8),
                                ],
                              ),
                            ),
                            if (nameStr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  nameStr,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.white60,
                                    fontWeight: FontWeight.w500,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'RA: $raStr',
                              style: GoogleFonts.robotoMono(
                                fontSize: 13,
                                color: _hudCyan.withAlpha(180),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _hudPanel.withAlpha(215),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _hudAmber.withAlpha(170),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: _hudAmber,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'NÍVEL $level • $xp XP',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: _hudAmber,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Edit Fields (shown in edit mode) ──
              if (_isEditMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EDITAR PERFIL',
                          style: GoogleFonts.robotoMono(
                            color: _hudCyan.withAlpha(210),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Name field
                        TextFormField(
                          controller: _nameController,
                          cursorColor: _hudCyan,
                          style: GoogleFonts.robotoMono(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Nome',
                            labelStyle: GoogleFonts.robotoMono(
                              color: _hudCyan.withAlpha(180),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(Icons.person_rounded),
                            prefixIconColor: _hudCyan.withAlpha(170),
                            filled: true,
                            fillColor: _hudPanel.withAlpha(220),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: _hudCyan.withAlpha(60),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: _hudCyan.withAlpha(60),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: _hudCyan),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Callsign field
                        TextFormField(
                          controller: _callsignController,
                          cursorColor: _hudCyan,
                          style: GoogleFonts.robotoMono(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Nome de Guerra (Codinome)',
                            labelStyle: GoogleFonts.robotoMono(
                              color: _hudCyan.withAlpha(180),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(Icons.military_tech_rounded),
                            prefixIconColor: _hudCyan.withAlpha(170),
                            filled: true,
                            fillColor: _hudPanel.withAlpha(220),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: _hudCyan.withAlpha(60),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: _hudCyan.withAlpha(60),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: _hudCyan),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // RA (read-only)
                        TextFormField(
                          initialValue: raStr,
                          readOnly: true,
                          style: GoogleFonts.robotoMono(
                            color: Colors.white54,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'R.A. (somente leitura)',
                            labelStyle: GoogleFonts.robotoMono(
                              color: Colors.white38,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.white24,
                            ),
                            filled: true,
                            fillColor: _hudPanel.withAlpha(150),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: _hudCyan.withAlpha(35),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Save button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () {
                                    HapticFeedback.mediumImpact();
                                    _saveChanges(userModel, authVM, userVM);
                                  },
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.save_rounded,
                                    color: _hudBackground,
                                  ),
                            label: Text(
                              _isSaving ? 'SALVANDO...' : 'SALVAR ALTERAÇÕES',
                              style: GoogleFonts.oxanium(
                                fontWeight: FontWeight.w900,
                                color: _hudBackground,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hudCyan,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              elevation: 8,
                              shadowColor: _hudCyan.withAlpha(100),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Info Cards ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    _isEditMode ? 24 : 24,
                    20,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IDENTIFICAÇÃO',
                        style: GoogleFonts.robotoMono(
                          color: _hudCyan.withAlpha(210),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.military_tech_rounded,
                        label: 'Codinome',
                        value: callsign,
                      ),
                      if (nameStr.isNotEmpty)
                        _InfoRow(
                          icon: Icons.person_rounded,
                          label: 'Nome',
                          value: nameStr,
                        ),
                      _InfoRow(
                        icon: Icons.numbers_rounded,
                        label: 'R.A.',
                        value: raStr,
                      ),
                      if (userModel?.unit.isNotEmpty == true)
                        _InfoRow(
                          icon: Icons.business_rounded,
                          label: 'Unidade',
                          value: userModel!.unit,
                        ),
                      if (userModel?.accessLevel.isNotEmpty == true)
                        _InfoRow(
                          icon: Icons.security_rounded,
                          label: 'Nível',
                          value: userModel!.accessLevel,
                        ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EVOLUÇÃO TÁTICA',
                        style: GoogleFonts.robotoMono(
                          color: _hudCyan.withAlpha(210),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LevelProgressCard(progress: levelProgress),
                      if (_weeklyMissionFuture != null) ...[
                        const SizedBox(height: 14),
                        FutureBuilder<List<WeeklyMissionProgress>>(
                          future: _weeklyMissionFuture,
                          builder: (context, missionSnapshot) {
                            if (missionSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFFBBF24),
                                  ),
                                ),
                              );
                            }

                            final missions =
                                missionSnapshot.data ??
                                const <WeeklyMissionProgress>[];

                            return _buildBadgeStatusCard(
                              title: 'MISSÕES DA SEMANA',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Metas rápidas da semana com bônus automático de XP ao concluir.',
                                    style: GoogleFonts.inter(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...missions.map((mission) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: WeeklyMissionCard(
                                        mission: mission,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Galeria de Troféus (Gamification V2) ──
              if (userModel != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GALERIA DE TROFÉUS',
                          style: GoogleFonts.robotoMono(
                            color: _hudCyan.withAlpha(210),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: BadgesConfig.badges.map((b) {
                            final bool isUnlocked = userModel.userBadges
                                .contains(b.id);

                            return Tooltip(
                              message: isUnlocked
                                  ? b.description
                                  : 'Bloqueado: ${b.description}',
                              textStyle: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: isUnlocked
                                  ? Container(
                                      width: 80,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(8),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: b.color.withAlpha(140),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: b.color.withValues(
                                              alpha: 0.16,
                                            ),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            b.icon,
                                            size: 32,
                                            color: b.color,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            b.name,
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ColorFiltered(
                                      colorFilter: const ColorFilter.matrix([
                                        0.2126, 0.7152, 0.0722, 0, 0,
                                        0.2126, 0.7152, 0.0722, 0, 0,
                                        0.2126, 0.7152, 0.0722, 0, 0,
                                        0,
                                        0,
                                        0,
                                        0.4,
                                        0, // Opacidade reduzida + Grayscale
                                      ]),
                                      child: Container(
                                        width: 80,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(5),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: b.color.withAlpha(120),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              b.icon,
                                              size: 32,
                                              color: b.color,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              b.name,
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),

              if (userModel != null && _badgeProgressFuture != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                    child: FutureBuilder<Map<String, BadgeProgress>>(
                      future: _badgeProgressFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: CircularProgressIndicator(
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          );
                        }

                        final progressMap =
                            snapshot.data ?? const <String, BadgeProgress>{};
                        final lockedBadges =
                            BadgesConfig.badges
                                .where(
                                  (badge) =>
                                      !userModel.userBadges.contains(badge.id),
                                )
                                .where(
                                  (badge) => progressMap.containsKey(badge.id),
                                )
                                .toList()
                              ..sort((a, b) {
                                final progressA = progressMap[a.id]!;
                                final progressB = progressMap[b.id]!;
                                final byCompletion = progressB.progress
                                    .compareTo(progressA.progress);
                                if (byCompletion != 0) return byCompletion;
                                return progressA.remaining.compareTo(
                                  progressB.remaining,
                                );
                              });

                        if (lockedBadges.isEmpty) {
                          return _buildBadgeStatusCard(
                            title: 'PROGRESSO DOS TROFÉUS',
                            child: Text(
                              'Todos os troféus disponíveis já foram conquistados.',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }

                        final nextBadge = lockedBadges.first;
                        final nextBadgeProgress = progressMap[nextBadge.id]!;
                        final remainingBadges = lockedBadges.skip(1).toList();

                        return _buildBadgeStatusCard(
                          title: 'PROGRESSO DOS TROFÉUS',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              NextBadgeHighlightCard(
                                badge: nextBadge,
                                progress: nextBadgeProgress,
                              ),
                              if (remainingBadges.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'OUTROS TROFÉUS EM PROGRESSO',
                                  style: GoogleFonts.inter(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...remainingBadges.map((badge) {
                                  final progress = progressMap[badge.id]!;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: BadgeProgressCard(
                                      badge: badge,
                                      progress: progress,
                                      padding: const EdgeInsets.all(14),
                                      borderRadius: 14,
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // ── Turno Actions ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TURNO',
                        style: GoogleFonts.robotoMono(
                          color: _hudCyan.withAlpha(210),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (shiftVM.hasActiveShift) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _isEndingShift
                                ? null
                                : () async {
                                    HapticFeedback.lightImpact();
                                    setState(() => _isEndingShift = true);
                                    await shiftVM.endShift();
                                    if (!context.mounted) return;
                                    setState(() => _isEndingShift = false);
                                    if (shiftVM.error != null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(shiftVM.error!)),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: Text(
                              'Trocar K9 do Turno',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _hudCyan,
                              side: BorderSide(color: _hudCyan.withAlpha(130)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isEndingShift
                              ? null
                              : () async {
                                  HapticFeedback.mediumImpact();
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: _hudPanel,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      title: const Row(
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            color: _hudAmber,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Encerrar Expediente',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: const Text(
                                        'Tem certeza que deseja encerrar o expediente e fazer logout? Todas as suas atividades do dia foram salvas?',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text(
                                            'Cancelar',
                                            style: TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _hudDanger,
                                          ),
                                          child: const Text(
                                            'Sim, Encerrar',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    setState(() => _isEndingShift = true);
                                    await shiftVM.endShift();
                                    if (shiftVM.error != null) {
                                      if (context.mounted) {
                                        setState(() => _isEndingShift = false);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(shiftVM.error!),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    await authVM.signOut();
                                  }
                                },
                          icon: const Icon(Icons.logout_rounded),
                          label: Text(
                            'Encerrar Expediente',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _hudDanger,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadgeStatusCard({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.robotoMono(
            color: _hudCyan.withAlpha(210),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(235),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(65)),
            boxShadow: [
              BoxShadow(color: _hudCyan.withAlpha(20), blurRadius: 18),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(55)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _hudCyan.withAlpha(185), size: 18),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.robotoMono(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
