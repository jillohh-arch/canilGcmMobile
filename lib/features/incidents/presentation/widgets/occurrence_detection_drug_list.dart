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
        OutlinedButton.icon(
          onPressed: onAddDrug,
          icon: const Icon(Icons.add, size: 16, color: Colors.white),
          label: Text(
            'ADICIONAR ENTORPECENTE',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
          ),
        ),
      ],
    );
  }
}

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
