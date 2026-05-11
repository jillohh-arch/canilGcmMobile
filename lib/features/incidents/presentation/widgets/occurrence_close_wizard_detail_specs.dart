part of 'occurrence_close_wizard.dart';

class _CloseDetailFieldSpec {
  final String label;
  final String key;
  final IconData icon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _CloseDetailFieldSpec({
    required this.label,
    required this.key,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });
}

List<_CloseDetailFieldSpec> _detailSpecsForResult(String result) {
  if (result == 'Objetos apreendidos') {
    return [
      const _CloseDetailFieldSpec(
        label: 'Descrição dos objetos',
        key: 'objetos_descricao',
        icon: Icons.inventory_2_rounded,
      ),
      _CloseDetailFieldSpec(
        label: 'Quantidade',
        key: 'objetos_quantidade',
        icon: Icons.numbers_rounded,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    ];
  }

  if (result == 'Veículo detido') {
    return const [
      _CloseDetailFieldSpec(
        label: 'Tipo de veículo',
        key: 'veiculo_tipo',
        icon: Icons.directions_car_rounded,
      ),
      _CloseDetailFieldSpec(
        label: 'Placa',
        key: 'veiculo_placa',
        icon: Icons.pin_rounded,
      ),
    ];
  }

  if (result == 'Indivíduo detido') {
    return [
      _CloseDetailFieldSpec(
        label: 'Quantidade de indivíduos',
        key: 'individuo_quantidade',
        icon: Icons.group_rounded,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const _CloseDetailFieldSpec(
        label: 'Destino / apresentação',
        key: 'individuo_destino',
        icon: Icons.account_balance_rounded,
      ),
    ];
  }

  if (result == 'Apoio prestado') {
    return const [
      _CloseDetailFieldSpec(
        label: 'Apoio prestado a',
        key: 'apoio_destino',
        icon: Icons.handshake_rounded,
      ),
      _CloseDetailFieldSpec(
        label: 'Observação do apoio',
        key: 'apoio_observacao',
        icon: Icons.notes_rounded,
      ),
    ];
  }

  if (result == 'BO elaborado') {
    return const [
      _CloseDetailFieldSpec(
        label: 'Número do BO',
        key: 'bo_numero',
        icon: Icons.article_rounded,
      ),
    ];
  }

  if (result == 'Encaminhamento médico') {
    return const [
      _CloseDetailFieldSpec(
        label: 'Local de encaminhamento',
        key: 'encaminhamento_local',
        icon: Icons.local_hospital_rounded,
      ),
      _CloseDetailFieldSpec(
        label: 'Observação médica',
        key: 'encaminhamento_observacao',
        icon: Icons.medical_information_rounded,
      ),
    ];
  }

  return [
    _CloseDetailFieldSpec(
      label: 'Descrição',
      key: '${result}_descricao',
      icon: Icons.description_rounded,
    ),
  ];
}
