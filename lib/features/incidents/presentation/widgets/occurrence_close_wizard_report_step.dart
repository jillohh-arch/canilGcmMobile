part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardReportStep on _OccurrenceCloseWizardState {
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
}
