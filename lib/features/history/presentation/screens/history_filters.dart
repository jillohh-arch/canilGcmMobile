part of 'history_screen.dart';

/// Filtros de período e tipo
extension _HistoryFilters on _HistoryScreenState {
  Widget _buildPeriodFilters() {
    const periods = ['Hoje', 'Ontem', 'Esta semana', 'Este mês', 'Personalizado'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: periods.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final period = periods[index];
            final isActive = _periodFilter == period;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _periodFilter = period);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? _cyanAccent.withAlpha(31)
                      : Colors.white.withAlpha(8),
                  border: Border.all(
                    color: isActive ? _cyanAccent : Colors.white.withAlpha(20),
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  period,
                  style: GoogleFonts.inter(
                    color: isActive ? _cyanAccent : _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTypeFilters() {
    final types = [
      ('Tudo', null),
      ('🍖 Rotina', 'Rotina'),
      ('⚕ Saúde', 'Saude'),
      ('🎯 Treino', 'Treino'),
      ('🛡 Ocorrência', 'Ocorrência'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: types.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final (label, value) = types[index];
            final filterValue = value ?? 'Tudo';
            final isActive = _typeFilter == filterValue;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _typeFilter = filterValue);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? _cyanAccent.withAlpha(31)
                      : Colors.white.withAlpha(8),
                  border: Border.all(
                    color: isActive ? _cyanAccent : Colors.white.withAlpha(20),
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: isActive ? _cyanAccent : _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Retorna o range de datas baseado no filtro de período
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
        final monthStart = DateTime(now.year, now.month, 1);
        return (start: monthStart, end: today.add(const Duration(days: 1)));
      default:
        // Personalizado - mostra últimos 30 dias por padrão
        return (
          start: today.subtract(const Duration(days: 30)),
          end: today.add(const Duration(days: 1)),
        );
    }
  }
}
