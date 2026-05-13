import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de vacina vindo do Firestore.
class VaccineRecord {
  final String id;
  final String caoId;
  final String nome;
  final DateTime dataAplicacao;
  final DateTime dataVencimento;
  final String status;

  VaccineRecord({
    required this.id,
    required this.caoId,
    required this.nome,
    required this.dataAplicacao,
    required this.dataVencimento,
    required this.status,
  });

  factory VaccineRecord.fromJson(Map<String, dynamic> json, String docId) {
    return VaccineRecord(
      id: docId,
      caoId: json['caoId'] ?? '',
      nome: json['nome'] ?? '',
      dataAplicacao: _parseTs(json['dataAplicacao']),
      dataVencimento: _parseTs(json['dataVencimento']),
      status: json['status'] ?? '',
    );
  }

  bool get isExpired => DateTime.now().isAfter(dataVencimento);

  int get daysOverdue => isExpired
      ? DateTime.now().difference(dataVencimento).inDays
      : 0;
}

/// Modelo de aptidão operacional.
class DogAptitude {
  final String id;
  final String nome;
  final String tipo;
  final String status;
  final int ordem;
  final String cor;
  final String icone;

  DogAptitude({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.status,
    required this.ordem,
    required this.cor,
    required this.icone,
  });

  factory DogAptitude.fromJson(Map<String, dynamic> json, String docId) {
    return DogAptitude(
      id: docId,
      nome: json['nome'] ?? '',
      tipo: json['tipo'] ?? '',
      status: json['status'] ?? 'inativo',
      ordem: (json['ordem'] as num?)?.toInt() ?? 0,
      cor: json['cor'] ?? 'ciano',
      icone: json['icone'] ?? 'shield',
    );
  }
}

/// Modelo de registro recente.
class RecentRecord {
  final String id;
  final String tipo;
  final String titulo;
  final DateTime dataHora;

  RecentRecord({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.dataHora,
  });

  factory RecentRecord.fromJson(Map<String, dynamic> json, String docId) {
    return RecentRecord(
      id: docId,
      tipo: json['tipo'] ?? '',
      titulo: json['titulo'] ?? json['tipo'] ?? '',
      dataHora: _parseTs(json['dataHora']),
    );
  }
}

DateTime _parseTs(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

/// Service para buscar dados complementares do perfil do cão.
class DogProfileService {
  DogProfileService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Busca vacinas do cão, ordenadas por dataVencimento desc.
  Future<List<VaccineRecord>> getVaccines(String dogId) async {
    final snapshot = await _db
        .collection('vacinas')
        .where('caoId', isEqualTo: dogId)
        .where('ativo', isEqualTo: true)
        .orderBy('dataVencimento', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => VaccineRecord.fromJson(doc.data(), doc.id))
        .toList();
  }

  /// Busca aptidões operacionais do cão (subcoleção ou coleção).
  Future<List<DogAptitude>> getAptitudes(String dogId) async {
    // Tenta subcoleção primeiro
    final subSnapshot = await _db
        .collection('caes')
        .doc(dogId)
        .collection('aptidoes')
        .where('ativo', isEqualTo: true)
        .orderBy('ordem')
        .get();

    if (subSnapshot.docs.isNotEmpty) {
      return subSnapshot.docs
          .map((doc) => DogAptitude.fromJson(doc.data(), doc.id))
          .toList();
    }

    // Fallback: coleção raiz
    final rootSnapshot = await _db
        .collection('aptidoes')
        .where('caoId', isEqualTo: dogId)
        .where('ativo', isEqualTo: true)
        .orderBy('ordem')
        .get();

    return rootSnapshot.docs
        .map((doc) => DogAptitude.fromJson(doc.data(), doc.id))
        .toList();
  }

  /// Busca últimos registros do cão (máx [limit]).
  Future<List<RecentRecord>> getRecentRecords(
    String dogId, {
    int limit = 3,
  }) async {
    final snapshot = await _db
        .collection('registros')
        .where('caoId', isEqualTo: dogId)
        .orderBy('dataHora', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => RecentRecord.fromJson(doc.data(), doc.id))
        .toList();
  }

  /// Busca nome do condutor pelo ID.
  Future<String?> getHandlerName(String handlerId) async {
    final doc = await _db.collection('users').doc(handlerId).get();
    if (!doc.exists) return null;
    final data = doc.data();
    return data?['name'] ?? data?['nome'] ?? data?['displayName'];
  }
}
