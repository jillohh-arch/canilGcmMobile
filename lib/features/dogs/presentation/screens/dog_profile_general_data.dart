part of 'dog_profile_screen.dart';

/// Seção "DADOS GERAIS" com grade 2x2.
class _GeneralDataSection extends StatelessWidget {
  final Dog dog;
  const _GeneralDataSection({required this.dog});

  @override
  Widget build(BuildContext context) {
    final birthFormatted = DateFormat('dd/MM/yyyy').format(dog.dateOfBirth);
    final sexLabel = dog.sex == 'M' ? 'Macho' : 'Fêmea';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'DADOS GERAIS'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelColor.withAlpha(200),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withAlpha(30)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DataCell(
                      icon: Icons.male_rounded,
                      label: 'Sexo',
                      value: sexLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DataCell(
                      icon: Icons.cake_outlined,
                      label: 'Nascimento',
                      value: birthFormatted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DataCell(
                      icon: Icons.palette_outlined,
                      label: 'Cor',
                      value: dog.cor ?? 'Não informado',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DataCell(
                      icon: Icons.memory_rounded,
                      label: 'Microchip',
                      value: dog.microchip ?? 'Não informado',
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
}

class _DataCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DataCell({
    required this.icon,
    required this.label,
    required this.value,
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
                  color: Colors.white,
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

/// Título de seção reutilizável.
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.robotoMono(
        color: _cyan,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}
