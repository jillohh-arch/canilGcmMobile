part of 'dog_profile_screen.dart';

/// Seção "SAÚDE" com vacinas, peso e condição corporal.
class _HealthSection extends StatelessWidget {
  final Dog dog;
  final List<VaccineRecord> vaccines;
  final bool loading;

  const _HealthSection({
    required this.dog,
    required this.vaccines,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final v10 = _findVaccine('V10');
    final antirrabica = _findVaccine('Antirrábica');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'SAÚDE'),
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
              : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _HealthCell(
                            icon: Icons.vaccines_rounded,
                            label: 'Vacina V10',
                            value: _vaccineStatus(v10),
                            valueColor: _vaccineColor(v10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HealthCell(
                            icon: Icons.vaccines_rounded,
                            label: 'Antirrábica',
                            value: _vaccineStatus(antirrabica),
                            valueColor: _vaccineColor(antirrabica),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _HealthCell(
                            icon: Icons.monitor_weight_outlined,
                            label: 'Peso atual',
                            value: dog.weight != null
                                ? '${dog.weight!.toStringAsFixed(0)} kg'
                                : 'Não informado',
                            valueColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HealthCell(
                            icon: Icons.favorite_outline_rounded,
                            label: 'Condição corporal',
                            value: dog.condicaoCorporal ?? 'Não informado',
                            valueColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  VaccineRecord? _findVaccine(String name) {
    final lower = name.toLowerCase();
    for (final v in vaccines) {
      if (v.nome.toLowerCase().contains(lower)) return v;
    }
    return null;
  }

  String _vaccineStatus(VaccineRecord? vaccine) {
    if (vaccine == null) return 'Não informado';
    if (vaccine.isExpired) {
      return 'vencida há ${vaccine.daysOverdue} dias';
    }
    return 'em dia';
  }

  Color _vaccineColor(VaccineRecord? vaccine) {
    if (vaccine == null) return Colors.white38;
    if (vaccine.isExpired) return _danger;
    return _green;
  }
}

class _HealthCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _HealthCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _cyan, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  color: valueColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
