part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardDetailsStep on _OccurrenceCloseWizardState {
  Widget _buildDetailsStep() {
    final actionableResults = _selectedResults
        .where((result) => result != 'Sem constatação')
        .toList();

    return _StepShell(
      key: const ValueKey('detalhes'),
      title: 'DETALHES E EVIDÊNCIAS',
      accent: _OccurrenceCloseWizardState._cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actionableResults.isEmpty)
            _InstructionBox(
              text:
                  'Nenhum detalhe obrigatório para "Sem constatação". Revise o relato e conclua a ocorrência.',
            )
          else ...[
            _InstructionBox(
              text:
                  'Preencha apenas os campos ligados ao resultado selecionado.',
            ),
            const SizedBox(height: 14),
            ...actionableResults.map(_buildDynamicDetailBlock),
          ],
          const SizedBox(height: 12),
          _EvidenceNotice(),
        ],
      ),
    );
  }
}
