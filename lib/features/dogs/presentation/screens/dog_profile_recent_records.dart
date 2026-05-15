part of 'dog_profile_screen.dart';

/// Seção "ÚLTIMOS REGISTROS" com os 3 registros mais recentes.
class _RecentRecordsSection extends StatelessWidget {
  final List<RecentRecord> records;
  final bool loading;

  const _RecentRecordsSection({
    required this.records,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'ÚLTIMOS REGISTROS'),
        const SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelColor.withAlpha(200),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withAlpha(30)),
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _cyan,
                    ),
                  ),
                )
              : records.isEmpty
                  ? Text(
                      'Nenhum registro encontrado.',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    )
                  : Column(
                      children: [
                        for (int i = 0; i < records.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: Colors.white.withAlpha(10),
                            ),
                          _RecordRow(record: records[i]),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  final RecentRecord record;
  const _RecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final icon = _iconForType(record.tipo);
    final color = _colorForType(record.tipo);
    final timeLabel = _formatRelativeTime(record.dataHora);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              record.titulo,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeLabel,
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white24,
            size: 18,
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final hour =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    if (recordDay == today) {
      return 'hoje $hour';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (recordDay == yesterday) {
      return 'ontem $hour';
    }
    return '${DateFormat('dd/MM').format(dateTime)} $hour';
  }

  IconData _iconForType(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'alimentacao':
      case 'alimentação':
        return Icons.restaurant_rounded;
      case 'passeio':
        return Icons.directions_walk_rounded;
      case 'treino':
      case 'deteccao':
      case 'detecção':
        return Icons.track_changes_rounded;
      case 'limpeza':
        return Icons.cleaning_services_rounded;
      case 'saude':
      case 'saúde':
        return Icons.medical_services_outlined;
      case 'ocorrencia':
      case 'ocorrência':
        return Icons.local_police_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color _colorForType(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'alimentacao':
      case 'alimentação':
        return _cyan;
      case 'passeio':
        return _green;
      case 'treino':
      case 'deteccao':
      case 'detecção':
        return _amber;
      case 'limpeza':
        return _purple;
      case 'ocorrencia':
      case 'ocorrência':
        return _danger;
      default:
        return _cyan;
    }
  }
}
