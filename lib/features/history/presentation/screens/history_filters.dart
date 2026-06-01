// ignore_for_file: invalid_use_of_protected_member

part of 'history_screen.dart';

const _periodOptions = [
  'Hoje',
  'Ontem',
  'Esta semana',
  'Este mês',
  'Personalizado',
];

const _categoryOptions = ['Tudo', 'Nutrição', 'Saúde', 'Treino', 'Ocorrência'];

extension _HistoryFilters on _HistoryScreenState {
  Future<void> _openDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _customRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _hCyan,
            surface: _hSheetSurface,
            onSurface: _hTextPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _periodFilter = 'Personalizado';
      _visibleCount = 30;
    });
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: AppTheme.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              decoration: const BoxDecoration(
                color: _hSheetSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(top: BorderSide(color: _hCyan, width: 1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _hTextMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Filtros do histórico',
                    style: GoogleFonts.inter(
                      color: _hTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FilterSheetGroup(
                    title: 'Período',
                    options: _periodOptions,
                    selected: _periodFilter,
                    onSelected: (value) {
                      HapticFeedback.selectionClick();
                      if (value == 'Personalizado') {
                        Navigator.of(sheetContext).pop();
                        _openDateRangePicker();
                        return;
                      }
                      setState(() {
                        _periodFilter = value;
                        _visibleCount = 30;
                      });
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  _FilterSheetGroup(
                    title: 'Categoria',
                    options: _categoryOptions,
                    selected: _typeFilter,
                    onSelected: (value) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _typeFilter = value;
                        _visibleCount = 30;
                      });
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  ({DateTime start, DateTime end}) _periodDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_periodFilter) {
      case 'Hoje':
        return (start: today, end: today.add(const Duration(days: 1)));
      case 'Ontem':
        final yesterday = today.subtract(const Duration(days: 1));
        return (start: yesterday, end: today);
      case 'Esta semana':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        return (start: weekStart, end: today.add(const Duration(days: 1)));
      case 'Este mês':
        return (
          start: DateTime(now.year, now.month),
          end: today.add(const Duration(days: 1)),
        );
      case 'Personalizado':
        if (_customRange != null) {
          return (
            start: DateTime(
              _customRange!.start.year,
              _customRange!.start.month,
              _customRange!.start.day,
            ),
            end: DateTime(
              _customRange!.end.year,
              _customRange!.end.month,
              _customRange!.end.day,
            ).add(const Duration(days: 1)),
          );
        }
        return (
          start: today.subtract(const Duration(days: 30)),
          end: today.add(const Duration(days: 1)),
        );
      default:
        return (
          start: today.subtract(const Duration(days: 30)),
          end: today.add(const Duration(days: 1)),
        );
    }
  }
}

class _HistoryFilterToolbar extends StatelessWidget {
  final String period;
  final String category;
  final ValueChanged<String> onPeriodSelected;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onMoreFilters;

  const _HistoryFilterToolbar({
    required this.period,
    required this.category,
    required this.onPeriodSelected,
    required this.onCategorySelected,
    required this.onMoreFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _PopupFilterPill(
              label: period,
              icon: Icons.calendar_today_outlined,
              options: _periodOptions,
              onSelected: onPeriodSelected,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _PopupFilterPill(
              label: category,
              options: _categoryOptions,
              onSelected: onCategorySelected,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onMoreFilters,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Filtros',
                    style: GoogleFonts.inter(
                      color: _hCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: _hCyan,
                    size: 16,
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

class _PopupFilterPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final List<String> options;
  final ValueChanged<String> onSelected;

  const _PopupFilterPill({
    required this.label,
    required this.options,
    required this.onSelected,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: _hSheetSurface,
      elevation: 10,
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _hCyan.withAlpha(45)),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem<String>(
              value: option,
              child: Text(
                option,
                style: GoogleFonts.inter(
                  color: option == label ? _hCyan : _hTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _hTextPrimary.withAlpha(7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hTextPrimary.withAlpha(30)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: _hCyan, size: 15),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _hTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _hTextSecondary,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: active ? _hCyan.withAlpha(22) : _hTextPrimary.withAlpha(5),
          border: Border.all(
            color: active ? _hCyan : _hTextPrimary.withAlpha(24),
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: active ? _hCyan : _hTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheetGroup extends StatelessWidget {
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterSheetGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: _hTextSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isActive = option == selected;
            return _FilterChip(
              label: option,
              active: isActive,
              onTap: () => onSelected(option),
            );
          }).toList(),
        ),
      ],
    );
  }
}
