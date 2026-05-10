part of 'occurrence_close_wizard.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceCloseWizardNavigation on _OccurrenceCloseWizardState {
  void _nextStep() {
    if (widget.isSaving) return;

    if (_currentStep == 0 && _reportController.text.trim().isEmpty) {
      _showMessage('Informe o relato final ou use a narração por voz.');
      return;
    }
    if (_currentStep == 1 && _selectedResults.isEmpty) {
      _showMessage('Selecione pelo menos um resultado da ocorrência.');
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      return;
    }
    _finish();
  }

  void _previousStep() {
    if (widget.isSaving) return;

    if (_currentStep == 0) {
      widget.onCancel();
      return;
    }
    setState(() => _currentStep--);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildNavigation() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.isSaving ? null : _previousStep,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Colors.white70,
              side: BorderSide(
                color: _OccurrenceCloseWizardState._cyan.withAlpha(70),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _currentStep == 0 ? 'CANCELAR' : 'VOLTAR',
              style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: widget.isSaving ? null : _nextStep,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 17),
              backgroundColor: _currentStep == 2
                  ? _OccurrenceCloseWizardState._red
                  : _OccurrenceCloseWizardState._cyan,
              foregroundColor: _currentStep == 2
                  ? Colors.white
                  : _OccurrenceCloseWizardState._bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(
              _currentStep == 2 ? 'CONCLUIR OCORRÊNCIA' : 'PRÓXIMO',
              style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
