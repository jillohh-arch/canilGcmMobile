import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/canonical/restriction/canonical_operational_restriction_parser.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_read_gateway.dart';

/// Leitor canônico de UMA restrição operacional.
///
/// Um único `get()` de documento em
/// `dogs/{dogId}/operational_restrictions/{restrictionId}`. Sem query, sem
/// collection scan, sem listener, sem escrita: este gateway não tem writer.
final class FirestoreHealthRestrictionReadGateway
    implements HealthRestrictionReadGateway {
  FirestoreHealthRestrictionReadGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  }) async {
    // Validação local antes de qualquer I/O. IDs são usados como identidade
    // opaca: só o whitespace de borda é descartado, nenhuma normalização
    // semântica (case, prefixo, separador) é aplicada.
    final normalizedDogId = dogId.trim();
    if (normalizedDogId.isEmpty) {
      return const HealthRestrictionReadError(
        HealthRestrictionReadFailure(
          code: HealthRestrictionReadErrorCode.validation,
          message: 'K9 não informado.',
          field: 'dogId',
        ),
      );
    }
    final normalizedRestrictionId = restrictionId.trim();
    if (normalizedRestrictionId.isEmpty) {
      return const HealthRestrictionReadError(
        HealthRestrictionReadFailure(
          code: HealthRestrictionReadErrorCode.validation,
          message: 'Restrição não informada.',
          field: 'restrictionId',
        ),
      );
    }
    // `restriction:<id>` é o id de projeção do AttentionItem (B4-A), não o
    // Firestore document id canônico. O gateway recebe apenas restrictionId
    // puro: aceitar o prefixo faria um get() no path errado e devolveria
    // not-found por acaso, mascarando o acoplamento indevido com a projeção. A
    // tradução pertence ao consumidor (B4-C), fora deste gateway.
    if (normalizedRestrictionId.startsWith('restriction:')) {
      return const HealthRestrictionReadError(
        HealthRestrictionReadFailure(
          code: HealthRestrictionReadErrorCode.validation,
          message: 'Identificador de restrição inválido.',
          field: 'restrictionId',
        ),
      );
    }

    try {
      final snapshot = await _firestore
          .collection('dogs')
          .doc(normalizedDogId)
          .collection('operational_restrictions')
          .doc(normalizedRestrictionId)
          .get();

      if (!snapshot.exists) {
        // Ausente é ausente. Nenhum detalhe é fabricado a partir de
        // ReadinessRestriction, AttentionItem ou health_summary.
        return const HealthRestrictionReadError(
          HealthRestrictionReadFailure(
            code: HealthRestrictionReadErrorCode.notFound,
            message: 'Restrição não encontrada.',
          ),
        );
      }

      final data = snapshot.data();
      if (data == null) {
        return const HealthRestrictionReadError(
          HealthRestrictionReadFailure(
            code: HealthRestrictionReadErrorCode.integrity,
            message: 'Não foi possível ler os dados da restrição.',
          ),
        );
      }

      return HealthRestrictionReadSuccess(
        CanonicalOperationalRestrictionParser.parseDocument(
          documentId: snapshot.id,
          queryDogId: normalizedDogId,
          data: data,
        ),
      );
    } on CanonicalRestrictionParseException catch (e) {
      return HealthRestrictionReadError(_mapParseFailure(e));
    } on FirebaseException catch (e) {
      return HealthRestrictionReadError(_mapFirestoreFailure(e));
    } catch (e) {
      return HealthRestrictionReadError(
        HealthRestrictionReadFailure(
          code: HealthRestrictionReadErrorCode.unexpected,
          message: 'Não foi possível carregar a restrição.',
          field: e.runtimeType.toString(),
        ),
      );
    }
  }

  /// Contrato violado no documento persistido nunca degrada para "sem dados".
  static HealthRestrictionReadFailure _mapParseFailure(
    CanonicalRestrictionParseException e,
  ) {
    final message = switch (e.code) {
      CanonicalRestrictionParseErrorCode.unsupportedSchemaVersion =>
        'Esta restrição foi registrada em uma versão mais recente do '
            'aplicativo. Atualize para visualizá-la.',
      CanonicalRestrictionParseErrorCode.identityMismatch ||
      CanonicalRestrictionParseErrorCode.malformed =>
        'Os dados desta restrição estão inconsistentes e não podem ser '
            'exibidos com segurança.',
    };
    return HealthRestrictionReadFailure(
      code: HealthRestrictionReadErrorCode.integrity,
      message: message,
      field: e.field,
    );
  }

  /// Códigos do Firestore, não de Cloud Functions: os vocabulários diferem
  /// (`not-found` de documento vs `not-found` de callable), então o mapper do
  /// fluxo de mutação não é reaproveitado aqui.
  static HealthRestrictionReadFailure _mapFirestoreFailure(
    FirebaseException e,
  ) {
    return switch (e.code) {
      'permission-denied' => const HealthRestrictionReadFailure(
        code: HealthRestrictionReadErrorCode.permissionDenied,
        message: 'Você não possui autorização para consultar esta restrição.',
      ),
      'unavailable' || 'deadline-exceeded' || 'aborted' =>
        const HealthRestrictionReadFailure(
          code: HealthRestrictionReadErrorCode.unavailable,
          message:
              'Não foi possível consultar a restrição agora. Verifique a '
              'conexão e tente novamente.',
        ),
      'not-found' => const HealthRestrictionReadFailure(
        code: HealthRestrictionReadErrorCode.notFound,
        message: 'Restrição não encontrada.',
      ),
      _ => HealthRestrictionReadFailure(
        code: HealthRestrictionReadErrorCode.unexpected,
        message: 'Não foi possível carregar a restrição.',
        field: e.code,
      ),
    };
  }
}
