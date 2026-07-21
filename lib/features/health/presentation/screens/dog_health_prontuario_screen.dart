import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:canil_gcm/core/services/pdf_attachment_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/data/dog_profile_service.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/data/health_service.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/nutrition/data/nutrition_ai_service.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_supplement.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/domain/training_model.dart';

class DogHealthProntuarioScreen extends StatefulWidget {
  final String dogId;

  const DogHealthProntuarioScreen({super.key, required this.dogId});

  @override
  State<DogHealthProntuarioScreen> createState() =>
      _DogHealthProntuarioScreenState();
}

class _DogHealthProntuarioScreenState extends State<DogHealthProntuarioScreen> {
  final DogService _dogService = DogService();
  final HealthService _healthService = HealthService();
  final DogProfileService _profileService = DogProfileService();
  final WeightHistoryService _weightHistoryService = WeightHistoryService();

  Stream<Dog?>? _dogStream;
  Future<_HealthProntuarioData>? _dataFuture;
  bool _uploadingDocument = false;
  _HealthProntuarioTab _selectedTab = _HealthProntuarioTab.resumo;
  String? _lastNutritionDogId;

  @override
  void initState() {
    super.initState();
    _bind(widget.dogId);
  }

  @override
  void didUpdateWidget(covariant DogHealthProntuarioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dogId != widget.dogId) {
      _bind(widget.dogId);
    }
  }

  void _bind(String dogId) {
    _dogStream = _dogService.watchDog(dogId);
    _dataFuture = _loadData(dogId);
  }

  Future<_HealthProntuarioData> _loadData(String dogId) async {
    final results = await Future.wait([
      _healthService.getHealthLogsForDog(dogId),
      _profileService.getDocuments(dogId),
      _weightHistoryService.getHistory(dogId, limit: 20),
    ]);
    return _HealthProntuarioData(
      logs: results[0] as List<HealthLogModel>,
      documents: results[1] as List<DogDocument>,
      weightRecords: results[2] as List<WeightRecord>,
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData(widget.dogId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dogVM = Provider.of<DogViewModel>(context);

    return StreamBuilder<Dog?>(
      stream: _dogStream,
      builder: (context, dogSnapshot) {
        final dog = dogSnapshot.data ?? _dogFallback(dogVM, widget.dogId);
        if (dog == null) {
          return const _HealthEmptyState(
            message: 'Cão não encontrado.\nVerifique o turno ativo.',
          );
        }
        _ensureNutritionLoaded(dog.id);

        return FutureBuilder<_HealthProntuarioData>(
          future: _dataFuture,
          builder: (context, dataSnapshot) {
            final data = dataSnapshot.data;
            final loading =
                dataSnapshot.connectionState == ConnectionState.waiting &&
                data == null;

            return Scaffold(
              backgroundColor: AppTheme.background,
              body: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: AppTheme.transparent,
                  systemNavigationBarColor: AppTheme.surfaceNavigation,
                  systemNavigationBarIconBrightness: Brightness.light,
                ),
                child: _HealthProntuarioBody(
                  dog: dog,
                  data: data ?? _HealthProntuarioData.empty(),
                  loading: loading,
                  uploadingDocument: _uploadingDocument,
                  selectedTab: _selectedTab,
                  onTabSelected: (tab) => setState(() => _selectedTab = tab),
                  onRefresh: _refresh,
                  onOpenHealthHub: () => _openHealthActionHub(dog),
                  onOpenUnifiedHistory: _openUnifiedHistory,
                  onAttachDocument: () {
                    _attachDocument(dog);
                  },
                  onOpenDocument: _openDocument,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Dog? _dogFallback(DogViewModel dogVM, String dogId) {
    try {
      return dogVM.dogs.firstWhere((dog) => dog.id == dogId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openHealthActionHub(Dog dog) async {
    final latestWeight = (await _dataFuture)?.latestWeight ?? dog.weight;
    if (!mounted) return;
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => HealthTypeSelectorScreen(
          dogId: dog.id,
          dogName: dog.name,
          dogBreed: dog.breed,
          dogAgeYears: _dogAgeYears(dog),
          currentWeightKg: latestWeight,
          dogImageUrl: dog.profileImageUrl,
          handlerName: 'Ragonha',
          onRegisterWeight: (hubContext) =>
              _openWeightRegistration(dog, hostContext: hubContext),
          onRegisterNutrition: (hubContext) =>
              _openFeedingRegistration(dog, hostContext: hubContext),
          onAttachDocument: (hubContext) =>
              _attachDocument(dog, hostContext: hubContext),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) _refresh();
  }

  int _dogAgeYears(Dog dog) {
    final now = DateTime.now();
    var years = now.year - dog.dateOfBirth.year;
    final hadBirthday =
        now.month > dog.dateOfBirth.month ||
        (now.month == dog.dateOfBirth.month && now.day >= dog.dateOfBirth.day);
    if (!hadBirthday) years--;
    return years < 0 ? 0 : years;
  }

  Future<bool> _openWeightRegistration(
    Dog dog, {
    BuildContext? hostContext,
  }) async {
    final latest = (await _dataFuture)?.latestWeight ?? dog.weight ?? 25.0;
    if (!mounted) return false;
    final saved = await showModalBottomSheet<bool>(
      context: hostContext ?? context,
      isScrollControlled: true,
      backgroundColor: AppTheme.transparent,
      builder: (_) => _WeightRegistrationSheet(
        initialWeight: latest,
        onSave: (weight, notes) async {
          final user = FirebaseAuth.instance.currentUser;
          await _weightHistoryService.addRecord(
            dog.id,
            WeightRecord(
              weightKg: weight,
              measuredAt: DateTime.now(),
              measuredBy: user?.uid ?? user?.email ?? 'unknown',
              context: 'canil',
              notes: notes,
            ),
          );
        },
      ),
    );
    if (!mounted) return saved == true;
    if (saved == true) _refresh();
    return saved == true;
  }

  Future<bool> _openFeedingRegistration(
    Dog dog, {
    BuildContext? hostContext,
    HealthNutritionMutationController? mutationControllerOverride,
  }) async {
    final controller = mutationControllerOverride ??
        HealthNutritionMutationController(
          gateway: FirebaseFunctionsHealthNutritionMutationGateway(),
        );
    final outcome =
        await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
          context: hostContext ?? context,
          isScrollControlled: true,
          backgroundColor: AppTheme.surfacePanel,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => HealthAdhocMealFormSheet(
            dogId: dog.id,
            dogDisplayName: dog.name,
            controller: controller,
            onRefreshRequested: () async {
              final nutritionVM = Provider.of<NutritionViewModel>(
                context,
                listen: false,
              );
              await nutritionVM.loadForDog(dog.id, forceReload: true);
              await nutritionVM.loadFullHistory(dog.id);
              _refresh();
            },
          ),
        );
    if (mutationControllerOverride == null) {
      controller.dispose();
    }
    if (!mounted) return outcome is HealthNutritionMutationUiSuccess;
    if (outcome is HealthNutritionMutationUiSuccess) {
      final nutritionVM = Provider.of<NutritionViewModel>(
        context,
        listen: false,
      );
      await nutritionVM.loadForDog(dog.id, forceReload: true);
      await nutritionVM.loadFullHistory(dog.id);
      _refresh();
      return true;
    }
    return false;
  }

  Future<void> _openUnifiedHistory() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            const HistoryScreen(mode: HistoryScreenMode.healthProntuario),
      ),
    );
  }

  void _ensureNutritionLoaded(String dogId) {
    if (_lastNutritionDogId == dogId) return;
    _lastNutritionDogId = dogId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nutritionVM = Provider.of<NutritionViewModel>(
        context,
        listen: false,
      );
      nutritionVM.loadForDog(dogId, forceReload: true);
      nutritionVM.loadFullHistory(dogId);
    });
  }

  Future<bool> _attachDocument(Dog dog, {BuildContext? hostContext}) async {
    final result = await showModalBottomSheet<_DocumentUploadDraft>(
      context: hostContext ?? context,
      isScrollControlled: true,
      backgroundColor: AppTheme.transparent,
      builder: (_) => _DocumentUploadSheet(dogName: dog.name),
    );
    if (result == null) return false;

    setState(() => _uploadingDocument = true);
    try {
      await _profileService.uploadDocument(
        dogId: dog.id,
        nome: result.name,
        descricao: result.description,
        tipo: result.type,
        file: result.file,
        emissor: result.issuer,
      );
      if (!mounted) return false;
      _refresh();
      AppFeedback.success(context, 'Laudo anexado ao prontuário.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      AppFeedback.error(
        context,
        e,
        fallback: 'Não foi possível anexar o laudo.',
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _uploadingDocument = false);
      }
    }
  }

  Future<void> _openDocument(_ProntuarioDocumentItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null) {
      AppFeedback.warning(context, 'URL do documento inválida.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) {
      AppFeedback.warning(context, 'Não foi possível abrir o documento.');
    }
  }
}

enum _HealthProntuarioTab { resumo, vacinas, peso, nutricao, docs }

class _HealthProntuarioBody extends StatelessWidget {
  final Dog dog;
  final _HealthProntuarioData data;
  final bool loading;
  final bool uploadingDocument;
  final _HealthProntuarioTab selectedTab;
  final ValueChanged<_HealthProntuarioTab> onTabSelected;
  final VoidCallback onRefresh;
  final VoidCallback onOpenHealthHub;
  final VoidCallback onOpenUnifiedHistory;
  final VoidCallback onAttachDocument;
  final ValueChanged<_ProntuarioDocumentItem> onOpenDocument;

  const _HealthProntuarioBody({
    required this.dog,
    required this.data,
    required this.loading,
    required this.uploadingDocument,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onRefresh,
    required this.onOpenHealthHub,
    required this.onOpenUnifiedHistory,
    required this.onAttachDocument,
    required this.onOpenDocument,
  });

  @override
  Widget build(BuildContext context) {
    final elapsedText = _shiftElapsedText(context);
    final documents = data.documentItems;
    final tabContent = _buildTabContent(context, documents);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surfacePanelStrong,
            AppTheme.background,
            AppTheme.background,
          ],
        ),
      ),
      child: SafeArea(
        top: true,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              decoration: const BoxDecoration(
                color: AppTheme.primaryOverlay,
                border: Border(
                  bottom: BorderSide(color: AppTheme.primaryDivider, width: 1),
                ),
              ),
              child: BinomioHeader(
                dog: dog,
                subtitle: 'Turno ativo$elapsedText',
                subtitleColor: AppTheme.success,
                showStatusDot: true,
                statusDotColor: AppTheme.success,
                withBackground: false,
                showProfileButton: true,
                onSwitchDog: () => showDogSwitcher(context),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () async => onRefresh(),
                    color: AppTheme.primary,
                    backgroundColor: AppTheme.surfacePanel,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PageTitle(loading: loading),
                          const SizedBox(height: 12),
                          _DogIdentityCard(
                            dog: dog,
                            latestWeight: data.latestWeight ?? dog.weight,
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(title: 'STATUS MÉDICO'),
                          const SizedBox(height: 10),
                          _QuickStatusRow(dog: dog, data: data),
                          const SizedBox(height: 16),
                          _HealthTabSelector(
                            selected: selectedTab,
                            onSelected: onTabSelected,
                          ),
                          const SizedBox(height: 16),
                          tabContent,
                          if (_showLegacyHealthSections) ...[
                            const SizedBox(height: 18),
                            _SectionLabel(
                              title: 'EVOLUÇÃO DO PESO',
                              action: data.weightLogs.isEmpty
                                  ? null
                                  : '${data.weightLogs.length} registros',
                            ),
                            const SizedBox(height: 10),
                            _WeightEvolutionCard(
                              dog: dog,
                              records: data.weightRecords,
                              legacyLogs: data.weightLogs,
                            ),
                            const SizedBox(height: 18),
                            _SectionLabel(
                              title: 'CARTEIRA DE VACINAÇÃO',
                              action: data.vaccines.isEmpty
                                  ? null
                                  : '${data.vaccines.length} registros',
                            ),
                            const SizedBox(height: 10),
                            _VaccinationCard(vaccines: data.vaccines),
                            const SizedBox(height: 18),
                            _SectionLabel(
                              title: 'LAUDOS E DOCUMENTOS',
                              count: documents.length,
                            ),
                            const SizedBox(height: 10),
                            _DocumentList(
                              documents: documents,
                              onOpenDocument: onOpenDocument,
                            ),
                            const SizedBox(height: 8),
                            _AttachDocumentButton(
                              uploading: uploadingDocument,
                              onTap: uploadingDocument
                                  ? null
                                  : onAttachDocument,
                            ),
                            const SizedBox(height: 18),
                            _SectionLabel(
                              title: 'EVENTOS MÉDICOS RECENTES',
                              action: data.logs.isEmpty
                                  ? null
                                  : '${data.logs.length} registros',
                            ),
                            const SizedBox(height: 4),
                            _RecentEvents(logs: data.logs),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 22,
                    bottom: 22,
                    child: _HealthActionFab(onTap: onOpenHealthHub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    List<_ProntuarioDocumentItem> documents,
  ) {
    switch (selectedTab) {
      case _HealthProntuarioTab.resumo:
        return _HealthResumoTab(
          dog: dog,
          data: data,
          onOpenHistory: onOpenUnifiedHistory,
        );
      case _HealthProntuarioTab.vacinas:
        return _HealthVaccinesTab(data: data);
      case _HealthProntuarioTab.peso:
        return _HealthWeightTab(dog: dog, data: data);
      case _HealthProntuarioTab.nutricao:
        return _HealthNutritionTab(
          dog: dog,
          vm: context.watch<NutritionViewModel>(),
        );
      case _HealthProntuarioTab.docs:
        return _HealthDocsTab(
          documents: documents,
          onOpenDocument: onOpenDocument,
        );
    }
  }

  String _shiftElapsedText(BuildContext context) {
    final shiftStartTime = context.watch<ShiftViewModel>().shiftStartTime;
    if (shiftStartTime == null) return '';
    final diff = DateTime.now().difference(shiftStartTime);
    if (diff.inHours > 0) return ' · há ${diff.inHours}h';
    if (diff.inMinutes > 0) return ' · há ${diff.inMinutes}m';
    return ' · agora';
  }
}

class _PageTitle extends StatelessWidget {
  final bool loading;

  const _PageTitle({required this.loading});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'PRONTUÁRIO DO CÃO',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        if (loading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}

class _DogIdentityCard extends StatelessWidget {
  final Dog dog;
  final double? latestWeight;

  const _DogIdentityCard({required this.dog, required this.latestWeight});

  @override
  Widget build(BuildContext context) {
    final displayWeight = latestWeight ?? dog.weight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withAlpha(14),
            AppTheme.success.withAlpha(6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Row(
        children: [
          _DogPhoto(dog: dog, size: 72),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dog.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${dog.breed.toUpperCase()} · ${dog.sex == 'F' ? 'FÊMEA' : 'MACHO'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _MetaText(label: 'Idade', value: '${dog.age} anos'),
                    if (displayWeight != null)
                      _MetaText(
                        label: 'Peso',
                        value: '${displayWeight.toStringAsFixed(1)} kg',
                      ),
                    if (dog.microchip?.trim().isNotEmpty == true)
                      _MetaText(label: 'Chip', value: dog.microchip!.trim()),
                  ],
                ),
                const SizedBox(height: 8),
                _OperationalBadge(status: dog.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DogPhoto extends StatelessWidget {
  final Dog dog;
  final double size;

  const _DogPhoto({required this.dog, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl = dog.profileImageUrl?.trim();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.surfacePanelAlt,
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(color: AppTheme.primary, width: 3),
          ),
          child: ClipOval(
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(),
                  )
                : _fallback(),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppTheme.success,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppTheme.background, width: 2),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppTheme.background,
              size: 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback() {
    final text = dog.name.isNotEmpty ? dog.name[0].toUpperCase() : 'K9';
    return Center(
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: size * 0.26,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final String label;
  final String value;

  const _MetaText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppTheme.textTertiary),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationalBadge extends StatelessWidget {
  final String status;

  const _OperationalBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final active = status.toLowerCase() == 'ativo';
    final color = active ? AppTheme.success : AppTheme.warning;
    final label = active ? 'OPERACIONAL' : status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        '● $label',
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final String? action;
  final int? count;
  final VoidCallback? onActionTap;

  const _SectionLabel({
    required this.title,
    this.action,
    this.count,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(height: 1, color: AppTheme.primary.withAlpha(38)),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ] else if (action != null || onActionTap != null) ...[
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onActionTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                action ?? 'Ver histórico',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickStatusRow extends StatelessWidget {
  final Dog dog;
  final _HealthProntuarioData data;

  const _QuickStatusRow({required this.dog, required this.data});

  @override
  Widget build(BuildContext context) {
    final vaccines = _statusForVaccines(data.logs);
    final alerts = data.openAlertsCount;

    return Row(
      children: [
        Expanded(
          child: _QuickStatusCard(
            icon: Icons.monitor_weight_rounded,
            label: 'Peso',
            value: data.latestWeight == null
                ? 'Sem registro'
                : '${data.latestWeight!.toStringAsFixed(1)} kg',
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStatusCard(
            icon: Icons.verified_user_rounded,
            label: 'Vacinas',
            value: vaccines.value,
            color: vaccines.color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStatusCard(
            icon: Icons.health_and_safety_rounded,
            label: 'Alertas',
            value: alerts == 0 ? 'Sem alertas' : '$alerts alerta(s)',
            color: alerts == 0 ? AppTheme.textSecondary : AppTheme.warning,
          ),
        ),
      ],
    );
  }
}

class _QuickStatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QuickStatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(10),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
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

class _HealthTabSelector extends StatelessWidget {
  final _HealthProntuarioTab selected;
  final ValueChanged<_HealthProntuarioTab> onSelected;

  const _HealthTabSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (_HealthProntuarioTab.resumo, 'Resumo'),
      (_HealthProntuarioTab.vacinas, 'Vacinas'),
      (_HealthProntuarioTab.peso, 'Peso'),
      (_HealthProntuarioTab.nutricao, 'Nutrição'),
      (_HealthProntuarioTab.docs, 'Docs'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceWhiteBorder),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: _HealthTabButton(
                label: tab.$2,
                selected: selected == tab.$1,
                onTap: () => onSelected(tab.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HealthTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(32)
              : AppTheme.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: AppTheme.primary.withAlpha(95))
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HealthResumoTab extends StatelessWidget {
  final Dog dog;
  final _HealthProntuarioData data;
  final VoidCallback onOpenHistory;

  const _HealthResumoTab({
    required this.dog,
    required this.data,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title: 'PRÓXIMAS AÇÕES'),
        const SizedBox(height: 10),
        _NextActionsGrid(data: data),
        const SizedBox(height: 18),
        _SectionLabel(
          title: 'EVOLUÇÃO DO PESO',
          action: data.weightRecords.isEmpty
              ? null
              : '${data.weightRecords.length} registros',
        ),
        const SizedBox(height: 10),
        _WeightEvolutionCard(
          dog: dog,
          records: data.weightRecords,
          legacyLogs: data.weightLogs,
        ),
        const SizedBox(height: 18),
        _SectionLabel(
          title: 'ÚLTIMOS EVENTOS',
          action: data.logs.isEmpty ? null : 'Ver histórico',
          onActionTap: onOpenHistory,
        ),
        const SizedBox(height: 4),
        _SummaryEventsList(events: data.summaryEvents),
      ],
    );
  }
}

class _HealthVaccinesTab extends StatelessWidget {
  final _HealthProntuarioData data;

  const _HealthVaccinesTab({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          title: 'CARTEIRA DE VACINAÇÃO',
          action: data.vaccines.isEmpty
              ? null
              : '${data.vaccines.length} registros',
        ),
        const SizedBox(height: 10),
        _VaccinationCard(vaccines: data.vaccines),
        const SizedBox(height: 18),
        _SectionLabel(title: 'PRÓXIMAS APLICAÇÕES'),
        const SizedBox(height: 10),
        _UpcomingVaccinationsGrid(vaccines: data.upcomingVaccines),
        const SizedBox(height: 18),
        _SectionLabel(
          title: 'HISTÓRICO DE VACINAS',
          action: data.vaccines.isEmpty ? null : 'Ver histórico',
        ),
        const SizedBox(height: 4),
        _RecentEvents(logs: data.vaccines),
      ],
    );
  }
}

class _HealthWeightTab extends StatelessWidget {
  final Dog dog;
  final _HealthProntuarioData data;

  const _HealthWeightTab({required this.dog, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          title: 'EVOLUÇÃO DO PESO',
          action: data.weightRecords.isEmpty
              ? null
              : '${data.weightRecords.length} registros',
        ),
        const SizedBox(height: 10),
        _WeightEvolutionCard(
          dog: dog,
          records: data.weightRecords,
          legacyLogs: data.weightLogs,
        ),
        const SizedBox(height: 12),
        _WeightMetricsRow(dog: dog, data: data),
        const SizedBox(height: 18),
        _SectionLabel(title: 'REGISTROS DE PESAGEM'),
        const SizedBox(height: 10),
        _WeightRecordsList(records: data.weightRecords),
        const SizedBox(height: 12),
        _WeightTrendInsight(dog: dog, records: data.weightRecords),
      ],
    );
  }
}

class _HealthNutritionTab extends StatefulWidget {
  final Dog dog;
  final NutritionViewModel vm;

  const _HealthNutritionTab({required this.dog, required this.vm});

  @override
  State<_HealthNutritionTab> createState() => _HealthNutritionTabState();
}

class _HealthNutritionTabState extends State<_HealthNutritionTab> {
  final _aiService = NutritionAiService();
  int _periodDays = 30;
  bool _loadingAi = false;

  Future<void> _generateInsight() async {
    if (_loadingAi) return;
    setState(() => _loadingAi = true);
    HapticFeedback.selectionClick();

    try {
      final insight = await _aiService.generateInsight(
        dogId: widget.dog.id,
        periodDays: _periodDays,
      );
      if (!mounted) return;
      await _showNutritionInsightSheet(insight);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        e,
        fallback: 'Não foi possível gerar a análise nutricional.',
      );
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  Future<void> _showNutritionInsightSheet(NutritionAiInsight insight) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.48,
          maxChildSize: 0.96,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceSheet,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: AppTheme.attention.withAlpha(60)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.attention.withAlpha(22),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.attention.withAlpha(80),
                            ),
                          ),
                          child: const Icon(
                            Icons.psychology_alt_rounded,
                            color: AppTheme.attention,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Analise nutricional assistida',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${insight.periodDays} dias - ${insight.usedAi ? 'IA generativa' : 'analise local'}',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _InsightHighlight(
                      label: _nutritionLevelLabel(insight.recommendationLevel),
                      text: insight.summary,
                    ),
                    const SizedBox(height: 14),
                    _InsightBlock(
                      title: 'Ajuste alimentar',
                      icon: Icons.restaurant_menu_rounded,
                      color: AppTheme.attention,
                      items: [insight.foodAdjustment],
                    ),
                    _InsightBlock(
                      title: 'Fatores operacionais',
                      icon: Icons.fitness_center_rounded,
                      color: AppTheme.primary,
                      items: insight.operationalFactors,
                    ),
                    _InsightBlock(
                      title: 'Suplementos e hidratacao',
                      icon: Icons.medication_liquid_rounded,
                      color: AppTheme.healthAccent,
                      items: [
                        ...insight.supplementNotes,
                        ...insight.hydrationNotes,
                      ],
                    ),
                    if (insight.dataGaps.isNotEmpty)
                      _InsightBlock(
                        title: 'Dados faltantes',
                        icon: Icons.playlist_add_check_circle_rounded,
                        color: AppTheme.warning,
                        items: insight.dataGaps,
                      ),
                    _InsightBlock(
                      title: 'Proximos passos',
                      icon: Icons.task_alt_rounded,
                      color: AppTheme.success,
                      items: insight.nextActions,
                    ),
                    _InsightBlock(
                      title: 'Cautela tecnica',
                      icon: Icons.health_and_safety_rounded,
                      color: AppTheme.error,
                      items: insight.veterinaryWarnings.isEmpty
                          ? [
                              'Sugestao assistiva: valide alteracoes de dieta, suplemento ou manejo clinico com responsavel tecnico.',
                            ]
                          : insight.veterinaryWarnings,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.attention,
                        ),
                        child: Text(
                          'ENTENDI',
                          style: GoogleFonts.inter(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final prescription = vm.prescription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title: 'PLANO ALIMENTAR'),
        const SizedBox(height: 10),
        _NutritionPlanCard(prescription: prescription),
        const SizedBox(height: 18),
        _SectionLabel(title: 'ROTINA DO DIA'),
        const SizedBox(height: 10),
        _FeedingRoutineCard(
          prescription: prescription,
          feedings: vm.todayFeedings,
          loading: vm.loading,
        ),
        const SizedBox(height: 18),
        _SectionLabel(title: 'SUPLEMENTOS'),
        const SizedBox(height: 10),
        _SupplementsCard(supplements: vm.supplements),
        const SizedBox(height: 18),
        _SectionLabel(title: 'OBSERVAÇÕES NUTRICIONAIS'),
        const SizedBox(height: 10),
        _NutritionNotesCard(
          prescription: prescription,
          conformityPercent: vm.conformityPercent,
        ),
        const SizedBox(height: 18),
        _SectionLabel(title: 'INTELIGENCIA ALIMENTAR'),
        const SizedBox(height: 10),
        _NutritionAiCard(
          periodDays: _periodDays,
          loading: _loadingAi,
          onPeriodChanged: (value) => setState(() => _periodDays = value),
          onGenerate: _generateInsight,
        ),
      ],
    );
  }
}

class _NutritionAiCard extends StatelessWidget {
  final int periodDays;
  final bool loading;
  final ValueChanged<int> onPeriodChanged;
  final VoidCallback onGenerate;

  const _NutritionAiCard({
    required this.periodDays,
    required this.loading,
    required this.onPeriodChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.attention.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.attention,
                        ),
                      )
                    : const Icon(
                        Icons.psychology_alt_rounded,
                        color: AppTheme.attention,
                        size: 21,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? 'Analisando dados...' : 'Sugestao assistida',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Cruza alimentacao, treinos, peso, saude e suplementos.',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
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
            children: [7, 30, 60].map((days) {
              final selected = periodDays == days;
              return GestureDetector(
                onTap: loading ? null : () => onPeriodChanged(days),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.attention.withAlpha(38)
                        : AppTheme.textPrimary.withAlpha(6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? AppTheme.attention
                          : AppTheme.surfaceWhiteBorder,
                    ),
                  ),
                  child: Text(
                    '$days dias',
                    style: GoogleFonts.inter(
                      color: selected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading ? null : onGenerate,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                loading ? 'GERANDO ANALISE' : 'GERAR ANALISE',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.attention,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppTheme.textPrimary.withAlpha(30),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A IA nao prescreve dieta. Use como apoio para revisar o manejo com o responsavel tecnico.',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightHighlight extends StatelessWidget {
  final String label;
  final String text;

  const _InsightHighlight({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.attention.withAlpha(18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.attention.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusPill(label: label, color: AppTheme.attention),
          const SizedBox(height: 10),
          Text(
            text,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _InsightBlock({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((item) => item.trim().isNotEmpty).toList();
    if (visibleItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: _panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...visibleItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '-',
                      style: GoogleFonts.inter(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NutritionPlanCard extends StatelessWidget {
  final NutritionPrescription? prescription;

  const _NutritionPlanCard({required this.prescription});

  @override
  Widget build(BuildContext context) {
    if (prescription == null) {
      return const _EmptyPanel(
        icon: Icons.restaurant_menu_outlined,
        message: 'Nenhum plano alimentar vigente cadastrado.',
      );
    }

    final p = prescription!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NutritionPlanTile(
                  icon: Icons.inventory_2_rounded,
                  title: p.foodType,
                  subtitle: 'Tipo de alimentação',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NutritionPlanTile(
                  icon: Icons.schedule_rounded,
                  title: '${p.mealsPerDay} refeições por dia',
                  subtitle: _plannedMealLabels(p.mealsPerDay).join(' e '),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NutritionPlanTile(
                  icon: Icons.scale_rounded,
                  title: '${p.amountGramsPerDay} g / dia',
                  subtitle: '${p.amountPerMeal} g por refeição',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NutritionPlanTile(
                  icon: Icons.water_drop_rounded,
                  title: 'Hidratação',
                  subtitle: p.hydrationNotes?.trim().isNotEmpty == true
                      ? p.hydrationNotes!.trim()
                      : 'Água fresca sempre disponível',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NutritionPlanTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _NutritionPlanTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.attention.withAlpha(24),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.attention, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedingRoutineCard extends StatelessWidget {
  final NutritionPrescription? prescription;
  final List<Feeding> feedings;
  final bool loading;

  const _FeedingRoutineCard({
    required this.prescription,
    required this.feedings,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && feedings.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.hourglass_top_rounded,
        message: 'Carregando rotina alimentar...',
      );
    }

    final periods = _plannedPeriods(prescription?.mealsPerDay ?? 2);
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < periods.length; i++)
            _FeedingRoutineRow(
              period: periods[i],
              amountPerMeal: prescription?.amountPerMeal,
              feeding: _feedingForPeriod(feedings, periods[i]),
              isLast: i == periods.length - 1,
            ),
        ],
      ),
    );
  }
}

class _FeedingRoutineRow extends StatelessWidget {
  final String period;
  final int? amountPerMeal;
  final Feeding? feeding;
  final bool isLast;

  const _FeedingRoutineRow({
    required this.period,
    required this.amountPerMeal,
    required this.feeding,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final completed = feeding != null;
    final color = completed ? AppTheme.success : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_periodIcon(period), color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  NutritionViewModel.periodLabel(period),
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  completed
                      ? '${feeding!.amountGrams} g registrados'
                      : amountPerMeal == null
                      ? 'Quantidade não prescrita'
                      : '$amountPerMeal g programados',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(
            label: completed ? 'Concluído' : 'Programado',
            color: color,
          ),
        ],
      ),
    );
  }
}

class _SupplementsCard extends StatelessWidget {
  final List<NutritionSupplement> supplements;

  const _SupplementsCard({required this.supplements});

  @override
  Widget build(BuildContext context) {
    final active = supplements.where((item) => item.isActive).toList();
    if (active.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.medication_liquid_outlined,
        message: 'Nenhum suplemento em uso.',
      );
    }

    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < active.length; i++)
            _SupplementRow(
              supplement: active[i],
              isLast: i == active.length - 1,
            ),
        ],
      ),
    );
  }
}

class _SupplementRow extends StatelessWidget {
  final NutritionSupplement supplement;
  final bool isLast;

  const _SupplementRow({required this.supplement, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.attention.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.medication_liquid_rounded,
              color: AppTheme.attention,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplement.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _supplementSubtitle(supplement),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(label: 'Em uso', color: AppTheme.success),
        ],
      ),
    );
  }
}

class _NutritionNotesCard extends StatelessWidget {
  final NutritionPrescription? prescription;
  final double conformityPercent;

  const _NutritionNotesCard({
    required this.prescription,
    required this.conformityPercent,
  });

  @override
  Widget build(BuildContext context) {
    final notes = prescription?.notes?.trim();
    final label = notes?.isNotEmpty == true ? notes! : 'Apetite normal';
    final subtitle = conformityPercent <= 0
        ? 'Sem refeições registradas hoje'
        : '${conformityPercent.toStringAsFixed(0)}% de conformidade hoje';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.success.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.success,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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

class _HealthDocsTab extends StatefulWidget {
  final List<_ProntuarioDocumentItem> documents;
  final ValueChanged<_ProntuarioDocumentItem> onOpenDocument;

  const _HealthDocsTab({required this.documents, required this.onOpenDocument});

  @override
  State<_HealthDocsTab> createState() => _HealthDocsTabState();
}

class _HealthDocsTabState extends State<_HealthDocsTab> {
  String _filter = 'todos';

  List<_ProntuarioDocumentItem> get _filteredDocuments {
    return widget.documents.where((item) {
      switch (_filter) {
        case 'exames':
          return item.type == 'exame';
        case 'laudos':
          return item.type == 'laudo';
        case 'pdf':
          return item.isPdf;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredDocuments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          title: 'LAUDOS E DOCUMENTOS',
          count: widget.documents.length,
        ),
        const SizedBox(height: 10),
        _DocumentFilterBar(
          selected: _filter,
          onSelected: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: 10),
        _DocumentList(
          documents: visible,
          onOpenDocument: widget.onOpenDocument,
        ),
      ],
    );
  }
}

class _UpcomingVaccinationsGrid extends StatelessWidget {
  final List<HealthLogModel> vaccines;

  const _UpcomingVaccinationsGrid({required this.vaccines});

  @override
  Widget build(BuildContext context) {
    if (vaccines.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.event_available_outlined,
        message: 'Nenhuma próxima aplicação cadastrada.',
      );
    }

    final visible = vaccines.take(4).toList();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: visible
          .map(
            (log) => SizedBox(
              width: MediaQuery.sizeOf(context).width / 2 - 21,
              child: _UpcomingVaccineCard(log: log),
            ),
          )
          .toList(),
    );
  }
}

class _UpcomingVaccineCard extends StatelessWidget {
  final HealthLogModel log;

  const _UpcomingVaccineCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final due = _dueStatus(log.nextDueDate);
    final color = _colorForLevel(due.level);
    final title = log.subtype?.trim().isNotEmpty == true
        ? log.subtype!.trim()
        : 'Vacina';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.event_available_rounded, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.nextDueDate == null
                      ? 'Sem data'
                      : _formatDate(log.nextDueDate!),
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  due.shortLabel,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
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

class _WeightMetricsRow extends StatelessWidget {
  final Dog dog;
  final _HealthProntuarioData data;

  const _WeightMetricsRow({required this.dog, required this.data});

  @override
  Widget build(BuildContext context) {
    final ordered = [...data.weightRecords]
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final latest = ordered.isEmpty ? null : ordered.first;
    final latestDate = latest == null
        ? 'Sem registro'
        : _formatDate(latest.measuredAt);
    final target = dog.idealWeightMin != null && dog.idealWeightMax != null
        ? '${((dog.idealWeightMin! + dog.idealWeightMax!) / 2).toStringAsFixed(1)} kg'
        : 'Não definida';
    final condition = _weightConditionLabel(dog, data.latestWeight);

    return Row(
      children: [
        Expanded(
          child: _MetricMiniCard(
            icon: Icons.calendar_today_rounded,
            label: 'Última pesagem',
            value: latestDate,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricMiniCard(
            icon: Icons.track_changes_rounded,
            label: 'Meta operacional',
            value: target,
            color: AppTheme.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricMiniCard(
            icon: Icons.health_and_safety_rounded,
            label: 'Condição corporal',
            value: condition,
            color: condition == 'Ideal' ? AppTheme.success : AppTheme.warning,
          ),
        ),
      ],
    );
  }
}

class _MetricMiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightTrendInsight extends StatelessWidget {
  final Dog dog;
  final List<WeightRecord> records;

  const _WeightTrendInsight({required this.dog, required this.records});

  @override
  Widget build(BuildContext context) {
    final ordered = [...records]
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final latest = ordered.isEmpty ? null : ordered.first.weightKg;
    final condition = _weightConditionLabel(dog, latest);
    final message = latest == null
        ? 'Registre pesagens para acompanhar a tendência operacional.'
        : condition == 'Ideal'
        ? 'O peso está dentro da faixa ideal cadastrada, com acompanhamento ativo.'
        : 'Peso fora da faixa ideal cadastrada. Acompanhe a próxima pesagem.';
    final color = latest == null
        ? AppTheme.textMuted
        : condition == 'Ideal'
        ? AppTheme.success
        : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.trending_up_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  condition == 'Ideal'
                      ? 'Tendência estável'
                      : 'Acompanhar tendência',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
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

class _DocumentFilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _DocumentFilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('todos', 'Todos'),
      ('exames', 'Exames'),
      ('laudos', 'Laudos'),
      ('pdf', 'PDF'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceWhiteBorder),
      ),
      child: Row(
        children: [
          for (final item in filters)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected == item.$1
                        ? AppTheme.primary.withAlpha(32)
                        : AppTheme.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: selected == item.$1
                        ? Border.all(color: AppTheme.primary.withAlpha(95))
                        : null,
                  ),
                  child: Text(
                    item.$2,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: selected == item.$1
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: selected == item.$1
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NextActionsGrid extends StatelessWidget {
  final _HealthProntuarioData data;

  const _NextActionsGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _nextVaccineAction(data.logs),
      _nextAntiparasiticAction(data.logs),
      _periodicExamAction(data.logs),
    ];

    return Column(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          _NextActionCard(action: actions[i]),
          if (i != actions.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  final _NextActionData action;

  const _NextActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.color;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(action.icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  action.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              action.status,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryEventsList extends StatelessWidget {
  final List<_SummaryEventData> events;

  const _SummaryEventsList({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.event_note_outlined,
        message: 'Nenhum evento registrado no prontuário.',
      );
    }

    final visible = events.take(5).toList();
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++)
            _SummaryEventRow(
              event: visible[i],
              isLast: i == visible.length - 1,
            ),
        ],
      ),
    );
  }
}

class _SummaryEventRow extends StatelessWidget {
  final _SummaryEventData event;
  final bool isLast;

  const _SummaryEventRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              _formatShortDate(event.date),
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: event.color.withAlpha(26),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(event.icon, color: event.color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
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

class _WeightRecordsList extends StatelessWidget {
  final List<WeightRecord> records;

  const _WeightRecordsList({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.monitor_weight_outlined,
        message: 'Nenhuma pesagem canônica registrada em weight_records.',
      );
    }

    final visible = [...records]
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final limited = visible.take(6).toList();
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < limited.length; i++)
            _WeightRecordRow(
              record: limited[i],
              previous: i + 1 < visible.length ? visible[i + 1] : null,
              isLast: i == limited.length - 1,
            ),
        ],
      ),
    );
  }
}

class _WeightRecordRow extends StatelessWidget {
  final WeightRecord record;
  final WeightRecord? previous;
  final bool isLast;

  const _WeightRecordRow({
    required this.record,
    required this.previous,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final delta = previous == null
        ? null
        : record.weightKg - previous!.weightKg;
    final deltaColor = delta == null || delta.abs() < 0.05
        ? AppTheme.textMuted
        : delta > 0
        ? AppTheme.error
        : AppTheme.success;
    final deltaLabel = delta == null
        ? null
        : '${delta > 0
              ? '↑'
              : delta < 0
              ? '↓'
              : '→'} ${delta.abs().toStringAsFixed(1)} kg';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.monitor_weight_rounded,
              color: AppTheme.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _formatDate(record.measuredAt),
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${record.weightKg.toStringAsFixed(1)} kg',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (deltaLabel != null) ...[
            const SizedBox(width: 10),
            Text(
              deltaLabel,
              style: GoogleFonts.inter(
                color: deltaColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SpecialtyRail extends StatelessWidget {
  final List<TrainingSpecialtyModel> specialties;
  final Dog dog;

  const _SpecialtyRail({required this.specialties, required this.dog});

  @override
  Widget build(BuildContext context) {
    final active = specialties.where((item) => item.isActive).toList();
    final labels = active.isNotEmpty
        ? active
        : (dog.specialties ?? const <String>[])
              .map(
                (label) => TrainingSpecialtyModel(
                  id: label,
                  dogId: dog.id,
                  name: normalizeTrainingLabel(label),
                  status: 'operational',
                  progressPercentage: 100,
                ),
              )
              .toList();

    if (labels.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.workspace_premium_outlined,
        message: 'Nenhuma especialidade operacional cadastrada.',
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: labels.map((specialty) {
          final color = specialty.isOperational
              ? AppTheme.success
              : AppTheme.warning;
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withAlpha(16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(65)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_specialtyIcon(specialty.name), color: color, size: 18),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      specialty.name,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '● ${specialty.statusLabel.toUpperCase()}',
                      style: GoogleFonts.inter(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _specialtyIcon(String label) {
    final key = normalizeTrainingKey(label);
    if (key.contains('busca')) return Icons.track_changes_rounded;
    if (key.contains('detecc')) return Icons.radar_rounded;
    if (key.contains('guarda')) return Icons.shield_rounded;
    if (key.contains('obed')) return Icons.school_rounded;
    return Icons.workspace_premium_rounded;
  }
}

class _WeightEvolutionCard extends StatelessWidget {
  final Dog dog;
  final List<WeightRecord> records;
  final List<HealthLogModel> legacyLogs;

  const _WeightEvolutionCard({
    required this.dog,
    required this.records,
    this.legacyLogs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final values =
        records
            .map((record) => _WeightPoint(record.measuredAt, record.weightKg))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (values.isEmpty) {
      values.addAll(
        legacyLogs
            .where((log) => log.weight != null)
            .map((log) => _WeightPoint(log.date, log.weight!)),
      );
      values.sort((a, b) => a.date.compareTo(b.date));
    }
    if (values.isEmpty && dog.weight != null) {
      values.add(_WeightPoint(DateTime.now(), dog.weight!));
    }
    final current = values.isNotEmpty ? values.last.value : null;
    final trend = _weightTrend(values);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  current == null
                      ? 'Sem pesagem'
                      : '${current.toStringAsFixed(1)} kg',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trend,
                  style: GoogleFonts.inter(
                    color: AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 82,
            width: double.infinity,
            child: values.length >= 2
                ? CustomPaint(painter: _WeightSparklinePainter(values))
                : const _MiniEmptyText(
                    'Registre mais pesagens para ver a curva.',
                  ),
          ),
          if (values.length >= 2) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: values.take(7).map((point) {
                return Text(
                  _monthLabel(point.date),
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeightSparklinePainter extends CustomPainter {
  final List<_WeightPoint> points;

  const _WeightSparklinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.surfaceWhiteBorder
      ..strokeWidth = 1;
    for (final y in [size.height * .25, size.height * .5, size.height * .75]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final visible = points.length > 7
        ? points.sublist(points.length - 7)
        : points;
    final minValue = visible
        .map((p) => p.value)
        .reduce((a, b) => a < b ? a : b);
    final maxValue = visible
        .map((p) => p.value)
        .reduce((a, b) => a > b ? a : b);
    final span = (maxValue - minValue).abs() < 0.1 ? 1.0 : maxValue - minValue;

    final offsets = <Offset>[];
    for (var i = 0; i < visible.length; i++) {
      final x = visible.length == 1
          ? size.width
          : (size.width * i / (visible.length - 1));
      final normalized = (visible[i].value - minValue) / span;
      final y = size.height - (normalized * (size.height - 16)) - 8;
      offsets.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.primary.withAlpha(32), AppTheme.transparent],
        ).createShader(Offset.zero & size),
    );

    for (final point in offsets) {
      canvas.drawCircle(point, 3.2, Paint()..color = AppTheme.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightSparklinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _VaccinationCard extends StatelessWidget {
  final List<HealthLogModel> vaccines;

  const _VaccinationCard({required this.vaccines});

  @override
  Widget build(BuildContext context) {
    if (vaccines.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.vaccines_outlined,
        message: 'Nenhuma vacina registrada no prontuário.',
      );
    }

    final visible = vaccines.take(3).toList();
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++)
            _VaccineRow(log: visible[i], isLast: i == visible.length - 1),
        ],
      ),
    );
  }
}

class _VaccineRow extends StatelessWidget {
  final HealthLogModel log;
  final bool isLast;

  const _VaccineRow({required this.log, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final status = _dueStatus(log.nextDueDate);
    final color = _colorForLevel(status.level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.subtype?.trim().isNotEmpty == true
                      ? log.subtype!.trim()
                      : 'Vacina',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aplicada em ${_formatDate(log.date)}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                log.nextDueDate == null
                    ? 'Sem próxima'
                    : _formatDate(log.nextDueDate!),
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              _StatusPill(label: _vaccineStatusLabel(status), color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  final List<_ProntuarioDocumentItem> documents;
  final ValueChanged<_ProntuarioDocumentItem> onOpenDocument;

  const _DocumentList({required this.documents, required this.onOpenDocument});

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.picture_as_pdf_outlined,
        message: 'Nenhum laudo ou documento anexado.',
      );
    }

    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < documents.length; i++)
            _DocumentRow(
              item: documents[i],
              isLast: i == documents.length - 1,
              onTap: () => onOpenDocument(documents[i]),
            ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final _ProntuarioDocumentItem item;
  final bool isLast;
  final VoidCallback onTap;

  const _DocumentRow({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(18),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(item.icon, color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatMonthYear(item.date),
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachDocumentButton extends StatelessWidget {
  final bool uploading;
  final VoidCallback? onTap;

  const _AttachDocumentButton({required this.uploading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.primary.withAlpha(78),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (uploading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.attach_file_rounded,
                color: AppTheme.primary,
                size: 17,
              ),
            const SizedBox(width: 8),
            Text(
              uploading ? 'Enviando laudo...' : 'Anexar laudo ou documento PDF',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentEvents extends StatelessWidget {
  final List<HealthLogModel> logs;

  const _RecentEvents({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.event_note_outlined,
        message: 'Nenhum evento médico registrado.',
      );
    }

    final visible = logs.take(5).toList();
    return Column(children: visible.map((log) => _EventRow(log: log)).toList());
  }
}

class _EventRow extends StatelessWidget {
  final HealthLogModel log;

  const _EventRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final color = _colorForHealthType(log.type);
    final title = log.subtype?.trim().isNotEmpty == true
        ? log.subtype!.trim()
        : log.logType;
    final subtitle = [
      if (log.vetName?.trim().isNotEmpty == true) log.vetName!.trim(),
      if (log.professionalCrmv?.trim().isNotEmpty == true)
        'CRMV ${log.professionalCrmv!.trim()}',
      if (log.healthObservations.trim().isNotEmpty)
        log.healthObservations.trim().split('\n').first,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.surfaceWhiteBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              _formatShortDate(log.date),
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_iconForHealthType(log.type), color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.isEmpty ? log.logType : subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
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

class _WeightRegistrationSheet extends StatefulWidget {
  final double initialWeight;
  final Future<void> Function(double weight, String? notes) onSave;

  const _WeightRegistrationSheet({
    required this.initialWeight,
    required this.onSave,
  });

  @override
  State<_WeightRegistrationSheet> createState() =>
      _WeightRegistrationSheetState();
}

class _WeightRegistrationSheetState extends State<_WeightRegistrationSheet> {
  final _notesController = TextEditingController();
  late double _weight;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weight = widget.initialWeight.clamp(5.0, 60.0).toDouble();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final notes = _notesController.text.trim();
      await widget.onSave(_weight, notes.isEmpty ? null : notes);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        e,
        fallback: 'Não foi possível registrar a pesagem.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceSheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: AppTheme.primaryDivider)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Registrar pesagem',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${_weight.toStringAsFixed(1)} kg',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Slider(
                value: _weight,
                min: 5,
                max: 60,
                divisions: 550,
                activeColor: AppTheme.primary,
                inactiveColor: AppTheme.primary.withAlpha(40),
                label: '${_weight.toStringAsFixed(1)} kg',
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _weight = value),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '5 kg',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '60 kg',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 3,
                enabled: !_saving,
                style: GoogleFonts.inter(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Observação opcional',
                  labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.surfacePanel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.surfaceWhiteBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.background,
                          ),
                        )
                      : const Icon(Icons.monitor_weight_rounded, size: 18),
                  label: Text(
                    _saving ? 'SALVANDO...' : 'SALVAR PESAGEM',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthActionFab extends StatelessWidget {
  final VoidCallback onTap;

  const _HealthActionFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.primary,
          border: Border.all(color: AppTheme.textPrimary.withAlpha(220)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withAlpha(125),
              blurRadius: 24,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: AppTheme.background.withAlpha(180),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.background.withAlpha(28),
            border: Border.all(color: AppTheme.background.withAlpha(120)),
          ),
          child: const Icon(
            Icons.health_and_safety_rounded,
            color: AppTheme.background,
            size: 38,
          ),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyPanel({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 26),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniEmptyText extends StatelessWidget {
  final String message;

  const _MiniEmptyText(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: AppTheme.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HealthEmptyState extends StatelessWidget {
  final String message;

  const _HealthEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSoft),
        ),
      ),
    );
  }
}

class _DocumentUploadSheet extends StatefulWidget {
  final String dogName;

  const _DocumentUploadSheet({required this.dogName});

  @override
  State<_DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends State<_DocumentUploadSheet> {
  final _nameController = TextEditingController();
  final _issuerController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _type = 'laudo';
  File? _pdfFile;
  String? _pdfName;

  @override
  void dispose() {
    _nameController.dispose();
    _issuerController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit =
        _nameController.text.trim().isNotEmpty && _pdfFile != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceSheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Anexar laudo de ${widget.dogName}',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SheetField(
                  controller: _nameController,
                  label: 'Nome do documento *',
                  hint: 'Ex.: Laudo ortopédico anual',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _SheetDropdown(
                  value: _type,
                  onChanged: (value) => setState(() => _type = value),
                ),
                const SizedBox(height: 12),
                _SheetField(
                  controller: _issuerController,
                  label: 'Emissor / profissional',
                  hint: 'Ex.: Dra. Ana Souza · CRMV 12345',
                ),
                const SizedBox(height: 12),
                _SheetField(
                  controller: _descriptionController,
                  label: 'Descrição',
                  hint: 'Observação curta para o prontuário',
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickPdf,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withAlpha(70)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _pdfName ?? 'Selecionar PDF',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: _pdfName == null
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.background,
                      disabledBackgroundColor: AppTheme.textPrimary.withAlpha(
                        24,
                      ),
                      disabledForegroundColor: AppTheme.textPrimary.withAlpha(
                        70,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'ANEXAR AO PRONTUÁRIO',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPdf() async {
    final result = await const PdfAttachmentService().pickPdf();
    if (result == null) return;
    setState(() {
      _pdfFile = result.file;
      _pdfName = result.name;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = result.name.replaceAll(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        );
      }
    });
  }

  void _submit() {
    final file = _pdfFile;
    if (file == null) return;
    Navigator.pop(
      context,
      _DocumentUploadDraft(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        type: _type,
        file: file,
        issuer: _issuerController.text.trim().isEmpty
            ? null
            : _issuerController.text.trim(),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
        filled: true,
        fillColor: AppTheme.surfacePanel,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}

class _SheetDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SheetDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: AppTheme.surfacePanel,
      style: GoogleFonts.inter(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: 'Tipo',
        labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.surfacePanel,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'laudo', child: Text('Laudo médico')),
        DropdownMenuItem(value: 'certificado', child: Text('Certificado')),
        DropdownMenuItem(value: 'documento', child: Text('Documento')),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _HealthProntuarioData {
  final List<HealthLogModel> logs;
  final List<DogDocument> documents;
  final List<WeightRecord> weightRecords;

  const _HealthProntuarioData({
    required this.logs,
    required this.documents,
    required this.weightRecords,
  });

  factory _HealthProntuarioData.empty() =>
      const _HealthProntuarioData(logs: [], documents: [], weightRecords: []);

  List<HealthLogModel> get vaccines =>
      logs.where((log) => log.type == 'vaccination').toList();

  List<HealthLogModel> get upcomingVaccines {
    final entries = vaccines.where((log) => log.nextDueDate != null).toList()
      ..sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));
    return entries;
  }

  List<HealthLogModel> get weightLogs =>
      logs.where((log) => log.weight != null).toList();

  double? get latestWeight {
    if (weightRecords.isNotEmpty) {
      final sorted = [...weightRecords]
        ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
      return sorted.first.weightKg;
    }
    if (weightLogs.isNotEmpty) {
      final sorted = [...weightLogs]..sort((a, b) => b.date.compareTo(a.date));
      return sorted.first.weight;
    }
    return null;
  }

  int get openAlertsCount {
    return logs.where((log) {
      final due = _dueStatus(log.nextDueDate);
      return due.level == _StatusLevel.warn ||
          due.level == _StatusLevel.critical;
    }).length;
  }

  List<_SummaryEventData> get summaryEvents {
    final events = <_SummaryEventData>[
      ...logs.map(_SummaryEventData.fromHealthLog),
      ...weightRecords.map(_SummaryEventData.fromWeightRecord),
    ];
    events.sort((a, b) => b.date.compareTo(a.date));
    return events;
  }

  List<_ProntuarioDocumentItem> get documentItems {
    final items = <_ProntuarioDocumentItem>[
      ...documents.map(_ProntuarioDocumentItem.fromDogDocument),
    ];

    for (final log in logs) {
      final attachmentUrl = log.attachmentUrl?.trim();
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
        items.add(_ProntuarioDocumentItem.fromHealthLog(log, attachmentUrl));
      }
      final media = log.mediaAttachments ?? const <Map<String, dynamic>>[];
      for (final attachment in media) {
        final url = attachment['url']?.toString().trim();
        if (url == null || url.isEmpty) continue;
        final type = attachment['type']?.toString().toLowerCase() ?? '';
        final caption = attachment['caption']?.toString();
        if (type == 'pdf' || url.toLowerCase().contains('.pdf')) {
          items.add(
            _ProntuarioDocumentItem.fromHealthLog(
              log,
              url,
              overrideName: caption,
            ),
          );
        }
      }
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }
}

class _ProntuarioDocumentItem {
  final String id;
  final String name;
  final String subtitle;
  final String url;
  final DateTime date;
  final String type;

  const _ProntuarioDocumentItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.url,
    required this.date,
    required this.type,
  });

  factory _ProntuarioDocumentItem.fromDogDocument(DogDocument document) {
    return _ProntuarioDocumentItem(
      id: document.id,
      name: document.nome,
      subtitle: [
        if (document.emissor?.trim().isNotEmpty == true)
          document.emissor!.trim(),
        if (document.descricao.trim().isNotEmpty) document.descricao.trim(),
      ].join(' · '),
      url: document.url,
      date: document.dataUpload,
      type: document.tipo,
    );
  }

  factory _ProntuarioDocumentItem.fromHealthLog(
    HealthLogModel log,
    String url, {
    String? overrideName,
  }) {
    final title = overrideName?.trim().isNotEmpty == true
        ? overrideName!.trim()
        : '${log.logType}${log.subtype == null ? '' : ' · ${log.subtype}'}';
    final subtitle = [
      if (log.vetName?.trim().isNotEmpty == true) log.vetName!.trim(),
      if (log.professionalCrmv?.trim().isNotEmpty == true)
        'CRMV ${log.professionalCrmv!.trim()}',
      'Registro de saúde',
    ].join(' · ');

    return _ProntuarioDocumentItem(
      id: 'health_${log.id ?? log.date.toIso8601String()}_$url',
      name: title,
      subtitle: subtitle,
      url: url,
      date: log.date,
      type: log.type == 'exam' ? 'exame' : 'documento',
    );
  }

  IconData get icon {
    switch (type) {
      case 'exame':
        return Icons.biotech_rounded;
      case 'laudo':
        return Icons.medical_information_rounded;
      case 'certificado':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  bool get isPdf => url.toLowerCase().contains('.pdf');
}

class _DocumentUploadDraft {
  final String name;
  final String description;
  final String type;
  final File file;
  final String? issuer;

  const _DocumentUploadDraft({
    required this.name,
    required this.description,
    required this.type,
    required this.file,
    this.issuer,
  });
}

class _MedicalStatusData {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final _StatusLevel level;

  const _MedicalStatusData({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.level,
  });

  Color get color => _colorForLevel(level);
}

class _DueStatus {
  final _StatusLevel level;
  final String shortLabel;

  const _DueStatus(this.level, this.shortLabel);
}

class _WeightPoint {
  final DateTime date;
  final double value;

  const _WeightPoint(this.date, this.value);
}

class _NextActionData {
  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final _StatusLevel level;

  const _NextActionData({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.level,
  });

  Color get color => _colorForLevel(level);
}

class _SummaryEventData {
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SummaryEventData({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  factory _SummaryEventData.fromHealthLog(HealthLogModel log) {
    final title = log.subtype?.trim().isNotEmpty == true
        ? log.subtype!.trim()
        : log.logType;
    final subtitle = [
      log.logType,
      if (log.vetName?.trim().isNotEmpty == true) log.vetName!.trim(),
      if (log.professionalCrmv?.trim().isNotEmpty == true)
        'CRMV ${log.professionalCrmv!.trim()}',
      if (log.healthObservations.trim().isNotEmpty)
        log.healthObservations.trim().split('\n').first,
    ].join(' · ');

    return _SummaryEventData(
      date: log.date,
      title: title,
      subtitle: subtitle,
      icon: _iconForHealthType(log.type),
      color: _colorForHealthType(log.type),
    );
  }

  factory _SummaryEventData.fromWeightRecord(WeightRecord record) {
    final context = record.context.trim().isEmpty ? 'canil' : record.context;
    final measuredBy = record.measuredBy.trim();
    return _SummaryEventData(
      date: record.measuredAt,
      title: 'Pesagem',
      subtitle: [
        '${record.weightKg.toStringAsFixed(1)} kg',
        context,
        if (measuredBy.isNotEmpty) measuredBy,
      ].join(' · '),
      icon: Icons.monitor_weight_rounded,
      color: AppTheme.primary,
    );
  }
}

enum _StatusLevel { ok, warn, critical, neutral }

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: AppTheme.surfaceWhiteOverlayWeak,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppTheme.surfaceWhiteBorder),
  );
}

_NextActionData _nextVaccineAction(List<HealthLogModel> logs) {
  final vaccines = logs.where((log) => log.type == 'vaccination').toList();
  if (vaccines.isEmpty) {
    return const _NextActionData(
      title: 'Vacina',
      subtitle: 'Nenhuma vacina cadastrada',
      status: 'Sem registro',
      icon: Icons.vaccines_rounded,
      level: _StatusLevel.neutral,
    );
  }

  vaccines.sort((a, b) {
    final aDate = a.nextDueDate ?? a.date;
    final bDate = b.nextDueDate ?? b.date;
    return aDate.compareTo(bDate);
  });
  final next = vaccines.first;
  final due = _dueStatus(next.nextDueDate);
  return _NextActionData(
    title: next.subtype?.trim().isNotEmpty == true
        ? next.subtype!.trim()
        : 'Vacina',
    subtitle: next.nextDueDate == null
        ? 'Última aplicação em ${_formatDate(next.date)}'
        : 'Próxima aplicação em ${_formatDate(next.nextDueDate!)}',
    status: due.shortLabel,
    icon: Icons.vaccines_rounded,
    level: due.level,
  );
}

_NextActionData _nextAntiparasiticAction(List<HealthLogModel> logs) {
  final entries = logs.where((log) => log.type == 'antiparasitic').toList();
  if (entries.isEmpty) {
    return const _NextActionData(
      title: 'Antiparasitário',
      subtitle: 'Nenhuma aplicação cadastrada',
      status: 'Sem registro',
      icon: Icons.bug_report_rounded,
      level: _StatusLevel.neutral,
    );
  }

  entries.sort((a, b) {
    final aDate = a.nextDueDate ?? a.date;
    final bDate = b.nextDueDate ?? b.date;
    return aDate.compareTo(bDate);
  });
  final next = entries.first;
  final due = _dueStatus(next.nextDueDate);
  return _NextActionData(
    title: next.subtype?.trim().isNotEmpty == true
        ? next.subtype!.trim()
        : 'Antiparasitário',
    subtitle: next.nextDueDate == null
        ? 'Última aplicação em ${_formatDate(next.date)}'
        : 'Próxima aplicação em ${_formatDate(next.nextDueDate!)}',
    status: due.shortLabel,
    icon: Icons.bug_report_rounded,
    level: due.level,
  );
}

_NextActionData _periodicExamAction(List<HealthLogModel> logs) {
  final exams = logs.where((log) => log.type == 'exam').toList();
  if (exams.isEmpty) {
    return const _NextActionData(
      title: 'Exame periódico',
      subtitle: 'Nenhum exame cadastrado',
      status: 'Não cadastrado',
      icon: Icons.biotech_rounded,
      level: _StatusLevel.neutral,
    );
  }

  exams.sort((a, b) => b.date.compareTo(a.date));
  final latest = exams.first;
  final days = DateTime.now().difference(latest.date).inDays;
  final level = days >= 365
      ? _StatusLevel.critical
      : days >= 180
      ? _StatusLevel.warn
      : _StatusLevel.ok;
  return _NextActionData(
    title: latest.subtype?.trim().isNotEmpty == true
        ? latest.subtype!.trim()
        : 'Exame periódico',
    subtitle: 'Último exame em ${_formatDate(latest.date)}',
    status: days >= 365
        ? 'Vencido'
        : days >= 180
        ? 'Atenção'
        : 'Em dia',
    icon: Icons.biotech_rounded,
    level: level,
  );
}

_MedicalStatusData _statusForVaccines(List<HealthLogModel> logs) {
  final vaccines = logs.where((log) => log.type == 'vaccination').toList();
  if (vaccines.isEmpty) {
    return const _MedicalStatusData(
      label: 'VACINAS',
      value: 'Sem registro',
      subtitle: 'Nenhuma vacina cadastrada',
      icon: Icons.vaccines_rounded,
      level: _StatusLevel.neutral,
    );
  }
  vaccines.sort((a, b) => b.date.compareTo(a.date));
  final latest = vaccines.first;
  final due = _dueStatus(latest.nextDueDate);
  return _MedicalStatusData(
    label: 'VACINAS',
    value: due.level == _StatusLevel.critical
        ? 'Vencida'
        : due.level == _StatusLevel.warn
        ? 'Vencendo'
        : 'Em dia',
    subtitle: latest.nextDueDate == null
        ? 'Última: ${_formatDate(latest.date)}'
        : 'Próxima: ${latest.subtype ?? 'vacina'} em ${_formatDate(latest.nextDueDate!)}',
    icon: Icons.vaccines_rounded,
    level: due.level,
  );
}

// ignore: unused_element
_MedicalStatusData _statusForAntiparasitic(List<HealthLogModel> logs) {
  final entries = logs.where((log) => log.type == 'antiparasitic').toList();
  if (entries.isEmpty) {
    return const _MedicalStatusData(
      label: 'ANTIPARASITÁRIO',
      value: 'Sem registro',
      subtitle: 'Nenhuma aplicação cadastrada',
      icon: Icons.bug_report_rounded,
      level: _StatusLevel.neutral,
    );
  }
  entries.sort((a, b) => b.date.compareTo(a.date));
  final latest = entries.first;
  final due = _dueStatus(latest.nextDueDate);
  return _MedicalStatusData(
    label: 'ANTIPARASITÁRIO',
    value: due.level == _StatusLevel.critical
        ? 'Vencido'
        : due.level == _StatusLevel.warn
        ? 'Vencendo'
        : 'Em dia',
    subtitle:
        'Última: ${_formatDate(latest.date)} · ${latest.subtype ?? 'produto não informado'}',
    icon: Icons.bug_report_rounded,
    level: due.level,
  );
}

// ignore: unused_element
_MedicalStatusData _statusForWeight(Dog dog, double? latestWeight) {
  final weight = latestWeight ?? dog.weight;
  if (weight == null) {
    return const _MedicalStatusData(
      label: 'PESO',
      value: 'Sem registro',
      subtitle: 'Registre uma pesagem',
      icon: Icons.monitor_weight_rounded,
      level: _StatusLevel.neutral,
    );
  }

  final inRange =
      dog.idealWeightMin != null &&
      dog.idealWeightMax != null &&
      weight >= dog.idealWeightMin! &&
      weight <= dog.idealWeightMax!;
  final hasRange = dog.idealWeightMin != null && dog.idealWeightMax != null;

  return _MedicalStatusData(
    label: 'PESO',
    value: '${weight.toStringAsFixed(1)} kg',
    subtitle: hasRange
        ? 'Faixa ideal: ${dog.idealWeightMin!.toStringAsFixed(1)}-${dog.idealWeightMax!.toStringAsFixed(1)} kg'
        : 'Última pesagem registrada',
    icon: Icons.monitor_weight_rounded,
    level: !hasRange || inRange ? _StatusLevel.ok : _StatusLevel.warn,
  );
}

// ignore: unused_element
_MedicalStatusData _statusForExams(List<HealthLogModel> logs) {
  final exams = logs.where((log) => log.type == 'exam').toList();
  if (exams.isEmpty) {
    return const _MedicalStatusData(
      label: 'EXAMES',
      value: 'Sem registro',
      subtitle: 'Nenhum exame cadastrado',
      icon: Icons.biotech_rounded,
      level: _StatusLevel.neutral,
    );
  }
  exams.sort((a, b) => b.date.compareTo(a.date));
  final latest = exams.first;
  final months = DateTime.now().difference(latest.date).inDays ~/ 30;
  return _MedicalStatusData(
    label: 'EXAMES',
    value: months >= 12
        ? 'Antigo'
        : months >= 6
        ? 'Atenção'
        : 'Atual',
    subtitle:
        '${latest.subtype ?? 'Exame'} há ${months == 0 ? 'menos de 1' : months} mês(es)',
    icon: Icons.biotech_rounded,
    level: months >= 12
        ? _StatusLevel.critical
        : months >= 6
        ? _StatusLevel.warn
        : _StatusLevel.ok,
  );
}

_DueStatus _dueStatus(DateTime? date) {
  if (date == null) return const _DueStatus(_StatusLevel.neutral, 'sem data');
  final days = date.difference(DateTime.now()).inDays;
  if (days < 0) return const _DueStatus(_StatusLevel.critical, 'vencida');
  if (days <= 30) return _DueStatus(_StatusLevel.warn, 'em ${days}d');
  return _DueStatus(_StatusLevel.ok, 'em ${days}d');
}

String _vaccineStatusLabel(_DueStatus status) {
  switch (status.level) {
    case _StatusLevel.critical:
      return 'Vencida';
    case _StatusLevel.warn:
      return 'Vencendo';
    case _StatusLevel.ok:
      return 'Em dia';
    case _StatusLevel.neutral:
      return 'Sem data';
  }
}

List<String> _plannedPeriods(int mealsPerDay) {
  if (mealsPerDay <= 1) return const ['manha'];
  if (mealsPerDay == 2) return const ['manha', 'noite'];
  return const ['manha', 'almoco', 'noite'];
}

List<String> _plannedMealLabels(int mealsPerDay) {
  return _plannedPeriods(
    mealsPerDay,
  ).map(NutritionViewModel.periodLabel).toList();
}

Feeding? _feedingForPeriod(List<Feeding> feedings, String period) {
  final matches = feedings.where((feeding) => feeding.period == period).toList()
    ..sort((a, b) => b.fedAt.compareTo(a.fedAt));
  return matches.isEmpty ? null : matches.first;
}

IconData _periodIcon(String period) {
  switch (period) {
    case 'manha':
      return Icons.wb_sunny_rounded;
    case 'almoco':
      return Icons.wb_twilight_rounded;
    case 'noite':
      return Icons.nightlight_round;
    default:
      return Icons.restaurant_rounded;
  }
}

String _supplementSubtitle(NutritionSupplement supplement) {
  final end = supplement.endedAt == null
      ? 'em uso'
      : 'até ${_formatDate(supplement.endedAt!)}';
  return '${supplement.dose} · desde ${_formatDate(supplement.startedAt)} · $end';
}

// ignore: unused_element
double? _latestWeight(List<HealthLogModel> logs) {
  final weighted = logs.where((log) => log.weight != null).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return weighted.isEmpty ? null : weighted.first.weight;
}

String _weightTrend(List<_WeightPoint> values) {
  if (values.length < 2) return '→ sem curva';
  final diff = values.last.value - values.first.value;
  if (diff.abs() < 0.4) return '→ estável';
  if (diff > 0) return '↑ +${diff.toStringAsFixed(1)} kg';
  return '↓ ${diff.toStringAsFixed(1)} kg';
}

String _weightConditionLabel(Dog dog, double? weight) {
  if (weight == null) return 'Sem dado';
  final min = dog.idealWeightMin;
  final max = dog.idealWeightMax;
  if (min == null || max == null) return 'Monitorado';
  if (weight < min) return 'Abaixo';
  if (weight > max) return 'Acima';
  return 'Ideal';
}

Color _colorForLevel(_StatusLevel level) {
  switch (level) {
    case _StatusLevel.ok:
      return AppTheme.success;
    case _StatusLevel.warn:
      return AppTheme.warning;
    case _StatusLevel.critical:
      return AppTheme.error;
    case _StatusLevel.neutral:
      return AppTheme.textMuted;
  }
}

IconData _iconForHealthType(String type) {
  switch (type) {
    case 'vaccination':
      return Icons.vaccines_rounded;
    case 'antiparasitic':
      return Icons.bug_report_rounded;
    case 'exam':
      return Icons.biotech_rounded;
    case 'consultation':
      return Icons.medical_services_rounded;
    case 'medication':
      return Icons.medication_rounded;
    case 'symptom':
      return Icons.warning_rounded;
    case 'surgery':
      return Icons.healing_rounded;
    default:
      return Icons.event_note_rounded;
  }
}

Color _colorForHealthType(String type) {
  switch (type) {
    case 'vaccination':
      return AppTheme.success;
    case 'antiparasitic':
      return AppTheme.healthAccent;
    case 'exam':
      return AppTheme.info;
    case 'consultation':
      return AppTheme.successOperational;
    case 'medication':
      return AppTheme.warning;
    case 'symptom':
      return AppTheme.error;
    case 'surgery':
      return AppTheme.attention;
    default:
      return AppTheme.textMuted;
  }
}

String _nutritionLevelLabel(String level) {
  switch (level) {
    case 'avaliar_aumento':
      return 'Avaliar aumento';
    case 'avaliar_reducao':
      return 'Avaliar reducao';
    case 'atencao_clinica':
    case 'atenção_clinica':
      return 'Atencao clinica';
    default:
      return 'Manter monitoramento';
  }
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _formatShortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}

String _formatMonthYear(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '$month/${date.year}';
}

String _monthLabel(DateTime date) {
  const labels = [
    'JAN',
    'FEV',
    'MAR',
    'ABR',
    'MAI',
    'JUN',
    'JUL',
    'AGO',
    'SET',
    'OUT',
    'NOV',
    'DEZ',
  ];
  return labels[date.month - 1];
}

bool get _showLegacyHealthSections => false;
