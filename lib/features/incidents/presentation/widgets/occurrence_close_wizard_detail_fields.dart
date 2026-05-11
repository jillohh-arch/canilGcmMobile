part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardDetailFields on _OccurrenceCloseWizardState {
  Widget _buildDynamicDetailBlock(String result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _OccurrenceCloseWizardState._panel.withAlpha(230),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _OccurrenceCloseWizardState._cyan.withAlpha(75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.toUpperCase(),
            style: GoogleFonts.robotoMono(
              color: _OccurrenceCloseWizardState._cyan,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ..._fieldsFor(result),
        ],
      ),
    );
  }

  List<Widget> _fieldsFor(String result) {
    if (result == 'Droga apreendida') {
      return _spaced([_drugRowsField()]);
    }

    final specs = _detailSpecsForResult(result);
    return _spaced(specs.map(_detailField).toList());
  }

  List<Widget> _spaced(List<Widget> fields) {
    return [
      for (var i = 0; i < fields.length; i++) ...[
        fields[i],
        if (i < fields.length - 1) const SizedBox(height: 10),
      ],
    ];
  }

  Widget _detailField(_CloseDetailFieldSpec spec) {
    return TextField(
      controller: _detailController(spec.key),
      keyboardType: spec.keyboardType,
      inputFormatters: spec.inputFormatters,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: _fieldDecoration(hint: spec.label, icon: spec.icon),
    );
  }
}
