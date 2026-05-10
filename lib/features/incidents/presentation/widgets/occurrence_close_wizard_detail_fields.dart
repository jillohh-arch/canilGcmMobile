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
