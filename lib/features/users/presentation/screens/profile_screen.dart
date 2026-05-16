import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/dog_profile_screen.dart';

part 'profile_screen_sections.dart';
part 'profile_hero_widgets.dart';
part 'profile_hero_background.dart';
part 'profile_hero_content.dart';
part 'profile_edit_widgets.dart';
part 'profile_identification_widgets.dart';
part 'profile_shift_section.dart';
part 'profile_info_row.dart';

final _hudBackground = AppTheme.background;
const _hudPanel = const Color(0xFF0E1A1F);
const _hudPanelAlt = Color(0xFF111827);
final _hudCyan = AppTheme.primary;
const _hudAmber = Color(0xFFFBBF24);
const _hudGreen = Color(0xFF00E58A);
final _hudDanger = AppTheme.error;

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _callsignController = TextEditingController();
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
        final unit = userModel?.unit ?? 'GCM Limeira-SP';

        // Sync controllers when entering edit mode for the first time
        if (_isEditMode && _callsignController.text.isEmpty) {
          _callsignController.text = callsign;
          _nameController.text = nameStr;
        }

        return Scaffold(
          backgroundColor: _hudBackground,
          appBar: AppBar(
            backgroundColor: _hudBackground,
            elevation: 0,
            centerTitle: true,
            title: Text(
              'Perfil',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            leading: IconButton(
              icon: Icon(
                _isEditMode ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textPrimary,
                size: 20,
              ),
              onPressed: () {
                if (_isEditMode) {
                  _toggleEditMode(callsign, nameStr);
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            actions: [
              if (!_isEditMode)
                IconButton(
                  icon: Icon(Icons.edit_rounded, color: AppTheme.textSecondary, size: 20),
                  onPressed: () => _toggleEditMode(callsign, nameStr),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // Identity card
                _buildIdentityCard(photoStr, callsign, nameStr, raStr, unit),

                if (_isEditMode) ...[
                  const SizedBox(height: 20),
                  _buildEditSection(userModel, authVM, userVM),
                ] else ...[
                  const SizedBox(height: 20),
                  _buildDogSection(shiftVM),
                  const SizedBox(height: 20),
                  _buildStatsGrid(),
                  const SizedBox(height: 20),
                  _buildConformitySection(shiftVM),
                  const SizedBox(height: 20),
                  _buildSettingsSection(),
                  const SizedBox(height: 20),
                  _buildActionButtons(authVM, shiftVM),
                  const SizedBox(height: 24),
                  // Footer
                  Text(
                    'Canil K9 · $unit · v1.3.0',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Painel glassmorfismo tático universal
  Widget _glassPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    EdgeInsets margin = EdgeInsets.zero,
    Color borderColor = const Color(0xFF1D2C33),
    double borderRadius = 12,
    double sigmaBlur = 12,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigmaBlur, sigmaY: sigmaBlur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: const Color(0xFF0A1216).withAlpha(200),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor.withAlpha(60), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(40),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityCard(
    String? photoStr,
    String callsign,
    String nameStr,
    String raStr,
    String unit,
  ) {
    return _glassPanel(
      padding: const EdgeInsets.all(20),
      borderColor: AppTheme.primary,
      child: Column(
        children: [
          // Avatar
          GestureDetector(
            onTap: _isEditMode ? _pickPhoto : null,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary.withAlpha(100), width: 2.5),
              ),
              child: ClipOval(
                child: _newPhotoFile != null
                    ? Image.file(_newPhotoFile!, fit: BoxFit.cover)
                    : photoStr != null
                        ? CachedNetworkImage(
                            imageUrl: photoStr,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: const Color(0xFF0E1A1F),
                              child: Icon(Icons.person, color: AppTheme.textTertiary, size: 36),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF0E1A1F),
                              child: Icon(Icons.person, color: AppTheme.textTertiary, size: 36),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF0E1A1F),
                            child: Icon(Icons.person, color: AppTheme.textTertiary, size: 36),
                          ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Nome
          Text(
            'GCM $callsign',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'RA $raStr · $unit',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          // Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBadge('CONDUTOR TITULAR', AppTheme.success),
              const SizedBox(width: 8),
              _buildBadge('CANIL K9', AppTheme.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDogSection(ShiftViewModel shiftVM) {
    if (!shiftVM.hasActiveShift) return const SizedBox.shrink();

    final dogVM = Provider.of<DogViewModel>(context);
    final dogId = shiftVM.activeDogId;
    Dog? dog;
    try {
      dog = dogVM.dogs.firstWhere((d) => d.id == dogId);
    } catch (_) {}

    if (dog == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DogProfileScreen(dog: dog!),
          ),
        );
      },
      child: _glassPanel(
        borderColor: AppTheme.success,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.success.withAlpha(100), width: 2),
            ),
            child: ClipOval(
              child: dog.profileImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: dog.profileImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(Icons.pets, color: AppTheme.textTertiary, size: 20),
                    )
                  : Icon(Icons.pets, color: AppTheme.textTertiary, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BINÔMIO ATIVO',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${dog.name} · ${dog.breed}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Operacional · ${dog.specialties?.length ?? 0} especialidades',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 18),
        ],
      ),
      ),
    );
  }

  // ─── Stats Grid 2x2 ─────────────────────────────────────────────

  Widget _buildStatsGrid() {
    // Dados reais virão dos ViewModels — por ora usa contagem local
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);

    final totalOcorrencias = incidentVM.incidents.length;
    final totalTreinos = trainingVM.trainings.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SUA ATUAÇÃO',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(height: 1, color: AppTheme.primary.withAlpha(30)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard('—', 'PLANTÕES', Icons.calendar_today_rounded, _hudCyan),
            const SizedBox(width: 10),
            _buildStatCard('—', 'HORAS', Icons.access_time_rounded, _hudGreen),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildStatCard('$totalOcorrencias', 'OCORRÊNCIAS', Icons.shield_outlined, _hudAmber),
            const SizedBox(width: 10),
            _buildStatCard('$totalTreinos', 'TREINOS', Icons.fitness_center_rounded, _hudCyan),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1216).withAlpha(200),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(40), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(30),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Selos de Conformidade ─────────────────────────────────────────

  Widget _buildConformitySection(ShiftViewModel shiftVM) {
    final dogVM = Provider.of<DogViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    final dogId = shiftVM.activeDogId;
    Dog? dog;
    try {
      dog = dogVM.dogs.firstWhere((d) => d.id == dogId);
    } catch (_) {}

    final seals = _calculateSeals(dog, healthVM, nutritionVM);
    final activeCount = seals.where((s) => s.active).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CONFORMIDADE PROFISSIONAL',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$activeCount de ${seals.length}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Selos institucionais calculados conforme protocolo.',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.8,
          ),
          itemCount: seals.length,
          itemBuilder: (_, i) => _buildSealCard(seals[i]),
        ),
      ],
    );
  }

  Widget _buildSealCard(_Seal seal) {
    final color = seal.active ? AppTheme.success : AppTheme.textTertiary;
    final opacity = seal.active ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1216).withAlpha(180),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(seal.active ? 60 : 25), width: 0.8),
            ),
            child: Row(
              children: [
                Icon(seal.icon, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    seal.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: seal.active ? Colors.white : AppTheme.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_Seal> _calculateSeals(Dog? dog, HealthViewModel healthVM, NutritionViewModel nutritionVM) {
    final now = DateTime.now();

    // Vacinas em dia
    final vaccinesOk = dog?.lastVaccineDate != null &&
        now.difference(dog!.lastVaccineDate!).inDays < 365;

    // Peso monitorado (pesagem nos últimos 30 dias)
    final weightOk = healthVM.healthLogs.any((l) =>
        l.weight != null && now.difference(l.date).inDays <= 30);

    // Conformidade alimentar >= 90%
    final conformityOk = nutritionVM.conformity90d >= 90.0;

    return [
      _Seal(icon: Icons.calendar_today, label: 'Plantões sem lacunas', active: true),
      _Seal(icon: Icons.description_outlined, label: 'Relato final 100%', active: true),
      _Seal(icon: Icons.picture_as_pdf, label: 'PDFs gerados', active: true),
      _Seal(icon: Icons.fitness_center, label: 'Manutenções em dia', active: true),
      _Seal(icon: Icons.menu_book, label: 'Biblioteca atualizada', active: true),
      _Seal(icon: Icons.vaccines, label: 'Vacinas em dia', active: vaccinesOk),
      _Seal(icon: Icons.bug_report_outlined, label: 'Antipulgas em dia', active: vaccinesOk),
      _Seal(icon: Icons.restaurant, label: 'Conformidade alimentar', active: conformityOk),
      _Seal(icon: Icons.monitor_weight, label: 'Peso monitorado', active: weightOk),
      _Seal(icon: Icons.person, label: 'Perfil completo', active: true),
      _Seal(icon: Icons.folder_outlined, label: 'Documentos do cão', active: true),
    ];
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CONFIGURAÇÕES',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(height: 1, color: AppTheme.primary.withAlpha(30)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSettingItem(Icons.notifications_outlined, 'Notificações', 'Alertas e lembretes'),
        _buildSettingItem(Icons.sync_rounded, 'Sincronização', 'Dados offline e backup'),
        _buildSettingItem(Icons.security_rounded, 'Segurança', 'Biometria e senha'),
        _buildSettingItem(Icons.info_outline_rounded, 'Sobre o app', 'Versão e licenças'),
      ],
    );
  }

  Widget _buildSettingItem(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1216).withAlpha(180),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1D2C33).withAlpha(60), width: 0.8),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(AuthViewModel authVM, ShiftViewModel shiftVM) {
    return Column(
      children: [
        // Encerrar Expediente
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isEndingShift
                ? null
                : () async {
                    HapticFeedback.mediumImpact();
                    final confirm = await _showEndShiftDialog();
                    if (confirm == true) {
                      if (!mounted) return;
                      _setEndingShift(true);
                      await shiftVM.endShift();
                      if (shiftVM.error != null) {
                        if (!mounted) return;
                        _setEndingShift(false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(shiftVM.error!)),
                        );
                        return;
                      }
                      await authVM.signOut();
                    }
                  },
            icon: Icon(Icons.logout_rounded, size: 18),
            label: Text(
              'ENCERRAR EXPEDIENTE',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _hudAmber,
              side: BorderSide(color: _hudAmber.withAlpha(100)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Sair do app
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () async {
              HapticFeedback.lightImpact();
              await authVM.signOut();
            },
            icon: Icon(Icons.power_settings_new_rounded, size: 18),
            label: Text(
              'SAIR DO APP',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _hudDanger,
              side: BorderSide(color: _hudDanger.withAlpha(100)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditSection(UserModel? userModel, AuthViewModel authVM, UserViewModel userVM) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EDITAR PERFIL',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Nome',
            labelStyle: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
            prefixIcon: Icon(Icons.person_rounded, color: AppTheme.textTertiary, size: 18),
            filled: true,
            fillColor: const Color(0xFF0E1A1F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: const Color(0xFF1D2C33)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: const Color(0xFF1D2C33)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _callsignController,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Nome de Guerra',
            labelStyle: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
            prefixIcon: Icon(Icons.military_tech_rounded, color: AppTheme.textTertiary, size: 18),
            filled: true,
            fillColor: const Color(0xFF0E1A1F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: const Color(0xFF1D2C33)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: const Color(0xFF1D2C33)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSaving ? null : () => _saveChanges(userModel, authVM, userVM),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: _isSaving
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background))
                : Text('Salvar alterações', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Future<bool?> _showEndShiftDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _hudAmber),
            const SizedBox(width: 8),
            Text(
              'Encerrar Expediente',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Tem certeza que deseja encerrar o expediente e fazer logout?',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _hudDanger),
            child: Text('Sim, Encerrar', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _Seal {
  final IconData icon;
  final String label;
  final bool active;

  const _Seal({required this.icon, required this.label, required this.active});
}
