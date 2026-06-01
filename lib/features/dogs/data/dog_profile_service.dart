import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import 'package:canil_gcm/core/services/audit_service.dart';

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

  int get daysOverdue =>
      isExpired ? DateTime.now().difference(dataVencimento).inDays : 0;
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

/// Modelo de documento/laudo do cão.
class DogDocument {
  final String id;
  final String caoId;
  final String nome;
  final String descricao;
  final String tipo; // 'laudo', 'certificado', 'documento'
  final String url;
  final DateTime dataUpload;
  final String? emissor;

  DogDocument({
    required this.id,
    required this.caoId,
    required this.nome,
    required this.descricao,
    required this.tipo,
    required this.url,
    required this.dataUpload,
    this.emissor,
  });

  factory DogDocument.fromJson(Map<String, dynamic> json, String docId) {
    return DogDocument(
      id: docId,
      caoId: json['caoId'] ?? '',
      nome: json['nome'] ?? '',
      descricao: json['descricao'] ?? '',
      tipo: json['tipo'] ?? 'documento',
      url: json['url'] ?? '',
      dataUpload: _parseTs(json['dataUpload']),
      emissor: json['emissor'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caoId': caoId,
      'nome': nome,
      'descricao': descricao,
      'tipo': tipo,
      'url': url,
      'dataUpload': Timestamp.fromDate(dataUpload),
      if (emissor != null) 'emissor': emissor,
    };
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
    try {
      final snapshot = await _db
          .collection('vacinas')
          .where('caoId', isEqualTo: dogId)
          .where('ativo', isEqualTo: true)
          .orderBy('dataVencimento', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => VaccineRecord.fromJson(doc.data(), doc.id))
          .toList();
    } catch (_) {
      // Fallback: sem orderBy (índice composto pode não existir)
      try {
        final snapshot = await _db
            .collection('vacinas')
            .where('caoId', isEqualTo: dogId)
            .get();

        final vaccines = snapshot.docs
            .where((doc) => doc.data()['ativo'] == true)
            .map((doc) => VaccineRecord.fromJson(doc.data(), doc.id))
            .toList();
        vaccines.sort((a, b) => b.dataVencimento.compareTo(a.dataVencimento));
        return vaccines;
      } catch (_) {
        // Último fallback: busca todas e filtra localmente
        final snapshot = await _db.collection('vacinas').get();
        final vaccines = snapshot.docs
            .where((doc) {
              final data = doc.data();
              return data['caoId'] == dogId && data['ativo'] == true;
            })
            .map((doc) => VaccineRecord.fromJson(doc.data(), doc.id))
            .toList();
        vaccines.sort((a, b) => b.dataVencimento.compareTo(a.dataVencimento));
        return vaccines;
      }
    }
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

  /// Busca documentos/laudos do cão.
  Future<List<DogDocument>> getDocuments(String dogId) async {
    try {
      final snapshot = await _db
          .collection('documentos')
          .where('caoId', isEqualTo: dogId)
          .orderBy('dataUpload', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => DogDocument.fromJson(doc.data(), doc.id))
          .toList();
    } catch (_) {
      // Fallback sem orderBy
      final snapshot = await _db
          .collection('documentos')
          .where('caoId', isEqualTo: dogId)
          .get();

      final docs = snapshot.docs
          .map((doc) => DogDocument.fromJson(doc.data(), doc.id))
          .toList();
      docs.sort((a, b) => b.dataUpload.compareTo(a.dataUpload));
      return docs;
    }
  }

  /// Faz upload de um arquivo e salva o documento no Firestore.
  Future<DogDocument> uploadDocument({
    required String dogId,
    required String nome,
    required String descricao,
    required String tipo,
    required File file,
    String? emissor,
  }) async {
    final storage = FirebaseStorage.instance;
    final ext = file.path.split('.').last.toLowerCase();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = storage.ref('documentos/$dogId/$fileName');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    final docData = DogDocument(
      id: '',
      caoId: dogId,
      nome: nome,
      descricao: descricao,
      tipo: tipo,
      url: url,
      dataUpload: DateTime.now(),
      emissor: emissor,
    );

    final data = docData.toJson()
      ..['audit_trail'] = [AuditService.buildInlineEntry(action: 'created')];

    final docRef = await _db.collection('documentos').add(data);

    return DogDocument(
      id: docRef.id,
      caoId: dogId,
      nome: nome,
      descricao: descricao,
      tipo: tipo,
      url: url,
      dataUpload: DateTime.now(),
      emissor: emissor,
    );
  }
}
