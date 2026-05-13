import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelos leves para dados do dashboard vindos do Firestore.
class QuickAction {
  final String id;
  final String nome;
  final String tipo;
  final String icone;
  final String cor;
  final int ordem;

  QuickAction({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.icone,
    required this.cor,
    required this.ordem,
  });

  factory QuickAction.fromJson(Map<String, dynamic> json, String docId) {
    return QuickAction(
      id: docId,
      nome: json['nome'] ?? '',
      tipo: json['tipo'] ?? '',
      icone: json['icone'] ?? 'bolt',
      cor: json['cor'] ?? 'ciano',
      ordem: (json['ordem'] as num?)?.toInt() ?? 0,
    );
  }
}

class DashboardAlert {
  final String id;
  final String titulo;
  final String descricao;
  final String tipo;
  final String prioridade;
  final String cor;
  final String icone;
  final String? caoId;
  final DateTime createdAt;

  DashboardAlert({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.tipo,
    required this.prioridade,
    required this.cor,
    required this.icone,
    this.caoId,
    required this.createdAt,
  });

  factory DashboardAlert.fromJson(Map<String, dynamic> json, String docId) {
    return DashboardAlert(
      id: docId,
      titulo: json['titulo'] ?? '',
      descricao: json['descricao'] ?? '',
      tipo: json['tipo'] ?? '',
      prioridade: json['prioridade'] ?? 'informativo',
      cor: json['cor'] ?? 'ciano',
      icone: json['icone'] ?? 'warning',
      caoId: json['caoId'],
      createdAt: _parseTimestamp(json['createdAt']),
    );
  }
}

class WeatherData {
  final double temperatura;
  final int umidade;
  final String riscoTermico;
  final DateTime atualizadoEm;

  WeatherData({
    required this.temperatura,
    required this.umidade,
    required this.riscoTermico,
    required this.atualizadoEm,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperatura: (json['temperatura'] as num?)?.toDouble() ?? 0,
      umidade: (json['umidade'] as num?)?.toInt() ?? 0,
      riscoTermico: json['riscoTermico'] ?? '--',
      atualizadoEm: _parseTimestamp(json['atualizadoEm']),
    );
  }
}

DateTime _parseTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

/// Service para buscar dados dinâmicos do dashboard no Firestore.
class DashboardService {
  DashboardService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Busca atalhos de registro rápido ativos, ordenados por [ordem].
  Future<List<QuickAction>> getQuickActions() async {
    final snapshot = await _db
        .collection('atalhos_registro')
        .where('ativo', isEqualTo: true)
        .orderBy('ordem')
        .get();

    return snapshot.docs
        .map((doc) => QuickAction.fromJson(doc.data(), doc.id))
        .toList();
  }

  /// Busca alertas ativos para um cão específico (máx [limit]).
  Future<List<DashboardAlert>> getActiveAlerts(
    String dogId, {
    int limit = 2,
  }) async {
    final snapshot = await _db
        .collection('alertas')
        .where('caoId', isEqualTo: dogId)
        .where('ativo', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => DashboardAlert.fromJson(doc.data(), doc.id))
        .toList();
  }

  /// Conta total de alertas ativos para o cão.
  Future<int> countActiveAlerts(String dogId) async {
    final snapshot = await _db
        .collection('alertas')
        .where('caoId', isEqualTo: dogId)
        .where('ativo', isEqualTo: true)
        .count()
        .get();

    return snapshot.count ?? 0;
  }

  /// Busca dados de clima atuais do Firestore.
  Future<WeatherData?> getWeatherData(String localId) async {
    final doc = await _db.collection('climaAtual').doc(localId).get();
    if (!doc.exists || doc.data() == null) return null;
    return WeatherData.fromJson(doc.data()!);
  }

  /// Conta registros do dia para um cão.
  Future<int> countTodayRecords(String dogId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _db
        .collection('registros')
        .where('caoId', isEqualTo: dogId)
        .where('dataHora', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('dataHora', isLessThan: Timestamp.fromDate(endOfDay))
        .count()
        .get();

    return snapshot.count ?? 0;
  }
}
