import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

part 'occurrence_close_wizard_widgets.dart';
part 'occurrence_close_wizard_result_card.dart';
part 'occurrence_close_wizard_models.dart';
part 'occurrence_close_wizard_drug_fields.dart';
part 'occurrence_close_wizard_steps.dart';

class OccurrenceCloseWizard extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<Map<String, dynamic>> onFinish;
  final bool isSaving;

  const OccurrenceCloseWizard({
    super.key,
    required this.onCancel,
    required this.onFinish,
    this.isSaving = false,
  });

  @override
  State<OccurrenceCloseWizard> createState() => _OccurrenceCloseWizardState();
}

class _OccurrenceCloseWizardState extends State<OccurrenceCloseWizard> {
  static const _bg = Color(0xFF070B14);
  static const _panel = Color(0xFF0B1220);
  static const _cyan = Color(0xFF00E5FF);
  static const _red = Color(0xFFFF3B5C);

  int _currentStep = 0;
  late final stt.SpeechToText _speech;
  bool _speechReady = false;
  bool _isListening = false;

  final _reportController = TextEditingController();
  final Set<String> _selectedResults = {};
  final Map<String, TextEditingController> _detailControllers = {};
  final List<_DrugEntry> _drugEntries = [_DrugEntry()];

  static const _drugOptions = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Sintéticos',
    'Nose MP',
    'Outros',
  ];

  final List<_ResultOption> _resultOptions = const [
    _ResultOption(
      label: 'Droga apreendida',
      icon: Icons.science_rounded,
      color: Color(0xFFA855F7),
    ),
    _ResultOption(
      label: 'Objetos apreendidos',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFFFFB84D),
    ),
    _ResultOption(
      label: 'Veículo detido',
      icon: Icons.directions_car_rounded,
      color: Color(0xFF00B8FF),
    ),
    _ResultOption(
      label: 'Indivíduo detido',
      icon: Icons.person_pin_rounded,
      color: Color(0xFFFF8A00),
    ),
    _ResultOption(
      label: 'Apoio prestado',
      icon: Icons.handshake_rounded,
      color: Color(0xFF00F5A0),
    ),
    _ResultOption(
      label: 'BO elaborado',
      icon: Icons.article_rounded,
      color: Color(0xFF00E5FF),
    ),
    _ResultOption(
      label: 'Encaminhamento médico',
      icon: Icons.local_hospital_rounded,
      color: Color(0xFFFF3B5C),
    ),
    _ResultOption(
      label: 'Sem constatação',
      icon: Icons.highlight_off_rounded,
      color: Color(0xFFB8C2D6),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final ready = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() => _speechReady = ready);
  }

  @override
  void dispose() {
    _speech.cancel();
    _reportController.dispose();
    for (final controller in _detailControllers.values) {
      controller.dispose();
    }
    for (final entry in _drugEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _toggleNarration() async {
    if (widget.isSaving) return;

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechReady) await _initSpeech();
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível iniciar a narração por voz.'),
        ),
      );
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'pt_BR',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        setState(() {
          _reportController.text = words;
          _reportController.selection = TextSelection.collapsed(
            offset: _reportController.text.length,
          );
        });
      },
    );
  }

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

  void _finish() {
    if (widget.isSaving) return;

    final details = <String, dynamic>{};
    _detailControllers.forEach((key, controller) {
      details[key] = controller.text.trim();
    });
    if (_selectedResults.contains('Droga apreendida')) {
      final drugs = _drugEntries
          .map(
            (entry) => {
              'tipo': entry.type,
              'quantidade': entry.quantityController.text.trim(),
            },
          )
          .where(
            (entry) =>
                entry['tipo']!.trim().isNotEmpty ||
                entry['quantidade']!.trim().isNotEmpty,
          )
          .toList();
      details['drogas'] = drugs;
      if (drugs.isNotEmpty) {
        details['droga_tipo'] = drugs.first['tipo'];
        details['droga_quantidade'] = drugs.first['quantidade'];
      }
    }

    widget.onFinish({
      'report': _reportController.text.trim(),
      'results': _selectedResults.toList(),
      'details': details,
    });
  }

  TextEditingController _detailController(String key) {
    return _detailControllers.putIfAbsent(key, TextEditingController.new);
  }

  void _addDrugEntry() {
    setState(() => _drugEntries.add(_DrugEntry()));
  }

  void _updateDrugEntryType(_DrugEntry entry, String type) {
    setState(() => entry.type = type);
  }

  void _removeDrugEntry(int index) {
    setState(() {
      final removed = _drugEntries.removeAt(index);
      removed.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClosingRoadmap(currentStep: _currentStep),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildStep(),
        ),
        const SizedBox(height: 16),
        if (widget.isSaving) ...[
          const _SavingNotice(),
          const SizedBox(height: 12),
        ],
        _buildNavigation(),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    IconData? icon,
    String? suffixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.white38),
      counterStyle: GoogleFonts.robotoMono(color: Colors.white38, fontSize: 9),
      prefixIcon: icon == null ? null : Icon(icon, color: _cyan, size: 18),
      suffixText: suffixText,
      suffixStyle: GoogleFonts.robotoMono(
        color: _cyan,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
      filled: true,
      fillColor: const Color(0xFF0A1322),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _cyan.withAlpha(55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _cyan, width: 1.4),
      ),
    );
  }

  void _toggleResult(String label) {
    setState(() {
      if (label == 'Sem constatação') {
        if (_selectedResults.contains(label)) {
          _selectedResults.remove(label);
        } else {
          _selectedResults
            ..clear()
            ..add(label);
        }
        return;
      }

      _selectedResults.remove('Sem constatação');
      if (_selectedResults.contains(label)) {
        _selectedResults.remove(label);
      } else {
        _selectedResults.add(label);
      }
    });
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
              side: BorderSide(color: _cyan.withAlpha(70)),
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
              backgroundColor: _currentStep == 2 ? _red : _cyan,
              foregroundColor: _currentStep == 2 ? Colors.white : _bg,
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
