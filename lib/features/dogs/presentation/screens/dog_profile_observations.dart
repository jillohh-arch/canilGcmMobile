part of 'dog_profile_screen.dart';

/// Seção "OBSERVAÇÕES" com texto vindo do Firestore.
class _ObservationsSection extends StatelessWidget {
  final String? observacoes;

  const _ObservationsSection({this.observacoes});

  @override
  Widget build(BuildContext context) {
    final hasContent = observacoes != null && observacoes!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'OBSERVAÇÕES'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelColor.withAlpha(200),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withAlpha(30)),
          ),
          child: Text(
            hasContent ? observacoes! : 'Nenhuma observação registrada.',
            style: GoogleFonts.inter(
              color: hasContent ? Colors.white70 : Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
