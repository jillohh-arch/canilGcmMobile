part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardSteps on _OccurrenceCloseWizardState {
  Widget _buildStep() {
    return switch (_currentStep) {
      0 => _buildReportStep(),
      1 => _buildResultStep(),
      _ => _buildDetailsStep(),
    };
  }

  Widget _buildReportStep() {
    return _StepShell(
      key: const ValueKey('relato'),
      title: 'RELATO FINAL',
      accent: _OccurrenceCloseWizardState._cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InstructionBox(
            text:
                'Descreva brevemente o que ocorreu. Seja objetivo: os eventos já estão registrados na linha do tempo.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reportController,
            maxLines: 6,
            maxLength: 500,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              height: 1.35,
            ),
            decoration: _fieldDecoration(
              hint:
                  'Ex.: Equipe abordou veículo suspeito. K9 indicou presença de entorpecente no porta-malas...',
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _NarrationButton(
              listening: _isListening,
              onPressed: _toggleNarration,
            ),
          ),
        ],
      ),
    );
  }

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
                  'Nenhum detalhe obrigatório para “Sem constatação”. Revise o relato e conclua a ocorrência.',
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
