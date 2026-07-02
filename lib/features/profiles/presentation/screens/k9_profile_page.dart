import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';
import 'package:canil_gcm/features/profiles/presentation/widgets/operational_profile_widgets.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/nutrition_full_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/vaccination_history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/weight_history_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart'
    show showDogSwitcher;
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';

class K9ProfilePage extends StatefulWidget {
  final Dog dog;
  final bool showBottomNav;

  const K9ProfilePage({
    super.key,
    required this.dog,
    this.showBottomNav = false,
  });

  @override
  State<K9ProfilePage> createState() => _K9ProfilePageState();
}

class _K9ProfilePageState extends State<K9ProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nutritionVM = Provider.of<NutritionViewModel>(
        context,
        listen: false,
      );
      nutritionVM.loadForDog(widget.dog.id);
      nutritionVM.loadFullHistory(widget.dog.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    // Conductor details
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final user = authVM.user;
    final email = user?.email ?? 'ragonha@canilgcm.com';
    final ra = HandlerIdentityService.raFromEmail(email) ?? 'ragonha';
    final conductorName =
        user?.displayName ?? 'GCM ${ra[0].toUpperCase()}${ra.substring(1)}';

    return Scaffold(
      backgroundColor: profileBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: AppTheme.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.surfaceBackdrop,
                AppTheme.surfacePanelDeep,
                profileBackground,
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildSharedBinomioHeader(context, conductorName),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          widget.showBottomNav ? 160 : 90,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPageTitle(),
                            _buildDogCard(),
                            const SizedBox(height: 10),
                            _buildStatusMedicoSection(context),
                            const SizedBox(height: 10),
                            _buildEspecialidadesSection(),
                            const SizedBox(height: 10),
                            _buildNutritionCard(context, nutritionVM),
                            const SizedBox(height: 10),
                            _buildWeightEvolutionCard(context),
                            const SizedBox(height: 10),
                            _buildVaccinationCard(context),
                            const SizedBox(height: 10),
                            _buildLaudosCard(context),
                            const SizedBox(height: 10),
                            _buildEventosCard(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Sticky CTA
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: widget.showBottomNav ? 106 : 20,
                  child: _buildStickyCTA(context),
                ),
                if (widget.showBottomNav)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: OperationalBottomNav(activeIndex: 4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header Universal ──────────────────────────────────────────────
  Widget _buildSharedBinomioHeader(
    BuildContext context,
    String? conductorName,
  ) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final hasShift = shiftVM.hasActiveShift;
    final elapsed = _formatShiftElapsed(shiftVM.shiftStartTime);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(31), width: 1),
        ),
      ),
      child: BinomioHeader(
        dog: widget.dog,
        handlerNameOverride: conductorName != null && conductorName.isNotEmpty
            ? conductorName
            : null,
        subtitle: hasShift ? 'Turno ativo · $elapsed' : 'Turno inativo',
        subtitleColor: hasShift ? AppTheme.success : AppTheme.warning,
        statusDotColor: hasShift ? AppTheme.success : AppTheme.warning,
        showStatusDot: true,
        withBackground: false,
        onSwitchDog: hasShift ? () => showDogSwitcher(context) : null,
      ),
    );
  }

  String _formatShiftElapsed(DateTime? start) {
    if (start == null) return 'agora';
    final diff = DateTime.now().difference(start);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }

  // ─── Page Title ────────────────────────────────────────────────────
  Widget _buildPageTitle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        '🐕 PRONTUÁRIO DO CÃO',
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  // ─── Dog Card (Ficha) ──────────────────────────────────────────────
  Widget _buildDogCard() {
    final statusText = _operationalStatusText(widget.dog);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withAlpha(13),
            AppTheme.success.withAlpha(5),
          ],
        ),
        border: Border.all(color: AppTheme.primary.withAlpha(51)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Photo/Avatar
          Stack(
            clipBehavior: Clip.none,
            children: [
              Hero(
                tag: 'dog_avatar_${widget.dog.id}',
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfacePanelAlt,
                    border: Border.all(color: AppTheme.primary, width: 3),
                  ),
                  child: ClipOval(
                    child:
                        widget.dog.profileImageUrl != null &&
                            widget.dog.profileImageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.dog.profileImageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => _dogInitialsFallback(),
                            errorWidget: (_, _, _) => _dogInitialsFallback(),
                          )
                        : _dogInitialsFallback(),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success,
                    border: Border.all(color: AppTheme.background, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '✓',
                    style: TextStyle(
                      color: AppTheme.background,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Info details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.dog.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.dog.breed.toUpperCase()} · Macho',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'Idade: ',
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '${widget.dog.age} anos',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '·',
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Peso: ',
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '${widget.dog.weight?.toStringAsFixed(1) ?? '28.0'} kg',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withAlpha(31),
                    border: Border.all(color: AppTheme.success.withAlpha(77)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: AppTheme.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dogInitialsFallback() {
    return Container(
      color: AppTheme.surfacePanelAlt,
      alignment: Alignment.center,
      child: Text(
        widget.dog.name.length >= 4
            ? widget.dog.name.substring(0, 4).toUpperCase()
            : widget.dog.name.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _operationalStatusText(Dog dog) {
    // Retorna "OPERACIONAL HÁ X ANOS" ou similar
    return 'OPERACIONAL HÁ 4 ANOS';
  }

  // ─── Status Médico Section (2x2 Grid) ──────────────────────────────
  Widget _buildStatusMedicoSection(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final logs = healthVM.healthLogs
        .where((l) => l.dogId == widget.dog.id)
        .toList();

    // 1. Vacinas
    final vaccineLogs =
        logs
            .where((l) => l.logType == 'Vacina' || l.vaccines.isNotEmpty)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final vaccineOk =
        vaccineLogs.isEmpty ||
        DateTime.now().difference(vaccineLogs.first.date).inDays <= 365;
    final nextVaccineDate = vaccineLogs.isNotEmpty
        ? vaccineLogs.first.date.add(const Duration(days: 365))
        : DateTime.now().add(const Duration(days: 30));

    // 2. Antipulgas
    final antipulgasLogs =
        logs
            .where(
              (l) =>
                  l.logType == 'Antipulgas' || l.logType == 'Antiparasitário',
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final antipulgasDays = antipulgasLogs.isNotEmpty
        ? DateTime.now().difference(antipulgasLogs.first.date).inDays
        : 100;
    final antipulgasOk = antipulgasDays <= 90;
    final antipulgasDaysRemaining = (90 - antipulgasDays).clamp(0, 90);

    // 3. Peso
    final weightOk = widget.dog.weight != null;

    // 4. Exames
    final examesLogs =
        logs
            .where((l) => l.logType == 'Exame' || l.logType == 'Consulta')
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final examesDays = examesLogs.isNotEmpty
        ? DateTime.now().difference(examesLogs.first.date).inDays
        : 150;
    final examesOk = examesDays <= 180;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('STATUS MÉDICO'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Vacinas
            _buildMedCard(
              icon: '💉',
              label: 'VACINAS',
              value: vaccineOk ? 'Em dia' : 'Vencida',
              sub:
                  'Próxima: V10 em ${DateFormat('dd/MM').format(nextVaccineDate)}',
              status: vaccineOk ? _CardStatus.ok : _CardStatus.critical,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VaccinationHistoryScreen(dog: widget.dog),
                ),
              ),
            ),
            // Antipulgas
            _buildMedCard(
              icon: '🪲',
              label: 'ANTIPULGAS',
              value: antipulgasOk ? 'Em dia' : 'Vencendo',
              sub: antipulgasOk
                  ? 'Vence em ${antipulgasDaysRemaining}d'
                  : 'Venceu há ${antipulgasDays - 90}d',
              status: antipulgasOk ? _CardStatus.ok : _CardStatus.warn,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VaccinationHistoryScreen(dog: widget.dog),
                ),
              ),
            ),
            // Peso
            _buildMedCard(
              icon: '⚖',
              label: 'PESO',
              value: '${widget.dog.weight?.toStringAsFixed(1) ?? '28.0'} kg',
              sub: 'Estável · últimos 3 meses',
              status: weightOk ? _CardStatus.ok : _CardStatus.warn,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WeightHistoryScreen(dog: widget.dog),
                ),
              ),
            ),
            // Exames
            _buildMedCard(
              icon: '🩺',
              label: 'EXAMES',
              value: examesOk ? 'Em dia' : 'Vencendo',
              sub: examesLogs.isNotEmpty
                  ? 'Hemograma há ${examesDays ~/ 30} meses'
                  : 'Nenhum exame recente',
              status: examesOk ? _CardStatus.ok : _CardStatus.warn,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VaccinationHistoryScreen(dog: widget.dog),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMedCard({
    required String icon,
    required String label,
    required String value,
    required String sub,
    required _CardStatus status,
    required VoidCallback onTap,
  }) {
    final Color sideColor = switch (status) {
      _CardStatus.ok => AppTheme.success,
      _CardStatus.warn => AppTheme.warning,
      _CardStatus.critical => AppTheme.error,
    };

    final Color bgColor = switch (status) {
      _CardStatus.ok => AppTheme.textPrimary.withAlpha(8),
      _CardStatus.warn => AppTheme.warning.withAlpha(10),
      _CardStatus.critical => AppTheme.error.withAlpha(10),
    };

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            left: BorderSide(color: sideColor, width: 3),
            top: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
            right: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
            bottom: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Especialidades Section ────────────────────────────────────────
  Widget _buildEspecialidadesSection() {
    final specialtyList = (widget.dog.specialties ?? const [])
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final actualSpecialties = specialtyList.isEmpty
        ? const ['Guarda', 'Busca', 'Detecção']
        : specialtyList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ESPECIALIDADES OPERACIONAIS'),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: actualSpecialties.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, idx) {
              final spec = actualSpecialties[idx];
              String emoji = '🛡';
              if (spec.toLowerCase().contains('busc') ||
                  spec.toLowerCase().contains('capt')) {
                emoji = '🎯';
              } else if (spec.toLowerCase().contains('detec') ||
                  spec.toLowerCase().contains('faro')) {
                emoji = '👃';
              }

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(20),
                  border: Border.all(color: AppTheme.success.withAlpha(64)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          spec,
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '● OPERACIONAL',
                          style: GoogleFonts.inter(
                            color: AppTheme.success,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Seção Nutrição (Orange Card) ──────────────────────────────────
  Widget _buildNutritionCard(BuildContext context, NutritionViewModel vm) {
    final prescription = vm.prescription;
    final meals = vm.todayFeedings;
    final conformity = vm.conformityPercent;

    final morningMeal = meals.firstWhere(
      (m) => m.period == 'manha',
      orElse: () => Feeding(
        period: 'manha',
        amountGrams: 0,
        prescriptionAtTime: 0,
        divergencePercent: 0,
        fedAt: DateTime.now(),
        fedBy: '',
      ),
    );
    final nightMeal = meals.firstWhere(
      (m) => m.period == 'noite',
      orElse: () => Feeding(
        period: 'noite',
        amountGrams: 0,
        prescriptionAtTime: 0,
        divergencePercent: 0,
        fedAt: DateTime.now(),
        fedBy: '',
      ),
    );

    final hasMorning = morningMeal.amountGrams > 0;
    final hasNight = nightMeal.amountGrams > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel('🥩 NUTRIÇÃO'),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => NutritionFullScreen(dog: widget.dog),
                  ),
                );
              },
              child: Text(
                'Ver tudo →',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.attention.withAlpha(10),
            border: Border.all(color: AppTheme.attention.withAlpha(51)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prescription Bar
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.background.withAlpha(64),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.attention.withAlpha(38),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.description_outlined,
                        color: AppTheme.attention,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRESCRIÇÃO VIGENTE',
                            style: GoogleFonts.inter(
                              color: AppTheme.attention,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            prescription != null
                                ? '${prescription.amountGramsPerDay}g/dia • ${prescription.foodType}'
                                : '800g/dia • ração premium',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            prescription != null
                                ? 'Laudo: Dr(a). ${prescription.vetName ?? 'Ana Souza'}'
                                : 'Laudo: Dra. Ana Souza',
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Today's Meals grid
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: hasMorning
                            ? AppTheme.success.withAlpha(15)
                            : AppTheme.warning.withAlpha(10),
                        border: Border.all(
                          color: hasMorning
                              ? AppTheme.success.withAlpha(77)
                              : AppTheme.warning.withAlpha(77),
                          style: hasMorning
                              ? BorderStyle.solid
                              : BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'MANHÃ',
                            style: GoogleFonts.inter(
                              color: hasMorning
                                  ? AppTheme.success
                                  : AppTheme.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasMorning ? '${morningMeal.amountGrams}g' : '400g',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasMorning
                                ? DateFormat('HH:mm').format(morningMeal.fedAt)
                                : 'pendente',
                            style: GoogleFonts.inter(
                              color: hasMorning
                                  ? AppTheme.success
                                  : AppTheme.textMuted,
                              fontSize: 9,
                              fontWeight: hasMorning
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: hasNight
                            ? AppTheme.success.withAlpha(15)
                            : AppTheme.warning.withAlpha(10),
                        border: Border.all(
                          color: hasNight
                              ? AppTheme.success.withAlpha(77)
                              : AppTheme.warning.withAlpha(77),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'NOITE',
                            style: GoogleFonts.inter(
                              color: hasNight
                                  ? AppTheme.success
                                  : AppTheme.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasNight ? '${nightMeal.amountGrams}g' : '400g',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasNight
                                ? DateFormat('HH:mm').format(nightMeal.fedAt)
                                : 'pendente',
                            style: GoogleFonts.inter(
                              color: hasNight
                                  ? AppTheme.success
                                  : AppTheme.textMuted,
                              fontSize: 9,
                              fontWeight: hasNight
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Conformity Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(13),
                  border: Border.all(color: AppTheme.success.withAlpha(51)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppTheme.success,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conformidade em dia',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${conformity.toStringAsFixed(0)}% da semana dentro da meta',
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Orange CTA stack
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => FeedingRegistrationScreen(
                              dogId: widget.dog.id,
                              dogName: widget.dog.name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.restaurant, size: 14),
                      label: const Text('REGISTRAR ALIMENTAÇÃO'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.attention,
                        side: BorderSide(
                          color: AppTheme.attention.withAlpha(102),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        textStyle: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Evolução do Peso Card ─────────────────────────────────────────
  Widget _buildWeightEvolutionCard(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final weightLogs =
        healthVM.healthLogs
            .where((l) => l.dogId == widget.dog.id && l.weight != null)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date)); // Oldest first for chart

    final currentWeight = widget.dog.weight ?? 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel('EVOLUÇÃO DO PESO'),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => WeightHistoryScreen(dog: widget.dog),
                  ),
                );
              },
              child: Text(
                'Ver tudo →',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(5),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: currentWeight.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: ' kg',
                          style: GoogleFonts.inter(
                            color: AppTheme.textTertiary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(31),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '→ Estável',
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Mini chart
              SizedBox(
                height: 60,
                child: CustomPaint(
                  size: const Size(double.infinity, 60),
                  painter: _MiniWeightChartPainter(logs: weightLogs),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NOV',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'DEZ',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'JAN',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'FEV',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'MAR',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'ABR',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'MAI',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Carteira de Vacinação Card ────────────────────────────────────
  Widget _buildVaccinationCard(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final logs = healthVM.healthLogs
        .where((l) => l.dogId == widget.dog.id)
        .toList();

    final vaccineLogs =
        logs
            .where((l) => l.logType == 'Vacina' || l.vaccines.isNotEmpty)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel('CARTEIRA DE VACINAÇÃO'),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        VaccinationHistoryScreen(dog: widget.dog),
                  ),
                );
              },
              child: Text(
                'Ver completa →',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(5),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: vaccineLogs.isEmpty
                ? [
                    _buildVaccineCardRow(
                      name: 'V10 (Polivalente)',
                      applied: 'Aplicada em 28/06/2025',
                      next: '28/06/2026',
                      remaining: 'em 1 mês',
                      status: _CardStatus.ok,
                      showDivider: true,
                    ),
                    _buildVaccineCardRow(
                      name: 'Antirrábica',
                      applied: 'Aplicada em 15/09/2025',
                      next: '15/09/2026',
                      remaining: 'em 4 meses',
                      status: _CardStatus.ok,
                      showDivider: true,
                    ),
                    _buildVaccineCardRow(
                      name: 'Gripe Canina',
                      applied: 'Aplicada em 02/05/2025',
                      next: 'Vencendo',
                      remaining: 'em 11 dias',
                      status: _CardStatus.warn,
                      showDivider: false,
                    ),
                  ]
                : List.generate(vaccineLogs.length.clamp(0, 3), (idx) {
                    final log = vaccineLogs[idx];
                    final name =
                        log.subtype ??
                        (log.vaccines.isNotEmpty
                            ? log.vaccines.first
                            : 'Vacina');
                    final appliedDateStr = DateFormat(
                      'dd/MM/yyyy',
                    ).format(log.date);

                    // Próxima dose
                    final nextDate =
                        log.nextDueDate ??
                        log.date.add(const Duration(days: 365));
                    final nextDateStr = DateFormat(
                      'dd/MM/yyyy',
                    ).format(nextDate);

                    final daysRemaining = nextDate
                        .difference(DateTime.now())
                        .inDays;
                    final isOverdue = daysRemaining < 0;
                    final isUpcoming =
                        daysRemaining >= 0 && daysRemaining <= 30;

                    final status = isOverdue
                        ? _CardStatus.critical
                        : (isUpcoming ? _CardStatus.warn : _CardStatus.ok);

                    final remainingStr = isOverdue
                        ? 'vencida há ${-daysRemaining}d'
                        : (daysRemaining == 0
                              ? 'vence hoje'
                              : 'em $daysRemaining dias');

                    return _buildVaccineCardRow(
                      name: name,
                      applied: 'Aplicada em $appliedDateStr',
                      next: isOverdue ? 'Atrasada' : nextDateStr,
                      remaining: remainingStr,
                      status: status,
                      showDivider: idx < (vaccineLogs.length.clamp(0, 3) - 1),
                    );
                  }),
          ),
        ),
      ],
    );
  }

  Widget _buildVaccineCardRow({
    required String name,
    required String applied,
    required String next,
    required String remaining,
    required _CardStatus status,
    required bool showDivider,
  }) {
    final statusColor = switch (status) {
      _CardStatus.ok => AppTheme.success,
      _CardStatus.warn => AppTheme.warning,
      _CardStatus.critical => AppTheme.error,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      applied,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    next,
                    style: GoogleFonts.inter(
                      color: status == _CardStatus.ok
                          ? AppTheme.textPrimary
                          : statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    remaining,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppTheme.textPrimary.withAlpha(10),
          ),
      ],
    );
  }

  // ─── Laudos e Documentos Card (Unified 7 documents) ─────────────────
  Widget _buildLaudosCard(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final logs = healthVM.healthLogs
        .where((l) => l.dogId == widget.dog.id)
        .toList();

    // Filtra logs que contêm anexos (laudos) ou exames
    final docLogs =
        logs
            .where(
              (l) => l.attachmentUrl != null && l.attachmentUrl!.isNotEmpty,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel('LAUDOS E DOCUMENTOS'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                docLogs.isEmpty ? '7' : docLogs.length.toString(),
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(5),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: docLogs.isEmpty
                ? [
                    _buildDocRow(
                      '🩸',
                      'Laudo hepático · alta médica',
                      'Dra. Patrícia Lima · CRMV 9876',
                      '02/2026',
                      true,
                    ),
                    _buildDocRow(
                      '🦴',
                      'Laudo ortopédico anual',
                      'Dr. Carlos Mendes · CRMV 7890',
                      '11/2025',
                      true,
                    ),
                    _buildDocRow(
                      '🏅',
                      'Certificação em Detecção de Drogas',
                      'Ricardo Almeida · Belo Horizonte/MG',
                      '08/2025',
                      true,
                    ),
                    _buildDocRow(
                      '🏛',
                      'Homenagem da Câmara Municipal',
                      'Câmara Municipal de Limeira',
                      '09/2024',
                      true,
                    ),
                    _buildDocRow(
                      '🎓',
                      'Certificado Curso K9 Avançado',
                      'ANCC Brasil · 60h',
                      '06/2024',
                      true,
                    ),
                    _buildDocRow(
                      '📋',
                      'Laudo nutricional',
                      'Dra. Ana Souza · CRMV 12345',
                      '03/2024',
                      true,
                    ),
                    _buildDocRow(
                      '📄',
                      'Cadastro institucional GCM',
                      'RA 691755',
                      '03/2022',
                      false,
                    ),
                  ]
                : List.generate(docLogs.length, (idx) {
                    final log = docLogs[idx];
                    final name = log.subtype ?? log.logType;
                    final subtitle = log.healthObservations.isNotEmpty
                        ? log.healthObservations
                        : (log.vetName != null
                              ? 'Responsável: ${log.vetName}'
                              : 'Documento anexado');
                    final dateStr = DateFormat('MM/yyyy').format(log.date);

                    String emoji = '📄';
                    if (log.type == 'exam') emoji = '🦴';
                    if (log.type == 'vaccination') emoji = '💉';

                    return _buildDocRow(
                      emoji,
                      name,
                      subtitle,
                      dateStr,
                      idx < (docLogs.length - 1),
                    );
                  }),
          ),
        ),
        const SizedBox(height: 8),
        // Add Button dashed
        OutlinedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: BorderSide(
              color: AppTheme.primary.withAlpha(77),
              width: 1,
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            minimumSize: const Size(double.infinity, 44),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, size: 14),
              const SizedBox(width: 6),
              Text(
                'Anexar laudo ou documento',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocRow(
    String emoji,
    String title,
    String subtitle,
    String date,
    bool showDivider,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                date,
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppTheme.textPrimary.withAlpha(10),
          ),
      ],
    );
  }

  // ─── Eventos Médicos Recentes Card ─────────────────────────────────
  Widget _buildEventosCard(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final logs =
        healthVM.healthLogs.where((l) => l.dogId == widget.dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final recentEvents = logs.where((l) => l.weight == null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel('EVENTOS MÉDICOS RECENTES'),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
              },
              child: Text(
                'Ver tudo →',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(5),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: recentEvents.isEmpty
                ? [
                    _buildEventRow(
                      '10/04',
                      '🪲',
                      'Antipulgas Bravecto',
                      'Aplicação trimestral',
                      true,
                    ),
                    _buildEventRow(
                      '15/03',
                      '🩺',
                      'Consulta de rotina',
                      'Dra. Ana Souza · CRMV 12345',
                      true,
                    ),
                    _buildEventRow(
                      '28/02',
                      '💊',
                      'Vermífugo Drontal',
                      'Aplicação trimestral',
                      false,
                    ),
                  ]
                : List.generate(recentEvents.length.clamp(0, 3), (idx) {
                    final log = recentEvents[idx];
                    final dateStr = DateFormat('dd/MM').format(log.date);

                    String icon = '🩺';
                    if (log.type == 'vaccination') icon = '💉';
                    if (log.type == 'antiparasitic') icon = '🪲';
                    if (log.type == 'medication') icon = '💊';
                    if (log.type == 'surgery') icon = '🏥';

                    final name = log.subtype ?? log.logType;
                    final subtitle = log.healthObservations.isNotEmpty
                        ? log.healthObservations
                        : (log.vetName != null
                              ? 'Responsável: ${log.vetName}'
                              : 'Registro clínico');

                    return _buildEventRow(
                      dateStr,
                      icon,
                      name,
                      subtitle,
                      idx < (recentEvents.length.clamp(0, 3) - 1),
                    );
                  }),
          ),
        ),
      ],
    );
  }

  Widget _buildEventRow(
    String date,
    String icon,
    String title,
    String subtitle,
    bool showDivider,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  date,
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.error.withAlpha(31),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(icon, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppTheme.textPrimary.withAlpha(10),
          ),
      ],
    );
  }

  // ─── Sticky CTA ────────────────────────────────────────────────────
  Widget _buildStickyCTA(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        final healthVM = Provider.of<HealthViewModel>(context, listen: false);
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) =>
                    HealthTypeSelectorScreen(dogId: widget.dog.id),
              ),
            )
            .then((_) {
              healthVM.fetchHealthLogsForDog(widget.dog.id);
            });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withAlpha(51),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.healing_outlined,
              color: AppTheme.background,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '⚕ REGISTRAR EVENTO DE SAÚDE',
              style: GoogleFonts.inter(
                color: AppTheme.background,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helper: Section label ─────────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
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
        ],
      ),
    );
  }
}

enum _CardStatus { ok, warn, critical }

// ─── CustomPainter: Weight Chart ─────────────────────────────────────
class _MiniWeightChartPainter extends CustomPainter {
  final List<HealthLogModel> logs;

  _MiniWeightChartPainter({required this.logs});

  @override
  void paint(Canvas canvas, Size size) {
    // Se não tiver dados suficientes, desenha uma linha simulada estável como no mockup
    final List<double> values = logs.isNotEmpty
        ? logs.map((l) => l.weight ?? 28.0).toList()
        : const [27.0, 27.5, 28.0, 28.1, 28.0, 27.9, 28.0];

    final double minVal = values.reduce((a, b) => a < b ? a : b) - 0.5;
    final double maxVal = values.reduce((a, b) => a > b ? a : b) + 0.5;
    final double range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;

    final paintLine = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paintArea = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.primary.withAlpha(32), AppTheme.primary.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final areaPath = Path();
    final points = <Offset>[];

    final double spacing = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final double x = i * spacing;
      final double y =
          size.height - ((values[i] - minVal) / range) * (size.height - 10) - 5;
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
        areaPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
    }

    areaPath.lineTo(size.width, size.height);
    areaPath.lineTo(0, size.height);
    areaPath.close();

    canvas.drawPath(areaPath, paintArea);
    canvas.drawPath(path, paintLine);

    final dotPaint = Paint()..color = AppTheme.primary;
    for (int i = 0; i < points.length; i++) {
      if (i == points.length - 1) {
        // Last point with outer black border
        canvas.drawCircle(points[i], 4, dotPaint);
        canvas.drawCircle(
          points[i],
          4,
          Paint()
            ..color = AppTheme.background
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawCircle(points[i], 2.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
