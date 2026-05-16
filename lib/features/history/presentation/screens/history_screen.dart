import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/routine/domain/routine_model.dart';
import 'package:canil_gcm/features/routine/presentation/viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

part 'history_models.dart';
part 'history_filters.dart';
part 'history_timeline_list.dart';
part 'history_timeline_item.dart';
part 'history_data_loader.dart';

const Color _historyBackground = Color(0xFF050D10);
const Color _historySurfaceHigh = Color(0xFF0F2026);
const Color _historyBorder = Color(0x523E7180);
const Color _historyBorderStrong = Color(0x804DD0E1);
const Color _historyTextPrimary = Color(0xFFF4F7F8);
const Color _historyTextSecondary = Color(0xFFA7B4BA);
const Color _historyTextMuted = Color(0xFF71828A);
const Color _historyGreen = Color(0xFF74DB69);
const Color _historyYellow = Color(0xFFFFC23A);

const LinearGradient _historyPanelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xF2112028), Color(0xF207151B), Color(0xF20A1E25)],
);

BoxDecoration _historyPanelDecoration({Color? borderColor}) {
  return BoxDecoration(
    gradient: _historyPanelGradient,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor ?? _historyBorder, width: 1.1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(68),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: AppTheme.primary.withAlpha(12),
        blurRadius: 20,
        offset: const Offset(0, -2),
      ),
    ],
  );
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _periodFilter = 'Este mês';
  String _typeFilter = 'Tudo';
  DateTimeRange? _customRange;
  String _query = '';
  String? _lastLoadedDogId;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);

    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) {
      return const _HistoryNoShift();
    }

    final dogId = shiftVM.activeDogId!;
    if (_lastLoadedDogId != dogId) {
      _lastLoadedDogId = dogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAllData();
      });
    }

    final allEntries = _buildAllEntries(dogId);
    final filteredEntries = _filterEntries(allEntries);
    final groupedEntries = _groupEntriesByDay(filteredEntries);
    final monthEntries = _entriesThisMonth(allEntries);

    return Scaffold(
      backgroundColor: _historyBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFF07141B),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF061017), Color(0xFF050D10), Color(0xFF050D10)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 102),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HistoryHeader(
                    onFilterTap: _openFilterSheet,
                    onCalendarTap: _openDateRangePicker,
                  ),
                  const SizedBox(height: 16),
                  HistorySummaryCard(
                    total: allEntries.length,
                    month: monthEntries.length,
                    incidents: monthEntries
                        .where(
                          (entry) => entry.type == HistoryEntryType.incident,
                        )
                        .length,
                    trainings: monthEntries
                        .where(
                          (entry) => entry.type == HistoryEntryType.training,
                        )
                        .length,
                  ),
                  const SizedBox(height: 14),
                  HistorySearchBar(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 14),
                  HistoryTimelineCard(groups: groupedEntries),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<HistoryEntry> _filterEntries(List<HistoryEntry> entries) {
    final range = _periodDateRange();
    final query = _normalize(_query);

    return entries.where((entry) {
      final inRange =
          !entry.time.isBefore(range.start) && entry.time.isBefore(range.end);
      final typeMatches =
          _typeFilter == 'Tudo' || entry.category == _typeFilter;
      final queryMatches =
          query.isEmpty ||
          _normalize(
            '${entry.title} ${entry.subtitle} ${entry.author} ${entry.tag} ${entry.location}',
          ).contains(query);

      return inRange && typeMatches && queryMatches;
    }).toList()..sort((a, b) => b.time.compareTo(a.time));
  }

  List<HistoryEntry> _entriesThisMonth(List<HistoryEntry> entries) {
    final now = DateTime.now();
    return entries
        .where(
          (entry) =>
              entry.time.year == now.year && entry.time.month == now.month,
        )
        .toList();
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }
}

class HistoryHeader extends StatelessWidget {
  final VoidCallback onFilterTap;
  final VoidCallback onCalendarTap;

  const HistoryHeader({
    super.key,
    required this.onFilterTap,
    required this.onCalendarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Histórico',
                style: GoogleFonts.inter(
                  color: _historyTextPrimary,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Acompanhe todos os registros do binômio.',
                style: GoogleFonts.inter(
                  color: _historyTextSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _HeaderButton(
          icon: Icons.filter_alt_outlined,
          label: 'Filtros',
          onTap: onFilterTap,
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: Icons.calendar_month_outlined,
          onTap: onCalendarTap,
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: 40,
          width: label == null ? 40 : 102,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withAlpha(135)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.primary, size: 21),
              if (label != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: _HistoryAutoFitText(
                    label!,
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HistorySummaryCard extends StatelessWidget {
  final int total;
  final int month;
  final int incidents;
  final int trainings;

  const HistorySummaryCard({
    super.key,
    required this.total,
    required this.month,
    required this.incidents,
    required this.trainings,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final formattedMonth = '${_monthName(now.month)}/${now.year}';

    return _HistoryPanel(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                icon: Icons.assignment_outlined,
                value: '$total',
                label: 'Total de registros',
                meta: 'Todos os tipos',
                color: AppTheme.primary,
              ),
            ),
            const _SummaryDivider(),
            Expanded(
              child: _SummaryMetric(
                icon: Icons.schedule_rounded,
                value: '$month',
                label: 'Este mês',
                meta: formattedMonth,
                color: AppTheme.primary,
              ),
            ),
            const _SummaryDivider(),
            Expanded(
              child: _SummaryMetric(
                icon: Icons.assignment_outlined,
                value: '$incidents',
                label: 'Ocorrências',
                meta: 'Este mês',
                color: _historyYellow,
              ),
            ),
            const _SummaryDivider(),
            Expanded(
              child: _SummaryMetric(
                icon: Icons.fitness_center_rounded,
                value: '$trainings',
                label: 'Treinos',
                meta: 'Este mês',
                color: _historyGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return names[month];
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String meta;
  final Color color;

  const _SummaryMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.meta,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 25),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _HistoryAutoFitText(
                value,
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: _historyTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              _HistoryAutoFitText(
                label,
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: _historyTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              _HistoryAutoFitText(
                meta,
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: _historyTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: _historyBorderStrong.withAlpha(70),
    );
  }
}

class HistorySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const HistorySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: _historyPanelDecoration(),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.inter(
          color: _historyTextPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: AppTheme.primary,
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _historyTextSecondary,
            size: 26,
          ),
          hintText: 'Buscar no histórico...',
          hintStyle: GoogleFonts.inter(
            color: _historyTextSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _HistoryPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: _historyPanelDecoration(),
      child: child,
    );
  }
}

class _HistoryAutoFitText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Alignment alignment;
  final TextAlign textAlign;

  const _HistoryAutoFitText(
    this.text, {
    required this.style,
    this.alignment = Alignment.center,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: textAlign,
            style: style,
          ),
        );

        if (!constraints.maxWidth.isFinite) return fitted;
        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}

class _HistoryNoShift extends StatelessWidget {
  const _HistoryNoShift();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _historyBackground,
      body: Center(
        child: Text(
          'Nenhum turno ativo.',
          style: TextStyle(color: _historyTextSecondary),
        ),
      ),
    );
  }
}
