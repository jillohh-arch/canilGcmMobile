part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioVacinas on _DogProntuarioTabScreenState {
  Widget _buildVacinasSection() {
    if (_vaccines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('CARTEIRA DE VACINAÇÃO', action: 'Ver completa →'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(20)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: _vaccines.asMap().entries.map((entry) {
                final index = entry.key;
                final vaccine = entry.value;
                final isLast = index == _vaccines.length - 1;
                return _buildVaccineRow(vaccine, isLast: isLast);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVaccineRow(VaccineRecord vaccine, {required bool isLast}) {
    final now = DateTime.now();
    final daysUntil = vaccine.dataVencimento.difference(now).inDays;
    final isExpired = vaccine.isExpired;

    final Color statusColor;
    if (isExpired) {
      statusColor = _redAccent;
    } else if (daysUntil <= 30) {
      statusColor = _yellowAccent;
    } else {
      statusColor = _greenAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0x0AFFFFFF))),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vaccine.nome,
                  style: GoogleFonts.inter(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Aplicada em ${DateFormat('dd/MM/yyyy').format(vaccine.dataAplicacao)}',
                  style: GoogleFonts.inter(
                    color: _textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Próxima data
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isExpired
                    ? 'Vencida'
                    : DateFormat('dd/MM/yyyy').format(vaccine.dataVencimento),
                style: GoogleFonts.inter(
                  color: isExpired ? _redAccent : _textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                isExpired
                    ? 'há ${vaccine.daysOverdue}d'
                    : 'em ${daysUntil}d',
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
