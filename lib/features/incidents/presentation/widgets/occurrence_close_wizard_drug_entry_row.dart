part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardDrugEntryRow on _OccurrenceCloseWizardState {
  Widget _buildDrugEntryRow(int index) {
    final entry = _drugEntries[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: _occurrenceCloseDrugOptions.contains(entry.type)
                  ? entry.type
                  : _occurrenceCloseDrugOptions.first,
              dropdownColor: _OccurrenceCloseWizardState._panel,
              iconEnabledColor: _OccurrenceCloseWizardState._cyan,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: _fieldDecoration(
                hint: 'Tipo de entorpecente',
                icon: Icons.science_rounded,
              ),
              items: _occurrenceCloseDrugOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    ),
                  )
                  .toList(),
              onChanged: widget.isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      _updateDrugEntryType(entry, value);
                    },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: entry.quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: _fieldDecoration(
                hint: 'Qtd.',
                icon: Icons.scale_rounded,
                suffixText: 'g',
              ),
            ),
          ),
          if (_drugEntries.length > 1) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              height: 48,
              child: IconButton(
                onPressed: widget.isSaving
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        _removeDrugEntry(index);
                      },
                icon: const Icon(Icons.remove_circle_rounded),
                color: _OccurrenceCloseWizardState._red,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
