import 'package:flutter/material.dart';

abstract final class ActivitySubtypeIds {
  static const detection = 'Detecção';
  static const supportVehicle = 'Apoio à Viatura/Guarnição';
  static const missingPerson = 'Busca de Pessoa';
  static const serviceOrder = 'Ordem de Serviço (O.S.)';
  static const event = 'Palestra/Evento (RP)';

  static const obedience = 'Obediência';
  static const scentWork = 'Faro';
  static const guardProtection = 'Guarda e Proteção';
  static const searchCapture = 'Busca & Captura';
  static const physicalConditioning = 'Condicionamento Físico';

  static const consultation = 'Consulta';
  static const vaccine = 'Vacina';
  static const exam = 'Exame';
  static const bath = 'Banho';

  static const feeding = 'Alimentação';
  static const cleaning = 'Limpeza';
  static const walk = 'Passeio';
  static const rest = 'Descanso';
  static const play = 'Brincadeira';
  static const brushing = 'Escovação';
  static const other = 'Outros';
  static const narcoticsSearch = 'Busca de Entorpecentes';
}

abstract final class ActivityCardCatalog {
  static const occurrenceCards = [
    {
      'id': ActivitySubtypeIds.detection,
      'image': 'assets/images/card_deteccao.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': ActivitySubtypeIds.supportVehicle,
      'image': 'assets/images/card_apoio.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': ActivitySubtypeIds.missingPerson,
      'image': 'assets/images/card_busca_captura.png',
      'glow': Colors.redAccent,
    },
    {
      'id': ActivitySubtypeIds.serviceOrder,
      'image': 'assets/images/card_ordem_servico.png',
      'glow': Colors.blueGrey,
    },
    {
      'id': ActivitySubtypeIds.event,
      'image': 'assets/images/card_palestras.png',
      'glow': Colors.greenAccent,
    },
    {
      'id': ActivitySubtypeIds.other,
      'image': 'assets/images/card_outros.png',
      'glow': Colors.white54,
    },
  ];

  static const trainingCards = [
    {
      'id': ActivitySubtypeIds.obedience,
      'image': 'assets/images/card_obediencia.png',
      'glow': Colors.blueAccent,
    },
    {
      'id': ActivitySubtypeIds.scentWork,
      'image': 'assets/images/card_faro.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': ActivitySubtypeIds.guardProtection,
      'image': 'assets/images/card_protecao.png',
      'glow': Colors.redAccent,
    },
    {
      'id': ActivitySubtypeIds.searchCapture,
      'image': 'assets/images/card_treino_busca.png',
      'glow': Colors.greenAccent,
    },
    {
      'id': ActivitySubtypeIds.physicalConditioning,
      'image': 'assets/images/card_condicionamento.png',
      'glow': Colors.cyanAccent,
    },
  ];

  static const healthCards = [
    {
      'id': ActivitySubtypeIds.consultation,
      'image': 'assets/images/card_consulta.png',
      'glow': Colors.tealAccent,
    },
    {
      'id': ActivitySubtypeIds.vaccine,
      'image': 'assets/images/card_vacina.png',
      'glow': Colors.lightBlueAccent,
    },
    {
      'id': ActivitySubtypeIds.exam,
      'image': 'assets/images/card_exame.png',
      'glow': Colors.indigoAccent,
    },
    {
      'id': ActivitySubtypeIds.bath,
      'image': 'assets/images/card_banho.png',
      'glow': Colors.cyanAccent,
    },
  ];

  static const routineCards = [
    {
      'id': ActivitySubtypeIds.feeding,
      'image': 'assets/images/card_alimentacao.png',
      'glow': Colors.amber,
    },
    {
      'id': ActivitySubtypeIds.cleaning,
      'image': 'assets/images/card_limpeza.png',
      'glow': Colors.orange,
    },
    {
      'id': ActivitySubtypeIds.walk,
      'image': 'assets/images/card_passeio.png',
      'glow': Colors.lightGreen,
    },
    {
      'id': ActivitySubtypeIds.rest,
      'image': 'assets/images/card_descanso.png',
      'glow': Colors.deepOrangeAccent,
    },
    {
      'id': ActivitySubtypeIds.play,
      'image': 'assets/images/card_brincadeira.png',
      'glow': Colors.yellowAccent,
    },
    {
      'id': ActivitySubtypeIds.brushing,
      'image': 'assets/images/card_escovacao.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': ActivitySubtypeIds.other,
      'image': 'assets/images/card_outros.png',
      'glow': Colors.white54,
    },
  ];

  static List<Map<String, dynamic>> forCategory(String category) {
    if (category == 'Treino') return trainingCards;
    if (category == 'Saude') return healthCards;
    if (category == 'Rotina') return routineCards;
    return occurrenceCards;
  }

  static Map<String, dynamic>? findById({
    required String category,
    required String? id,
  }) {
    if (id == null) return null;
    for (final card in forCategory(category)) {
      if (card['id'] == id) {
        return card;
      }
    }
    return null;
  }

  static String? imageFor({required String category, required String? id}) {
    return findById(category: category, id: id)?['image'] as String?;
  }

  static Color glowFor({
    required String category,
    required String? id,
    required Color fallback,
  }) {
    final glow = findById(category: category, id: id)?['glow'];
    return glow is Color ? glow : fallback;
  }
}
