// Copyright 2024 GCM Health. All rights reserved.
//
// CANONICAL HEALTH TIMELINE ID DERIVER — Pure cross-language implementation.
//
// Derives deterministic timeline document IDs that match the TypeScript
// health_timeline_projection.ts implementation exactly.
//
// Formula (O3-D6 FROZEN):
//   timelineId = "tl1_" + SHA256_UTF8(jsonEncode([
//     "health_timeline_v1",
//     "dogs/{dogId}/{sourceCollection}",
//     sourceId
//   ]))
//
// ESCOPO: Somente esta função. ZERO Firestore. ZERO adapter. ZERO wiring.
//
// Coverage: PROVEN_CORRELATABLE_ORIGINS=0

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Coleções de origem permitidas para a timeline de saúde.
///
/// Usada como tipo para prevenir pass-through de strings ambíguas.
enum CanonicalHealthTimelineSourceCollection {
  /// Meal logs collection.
  mealLogs('meal_logs'),

  /// Supplement logs collection.
  supplementLogs('supplement_logs');

  const CanonicalHealthTimelineSourceCollection(this.firestoreCollection);

  /// O nome da coleção Firestore (ex: "meal_logs").
  final String firestoreCollection;
}

/// Constante de versão do contrato de timeline.
///
/// Deve corresponder exatamente a "health_timeline_v1" usado em
/// health_timeline_projection.ts.
const String _kHealthTimelineVersion = 'health_timeline_v1';

/// Prefixo do timeline ID.
///
/// Deve corresponder exatamente a "tl1_" usado em
/// health_timeline_projection.ts.
const String _kTimelineIdPrefix = 'tl1_';

/// Builds the exact dog-scoped source collection path.
///
/// Exemplo:
///   canonicalHealthTimelineSourcePath(
///     dogId: 'dog123',
///     sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
///   )
///   → 'dogs/dog123/meal_logs'
String canonicalHealthTimelineSourcePath({
  required String dogId,
  required CanonicalHealthTimelineSourceCollection sourceCollection,
}) {
  return 'dogs/$dogId/${sourceCollection.firestoreCollection}';
}

/// Derives a deterministic canonical health timeline document ID.
///
/// Produces IDs that match the TypeScript deriveTimelineId() function
/// in health_timeline_projection.ts exactly.
///
/// **Validação de entrada:**
/// - `dogId` não pode ser vazio, whitespace-only, ou conter "/".
/// - `sourceId` não pode ser vazio, whitespace-only, ou conter "/".
///
/// **Formato do ID:**
///   "tl1_" + SHA256_UTF8(jsonEncode([
///     "health_timeline_v1",
///     "dogs/{dogId}/{sourceCollection}",
///     sourceId
///   ]))
///
/// Retorna 68 caracteres: prefixo (4) + hex lowercase (64).
///
/// Exemplo:
///   deriveCanonicalHealthTimelineId(
///     dogId: 'dog123',
///     sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
///     sourceId: 'mo1_test',
///   )
///   → 'tl1_7b4299c45102c070634956184e7dee96b5bb096e80f61f654ab69c993cbd066b'
///
/// Lança [ArgumentError] se dogId ou sourceId forem inválidos.
String deriveCanonicalHealthTimelineId({
  required String dogId,
  required CanonicalHealthTimelineSourceCollection sourceCollection,
  required String sourceId,
}) {
  // Validar dogId
  if (dogId.trim().isEmpty) {
    throw ArgumentError.value(dogId, 'dogId', 'dogId cannot be blank');
  }
  if (dogId.contains('/')) {
    throw ArgumentError.value(dogId, 'dogId', 'dogId cannot contain "/"');
  }

  // Validar sourceId
  if (sourceId.trim().isEmpty) {
    throw ArgumentError.value(sourceId, 'sourceId', 'sourceId cannot be blank');
  }
  if (sourceId.contains('/')) {
    throw ArgumentError.value(
      sourceId,
      'sourceId',
      'sourceId cannot contain "/"',
    );
  }

  // Construir source path exato
  final sourcePath = canonicalHealthTimelineSourcePath(
    dogId: dogId,
    sourceCollection: sourceCollection,
  );

  // Criar preimage como array JSON (corresponde a stableStringify em TypeScript)
  final preimage = jsonEncode(<String>[
    _kHealthTimelineVersion,
    sourcePath,
    sourceId,
  ]);

  // Calcular SHA-256
  final digest = sha256.convert(utf8.encode(preimage));

  // Retornar ID com prefixo
  return '$_kTimelineIdPrefix${digest.toString()}';
}
