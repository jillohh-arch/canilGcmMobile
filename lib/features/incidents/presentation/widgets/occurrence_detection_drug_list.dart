part of 'occurrence_detection_fields.dart';

class _DetectionDrugList extends StatelessWidget {
  final List<Map<String, dynamic>> drugs;
  final List<String> drugOptions;
  final Color accentColor;
  final VoidCallback onAddDrug;
  final ValueChanged<int> onRemoveDrug;
  final void Function(Map<String, dynamic> drug, String type) onDrugTypeChanged;

  const _DetectionDrugList({
    required this.drugs,
    required this.drugOptions,
    required this.accentColor,
    required this.onAddDrug,
    required this.onRemoveDrug,
    required this.onDrugTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ENTORPECENTES LOCALIZADOS',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          drugs.length,
          (index) => _DetectionDrugRow(
            drug: drugs[index],
            index: index,
            drugOptions: drugOptions,
            accentColor: accentColor,
            onRemoveDrug: onRemoveDrug,
            onDrugTypeChanged: onDrugTypeChanged,
          ),
        ),
        _DetectionDrugAddButton(onPressed: onAddDrug),
      ],
    );
  }
}
