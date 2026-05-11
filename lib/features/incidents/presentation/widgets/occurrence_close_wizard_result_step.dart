part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardResultStep on _OccurrenceCloseWizardState {
  Widget _buildResultStep() {
    return _StepShell(
      key: const ValueKey('resultado'),
      title: 'RESULTADO DA OCORRÊNCIA',
      accent: _OccurrenceCloseWizardState._cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InstructionBox(
            text:
                'Selecione tudo que ocorreu. Pode marcar mais de um resultado.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _occurrenceCloseResultOptions.map((option) {
                  final selected = _selectedResults.contains(option.label);
                  final blockedByNone =
                      _selectedResults.contains('Sem constatação') &&
                      option.label != 'Sem constatação';
                  final hiddenNone =
                      option.label == 'Sem constatação' &&
                      _selectedResults.isNotEmpty &&
                      !selected;

                  if (blockedByNone || hiddenNone) {
                    return const SizedBox.shrink();
                  }

                  return _ResultCard(
                    width: width,
                    option: option,
                    selected: selected,
                    onTap: () => _toggleResult(option.label),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
