part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioEventos on _DogProntuarioTabScreenState {
  Widget _buildEventosSection() {
    if (_recentRecords.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('EVENTOS RECENTES', action: 'Ver tudo →'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: _recentRecords.asMap().entries.map((entry) {
              final record = entry.value;
              final isLast = entry.key == _recentRecords.length - 1;
              return _buildEventRow(record, isLast: isLast);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEventRow(RecentRecord record, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0x0AFFFFFF))),
      ),
      child: Row(
        children: [
          // Data
          SizedBox(
            width: 48,
            child: Text(
              DateFormat('dd/MM').format(record.dataHora),
              style: GoogleFonts.inter(
                color: _dimMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Ícone
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: _eventColor(record.tipo).withAlpha(31),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _eventIcon(record.tipo),
              color: _eventColor(record.tipo),
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.titulo,
                  style: GoogleFonts.inter(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  record.tipo,
                  style: GoogleFonts.inter(
                    color: _textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(String tipo) {
    final lower = tipo.toLowerCase();
    if (lower.contains('vacin')) return Icons.vaccines;
    if (lower.contains('consul') || lower.contains('exame')) return Icons.medical_services;
    if (lower.contains('banho') || lower.contains('higien')) return Icons.shower;
    if (lower.contains('treino') || lower.contains('train')) return Icons.fitness_center;
    if (lower.contains('ocorr') || lower.contains('incid')) return Icons.local_police;
    if (lower.contains('peso')) return Icons.monitor_weight;
    if (lower.contains('medic') || lower.contains('remedi')) return Icons.medication;
    return Icons.event_note;
  }

  Color _eventColor(String tipo) {
    final lower = tipo.toLowerCase();
    if (lower.contains('vacin') || lower.contains('medic')) return _redAccent;
    if (lower.contains('consul') || lower.contains('exame')) return _cyanAccent;
    if (lower.contains('treino') || lower.contains('train')) return _yellowAccent;
    if (lower.contains('ocorr') || lower.contains('incid')) return _redAccent;
    return _cyanAccent;
  }
}
