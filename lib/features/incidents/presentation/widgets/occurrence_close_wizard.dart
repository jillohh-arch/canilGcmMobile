import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
      accent: _cyan,
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
      accent: _cyan,
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
                children: _resultOptions.map((option) {
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
      accent: _cyan,
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

  Widget _buildDynamicDetailBlock(String result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel.withAlpha(230),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cyan.withAlpha(75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.toUpperCase(),
            style: GoogleFonts.robotoMono(
              color: _cyan,
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
    List<Widget> spaced(List<Widget> fields) {
      return [
        for (var i = 0; i < fields.length; i++) ...[
          fields[i],
          if (i < fields.length - 1) const SizedBox(height: 10),
        ],
      ];
    }

    if (result == 'Droga apreendida') {
      return spaced([_drugRowsField()]);
    }
    if (result == 'Objetos apreendidos') {
      return spaced([
        _detailField(
          'Descrição dos objetos',
          'objetos_descricao',
          Icons.inventory_2_rounded,
        ),
        _detailField(
          'Quantidade',
          'objetos_quantidade',
          Icons.numbers_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ]);
    }
    if (result == 'Veículo detido') {
      return spaced([
        _detailField(
          'Tipo de veículo',
          'veiculo_tipo',
          Icons.directions_car_rounded,
        ),
        _detailField('Placa', 'veiculo_placa', Icons.pin_rounded),
      ]);
    }
    if (result == 'Indivíduo detido') {
      return spaced([
        _detailField(
          'Quantidade de indivíduos',
          'individuo_quantidade',
          Icons.group_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _detailField(
          'Destino / apresentação',
          'individuo_destino',
          Icons.account_balance_rounded,
        ),
      ]);
    }
    if (result == 'Apoio prestado') {
      return spaced([
        _detailField(
          'Apoio prestado a',
          'apoio_destino',
          Icons.handshake_rounded,
        ),
        _detailField(
          'Observação do apoio',
          'apoio_observacao',
          Icons.notes_rounded,
        ),
      ]);
    }
    if (result == 'BO elaborado') {
      return spaced([
        _detailField('Número do BO', 'bo_numero', Icons.article_rounded),
      ]);
    }
    if (result == 'Encaminhamento médico') {
      return spaced([
        _detailField(
          'Local de encaminhamento',
          'encaminhamento_local',
          Icons.local_hospital_rounded,
        ),
        _detailField(
          'Observação médica',
          'encaminhamento_observacao',
          Icons.medical_information_rounded,
        ),
      ]);
    }
    return spaced([
      _detailField(
        'Descrição',
        '${result}_descricao',
        Icons.description_rounded,
      ),
    ]);
  }

  Widget _detailField(
    String label,
    String key,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? suffixText,
  }) {
    return TextField(
      controller: _detailController(key),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: _fieldDecoration(
        hint: label,
        icon: icon,
        suffixText: suffixText,
      ),
    );
  }

  Widget _drugRowsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(_drugEntries.length, _buildDrugEntryRow),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: widget.isSaving
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _drugEntries.add(_DrugEntry()));
                },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            'ADICIONAR ENTORPECENTE',
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _cyan,
            side: BorderSide(color: _cyan.withAlpha(120)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrugEntryRow(int index) {
    final entry = _drugEntries[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: _drugOptions.contains(entry.type)
                  ? entry.type
                  : _drugOptions.first,
              dropdownColor: _panel,
              iconEnabledColor: _cyan,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: _fieldDecoration(
                hint: 'Tipo de entorpecente',
                icon: Icons.science_rounded,
              ),
              items: _drugOptions
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
                      setState(() => entry.type = value);
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
                        setState(() {
                          final removed = _drugEntries.removeAt(index);
                          removed.dispose();
                        });
                      },
                icon: const Icon(Icons.remove_circle_rounded),
                color: _red,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
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

class _SavingNotice extends StatelessWidget {
  const _SavingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF082031),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E5FF).withAlpha(110)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withAlpha(24),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Finalizando ocorrência... sincronizando dados e anexos.',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosingRoadmap extends StatelessWidget {
  final int currentStep;

  const _ClosingRoadmap({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['RELATO', 'RESULTADO', 'DETALHES'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E5FF).withAlpha(75)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_rounded,
                color: Color(0xFFFFB84D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ROTEIRO DE ENCERRAMENTO',
                  style: GoogleFonts.robotoMono(
                    color: const Color(0xFFFFB84D),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Text(
                '${currentStep + 1} / 3',
                style: GoogleFonts.robotoMono(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (index) {
              final active = index <= currentStep;
              final done = index < currentStep;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? const Color(0xFF00E5FF).withAlpha(25)
                                  : Colors.transparent,
                              border: Border.all(
                                color: active
                                    ? const Color(0xFF00E5FF)
                                    : Colors.white24,
                              ),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF00E5FF,
                                        ).withAlpha(70),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: done
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Color(0xFF00F5A0),
                                      size: 20,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: GoogleFonts.oxanium(
                                        color: active
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white38,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels[index],
                            maxLines: 1,
                            style: GoogleFonts.robotoMono(
                              color: active
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white30,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < 2)
                      Container(
                        width: 34,
                        height: 2,
                        color: index < currentStep
                            ? const Color(0xFF00F5A0)
                            : Colors.white12,
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget child;

  const _StepShell({
    super.key,
    required this.title,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: GoogleFonts.robotoMono(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: accent.withAlpha(120))),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _InstructionBox extends StatelessWidget {
  final String text;

  const _InstructionBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF082031),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFF00E5FF), width: 3),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NarrationButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onPressed;

  const _NarrationButton({required this.listening, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
        size: 17,
      ),
      label: Text(listening ? 'PARAR NARRAÇÃO' : 'NARRAÇÃO'),
      style: OutlinedButton.styleFrom(
        foregroundColor: listening
            ? const Color(0xFFFF3B5C)
            : const Color(0xFF00E5FF),
        side: BorderSide(
          color: listening
              ? const Color(0xFFFF3B5C).withAlpha(145)
              : const Color(0xFF00E5FF).withAlpha(145),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.robotoMono(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final double width;
  final _ResultOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.width,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? option.color.withAlpha(28)
                : const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? option.color : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: option.color.withAlpha(40), blurRadius: 14)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: option.color.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(option.icon, color: option.color, size: 20),
              ),
              const SizedBox(height: 9),
              Text(
                option.label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.camera_alt_rounded,
            color: Color(0xFFB8C2D6),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Anexos e fotos vinculados à ocorrência serão mantidos no relatório final.',
              style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrugEntry {
  String type;
  final TextEditingController quantityController;

  _DrugEntry() : type = 'Maconha', quantityController = TextEditingController();

  void dispose() {
    quantityController.dispose();
  }
}

class _ResultOption {
  final String label;
  final IconData icon;
  final Color color;

  const _ResultOption({
    required this.label,
    required this.icon,
    required this.color,
  });
}
