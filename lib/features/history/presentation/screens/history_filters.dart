part of 'history_screen.dart';

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
            primary: AppTheme.primary,
            surface: _historySurfaceHigh,
            onSurface: _historyTextPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _periodFilter = 'Personalizado';
    });
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              decoration: const BoxDecoration(
                color: _historySurfaceHigh,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(
                  top: BorderSide(color: _historyBorderStrong, width: 1),
                ),
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
                        color: _historyTextMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'FILTROS DO HISTÓRICO',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FilterGroup(
                    title: 'Período',
                    options: const [
                      'Hoje',
                      'Ontem',
                      'Esta semana',
                      'Este mês',
                      'Personalizado',
                    ],
                    selected: _periodFilter,
                    onSelected: (value) {
                      HapticFeedback.selectionClick();
                      if (value == 'Personalizado') {
                        Navigator.of(sheetContext).pop();
                        _openDateRangePicker();
                        return;
                      }
                      setState(() => _periodFilter = value);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  _FilterGroup(
                    title: 'Categoria',
                    options: const [
                      'Tudo',
                      'Saúde',
                      'Treino',
                      'Ocorrência',
                      'Nutrição',
                      'Rotina',
                    ],
                    selected: _typeFilter,
                    onSelected: (value) {
                      HapticFeedback.selectionClick();
                      setState(() => _typeFilter = value);
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

class _FilterGroup extends StatelessWidget {
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterGroup({
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
            color: _historyTextSecondary,
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
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelected(option),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary.withAlpha(24)
                      : Colors.white.withAlpha(7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive ? AppTheme.primary : _historyBorder,
                  ),
                ),
                child: Text(
                  option,
                  style: GoogleFonts.inter(
                    color: isActive ? AppTheme.primary : _historyTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
