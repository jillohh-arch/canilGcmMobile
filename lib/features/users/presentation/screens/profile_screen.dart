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

part 'profile_screen_sections.dart';
part 'profile_hero_widgets.dart';
part 'profile_edit_widgets.dart';
part 'profile_identification_widgets.dart';
part 'profile_gamification_sections.dart';
part 'profile_shift_section.dart';

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

  void _toggleEditMode(String callsign, String nameStr) {
    setState(() {
      _isEditMode = !_isEditMode;
      _callsignController.text = callsign;
      _nameController.text = nameStr;
      if (!_isEditMode) {
        _newPhotoFile = null;
      }
    });
  }

  void _setEndingShift(bool value) {
    if (!mounted) return;
    setState(() => _isEndingShift = value);
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
              _buildProfileHeroSliver(
                photoStr: photoStr,
                callsign: callsign,
                nameStr: nameStr,
                raStr: raStr,
                level: level,
                xp: xp,
              ),
              if (_isEditMode)
                _buildProfileEditSliver(
                  raStr: raStr,
                  userModel: userModel,
                  authVM: authVM,
                  userVM: userVM,
                ),
              _buildIdentificationSliver(
                callsign: callsign,
                nameStr: nameStr,
                raStr: raStr,
                userModel: userModel,
              ),
              _buildTacticalEvolutionSliver(levelProgress),
              if (userModel != null) _buildBadgeGallerySliver(userModel),
              if (userModel != null && _badgeProgressFuture != null)
                _buildBadgeProgressSliver(userModel),
              _buildShiftActionsSliver(authVM: authVM, shiftVM: shiftVM),
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
