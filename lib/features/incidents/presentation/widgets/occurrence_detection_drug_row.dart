part of 'occurrence_detection_fields.dart';

class _DetectionDrugRow extends StatelessWidget {
  final Map<String, dynamic> drug;
  final int index;
  final List<String> drugOptions;
  final Color accentColor;
  final ValueChanged<int> onRemoveDrug;
  final void Function(Map<String, dynamic> drug, String type) onDrugTypeChanged;

  const _DetectionDrugRow({
    required this.drug,
    required this.index,
    required this.drugOptions,
    required this.accentColor,
    required this.onRemoveDrug,
    required this.onDrugTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedType = drugOptions.contains(drug['tipo'])
        ? drug['tipo'] as String?
        : 'Outros';
    final isOtherType = drug['tipo'] == 'Outros';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: HudSelectField<String>(
              label: 'Entorpecente',
              icon: Icons.science_rounded,
              value: selectedType,
              placeholder: 'Tipo',
              accent: accentColor,
              items: drugOptions,
              labelBuilder: (item) => item,
              onChanged: (value) {
                if (value != null) {
                  onDrugTypeChanged(drug, value);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          if (isOtherType)
            Expanded(
              flex: 2,
              child: TacticalTextField(
                controller: drug['especificar'],
                labelText: 'Especificar',
              ),
            ),
          if (isOtherType) const SizedBox(width: 8),
          Expanded(
            child: TacticalTextField(
              controller: drug['quantidade'],
              labelText: 'Qtd/G',
              keyboardType: TextInputType.number,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
            onPressed: () => onRemoveDrug(index),
          ),
        ],
      ),
    );
  }
}
