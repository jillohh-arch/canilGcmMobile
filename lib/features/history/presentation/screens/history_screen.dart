import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/pdf_generator/operational_history_pdf.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart'
    show showDogSwitcher;
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

part 'history_models.dart';
part 'history_filters.dart';
part 'history_timeline_list.dart';
part 'history_timeline_item.dart';
part 'history_data_loader.dart';

const Color _hBg = AppTheme.background;
const Color _hCyan = AppTheme.primary;
const Color _hTextPrimary = AppTheme.textPrimary;
const Color _hTextSecondary = AppTheme.textSecondary;
const Color _hTextMuted = AppTheme.textMuted;
const Color _hTextDimmed = AppTheme.textTertiary;
const Color _hGreen = AppTheme.success;
const Color _hYellow = AppTheme.warning;
const Color _hRed = AppTheme.error;
const Color _hPurple = AppTheme.healthAccent;
const Color _hSheetSurface = AppTheme.surfaceSheet;

enum HistoryScreenMode { full, healthProntuario }

class HistoryScreen extends StatefulWidget {
  final HistoryScreenMode mode;

  const HistoryScreen({super.key, this.mode = HistoryScreenMode.full});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  String _periodFilter = 'Esta semana';
  String _typeFilter = 'Tudo';
  DateTimeRange? _customRange;
  String? _lastLoadedTarget;
  int _visibleCount = 30;
  List<WeightRecord> _weightRecords = const [];

  @override
  void initState() {
    super.initState();
    if (widget.mode == HistoryScreenMode.healthProntuario) {
      _periodFilter = 'Este mês';
      _typeFilter = 'Todos';
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _replaceWeightRecords(List<WeightRecord> records) {
    if (!mounted) return;
    setState(() => _weightRecords = records);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Recarregar dados quando o app volta do background
    if (state == AppLifecycleState.resumed) {
      _lastLoadedTarget = null; // Forçar reload
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAllData(forceReload: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final userVM = Provider.of<UserViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);

    if (!shiftVM.hasActiveShift) {
      return const _HistoryNoShift();
    }

    final effectiveDogId = shiftVM.activeDogId ?? shiftVM.serviceDogId;
    final fbUser = authVM.user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final currentTarget = (effectiveDogId != null && effectiveDogId.isNotEmpty)
        ? 'dog:$effectiveDogId'
        : (currentRa != null && currentRa.isNotEmpty)
            ? 'handler:$currentRa'
            : null;

    if (currentTarget != null && _lastLoadedTarget != currentTarget) {
      _lastLoadedTarget = currentTarget;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAllData();
      });
    }

    final dog = effectiveDogId != null
        ? dogVM.dogs.cast<Dog?>().firstWhere(
            (d) => d?.id == effectiveDogId,
            orElse: () => dogVM.dogs.isNotEmpty ? dogVM.dogs.first : null,
          )
        : null;

    final callsign = userVM.displayNameFor(ra: currentRa, firebaseUser: fbUser);
    final handlerUser = userVM.findByRa(currentRa);
    final handlerPhoto = handlerUser?.photoUrl?.trim();
    final firebasePhoto = fbUser?.photoURL?.trim();
    final handlerImageUrl = handlerPhoto != null && handlerPhoto.isNotEmpty
        ? handlerPhoto
        : firebasePhoto != null && firebasePhoto.isNotEmpty
        ? firebasePhoto
        : null;

    final allEntries = _buildAllEntries(effectiveDogId);
    final filteredEntries = _filterEntries(allEntries);
    final visibleEntries = filteredEntries.take(_visibleCount).toList();
    final groupedEntries = _groupEntriesByDay(visibleEntries);
    final daysCount = groupedEntries.length;

    return Scaffold(
      backgroundColor: _hBg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: _hBg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _HistoryShiftHeader(
                dog: dog,
                callsign: callsign,
                handlerImageUrl: handlerImageUrl,
                shiftStartTime: shiftVM.shiftStartTime,
              ),
              _PageTitleRow(
                title: widget.mode == HistoryScreenMode.healthProntuario
                    ? 'Histórico do prontuário'
                    : 'Histórico',
                showBack: widget.mode == HistoryScreenMode.healthProntuario,
                onBack: () => Navigator.of(context).maybePop(),
                onExport: () => _exportPdf(filteredEntries, dog, callsign),
              ),
              _HistoryFilterToolbar(
                mode: widget.mode,
                period: _periodFilter,
                category: _typeFilter,
                onPeriodSelected: (v) {
                  HapticFeedback.selectionClick();
                  if (v == 'Personalizado') {
                    _openDateRangePicker();
                    return;
                  }
                  setState(() {
                    _periodFilter = v;
                    _visibleCount = 30;
                  });
                },
                onCategorySelected: (v) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _typeFilter = v;
                    _visibleCount = 30;
                  });
                },
                onMoreFilters: _openFilterSheet,
              ),
              _FilterSummaryRow(count: filteredEntries.length, days: daysCount),
              Expanded(
                child: _HistoryTimeline(
                  groups: groupedEntries,
                  hasMore: filteredEntries.length > visibleEntries.length,
                  onLoadMore: () {
                    HapticFeedback.selectionClick();
                    setState(() => _visibleCount += 30);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<HistoryEntry> _filterEntries(List<HistoryEntry> entries) {
    final range = _periodDateRange();

    return entries.where((entry) {
      final inRange =
          !entry.time.isBefore(range.start) && entry.time.isBefore(range.end);
      final typeMatches = widget.mode == HistoryScreenMode.healthProntuario
          ? _healthProntuarioTypeMatches(entry)
          : _typeFilter == 'Tudo' || entry.category == _typeFilter;

      return inRange &&
          typeMatches &&
          (widget.mode != HistoryScreenMode.healthProntuario ||
              _isHealthProntuarioEntry(entry));
    }).toList()..sort((a, b) => b.time.compareTo(a.time));
  }

  bool _isHealthProntuarioEntry(HistoryEntry entry) {
    return entry.type == HistoryEntryType.health ||
        entry.type == HistoryEntryType.nutrition;
  }

  bool _healthProntuarioTypeMatches(HistoryEntry entry) {
    if (_typeFilter == 'Todos') return true;
    if (_typeFilter == 'Nutrição') {
      return entry.type == HistoryEntryType.nutrition;
    }
    if (entry.type != HistoryEntryType.health) return false;

    final kind = entry.details['_healthKind']?.toString();
    switch (_typeFilter) {
      case 'Vacinas':
        return kind == 'vaccination';
      case 'Peso':
        return kind == 'weight';
      case 'Exames':
        return kind == 'exam';
      default:
        return false;
    }
  }

  Future<void> _exportPdf(
    List<HistoryEntry> entries,
    Dog? dog,
    String handlerName,
  ) async {
    if (entries.isEmpty) {
      AppFeedback.info(context, 'Não há registros no período filtrado.');
      return;
    }

    final range = _periodDateRange();
    final rangeEnd = range.end.subtract(const Duration(days: 1));
    final dateLabel =
        '${DateFormat('dd/MM/yyyy').format(range.start)} a ${DateFormat('dd/MM/yyyy').format(rangeEnd)}';

    final bytes = await OperationalHistoryPdf.generate(
      entries: entries,
      dog: dog,
      handlerName: handlerName,
      periodLabel: dateLabel,
    );
    final dogName = dog?.name ?? 'operador';
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'historico_${dogName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}

class _PageTitleRow extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback onExport;

  const _PageTitleRow({
    required this.title,
    required this.onExport,
    this.showBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Row(
        children: [
          if (showBack) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onBack,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _hCyan.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _hCyan.withAlpha(70)),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _hCyan,
                  size: 17,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            title,
            style: GoogleFonts.inter(
              color: _hTextPrimary,
              fontSize: showBack ? 21 : 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onExport,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _hCyan.withAlpha(12),
                border: Border.all(color: _hCyan.withAlpha(210)),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: _hCyan,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Exportar PDF',
                    style: GoogleFonts.inter(
                      color: _hCyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSummaryRow extends StatelessWidget {
  final int count;
  final int days;

  const _FilterSummaryRow({required this.count, required this.days});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: _hTextDimmed,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: '$count registros',
                  style: const TextStyle(
                    color: _hTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' · $days ${days == 1 ? 'dia' : 'dias'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryShiftHeader extends StatelessWidget {
  final Dog? dog;
  final String callsign;
  final String? handlerImageUrl;
  final DateTime? shiftStartTime;

  const _HistoryShiftHeader({
    required this.dog,
    required this.callsign,
    this.handlerImageUrl,
    this.shiftStartTime,
  });

  @override
  Widget build(BuildContext context) {
    final elapsed = _formatElapsed(shiftStartTime);

    if (dog != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(10),
          border: Border(
            bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
          ),
        ),
        child: BinomioHeader(
          dog: dog!,
          handlerNameOverride: callsign,
          conductorPhotoUrl: handlerImageUrl,
          subtitle: 'Turno ativo · $elapsed',
          subtitleColor: _hGreen,
          statusDotColor: _hGreen,
          showStatusDot: true,
          withBackground: false,
          onSwitchDog: () => showDogSwitcher(context),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withAlpha(12),
              border: Border.all(color: AppTheme.primary.withAlpha(180)),
            ),
            child: handlerImageUrl != null
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: handlerImageUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const Icon(
                        Icons.person_rounded,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  callsign,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Turno ativo · Sem K9 · $elapsed',
                  style: GoogleFonts.inter(
                    color: _hGreen,
                    fontSize: 12,
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

  String _formatElapsed(DateTime? start) {
    if (start == null) return '--';
    final diff = DateTime.now().difference(start);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }
}

class _HistoryNoShift extends StatelessWidget {
  const _HistoryNoShift();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hBg,
      body: Center(
        child: Text(
          'Nenhum turno ativo.\nInicie um turno para ver o histórico.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: _hTextMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
