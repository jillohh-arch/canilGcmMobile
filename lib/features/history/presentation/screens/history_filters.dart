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
            primary: _hCyan,
            surface: Color(0xFF0F2026),
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
                color: Color(0xFF0F2026),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(
                  top: BorderSide(color: _hCyan, width: 1),
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
                        color: _hTextMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'FILTROS DO HISTÓRICO',
                    style: GoogleFonts.inter(
                      color: _hCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FilterSheetGroup(
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
                  _FilterSheetGroup(
                    title: 'Categoria',
                    options: const [
                      'Tudo',
                      'Rotina',
                      'Saúde',
                      'Treino',
                      'Ocorrência',
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

class _PeriodFilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _PeriodFilterChips({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const chips = ['Hoje', 'Ontem', 'Esta semana', 'Este mês', 'Personalizado'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 0, 8),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          padding: const EdgeInsets.only(right: 16),
          itemBuilder: (context, index) {
            final chip = chips[index];
            final active = selected == chip;
            return _FilterChip(
              label: chip,
              active: active,
              onTap: () => onSelected(chip),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryFilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _CategoryFilterChips({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const chips = [
      ('Tudo', ''),
      ('Rotina', '🍖'),
      ('Saúde', '⚕'),
      ('Treino', '🎯'),
      ('Ocorrência', '🛡'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          padding: const EdgeInsets.only(right: 16),
          itemBuilder: (context, index) {
            final (value, emoji) = chips[index];
            final active = selected == value;
            final label = emoji.isEmpty ? value : '$emoji $value';
            return _FilterChip(
              label: label,
              active: active,
              onTap: () => onSelected(value),
            );
          },
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _hCyan.withAlpha(31) : Colors.white.withAlpha(8),
          border: Border.all(
            color: active ? _hCyan : Colors.white.withAlpha(20),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: active ? _hCyan : _hTextSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
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
            return GestureDetector(
              onTap: () => onSelected(option),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? _hCyan.withAlpha(31)
                      : Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive ? _hCyan : Colors.white.withAlpha(20),
                  ),
                ),
                child: Text(
                  option,
                  style: GoogleFonts.inter(
                    color: isActive ? _hCyan : _hTextSecondary,
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
