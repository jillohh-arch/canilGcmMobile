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
}
