import 'package:flutter/material.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/routine/presentation/viewmodels/routine_viewmodel.dart';

import 'package:canil_gcm/core/services/activity_media_uploader.dart';
import 'activity_record_payload_builder.dart';

/// Controller que encapsula todo o estado e lógica da categoria Rotina
/// dentro do [DynamicActivitySheet].
///
/// Opção B: possui seus próprios [descriptionController] e [timeController];
/// o State lê do controller ativo conforme a categoria.
/// Rotina não usa localização no formulário padrão.
class ActivitySheetRoutineCtrl {
  ActivitySheetRoutineCtrl({
    required this.dogId,
    required this.dogName,
    required this.onStateChanged,
    this.documentId,
    this.initialData,
  });

  final String dogId;
  final String dogName;
  final String? documentId;
  final Map<String, dynamic>? initialData;

  /// Chamado quando o controller muta estado que a UI precisa refletir.
  final VoidCallback onStateChanged;

  // -------------------------------------------------------------------------
  // TextEditingControllers (Opção B)
  // -------------------------------------------------------------------------
  final descriptionController = TextEditingController(); // notas
  final timeController = TextEditingController();
  final durationController = TextEditingController();

  // Campos específicos de rotina
  final racaoMarcaController = TextEditingController();
  final racaoQtdController = TextEditingController();
  final distanciaController = TextEditingController();

  // -------------------------------------------------------------------------
  // Inicialização
  // -------------------------------------------------------------------------

  void init() {
    if (initialData != null) {
      _populate(initialData!);
    }
  }

  void _populate(Map<String, dynamic> data) {
    _populateTimestamp(data);
    _populateFields(data);
  }

  void _populateTimestamp(Map<String, dynamic> data) {
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) {
      timeController.text = const PtBrDateTimeService().time(rawDate);
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    descriptionController.text = data['notes'] ?? '';

    if (data['metadata'] is Map) {
      final meta = Map<String, dynamic>.from(data['metadata'] as Map);
      final marca = meta['Marca da Ração'];
      if (marca != null) racaoMarcaController.text = marca.toString();
      final qty = meta['Quantidade (g)'];
      if (qty != null) racaoQtdController.text = qty.toString();
      final dur = meta['Duração (min)'];
      if (dur != null) durationController.text = dur.toString();
      final dist = meta['Distância (km)'];
      if (dist != null) distanciaController.text = dist.toString();
    }
  }

  // -------------------------------------------------------------------------
  // Metadados (preenchidos antes do save, mesclados ao formData do State)
  // -------------------------------------------------------------------------

  Map<String, dynamic> buildMetadata({required String? subtype}) {
    const feedingSubtype = 'Alimentação';
    const playSubtype = 'Brincar';
    const walkSubtype = 'Caminhada';

    final meta = <String, dynamic>{};

    if (subtype == feedingSubtype) {
      if (racaoMarcaController.text.isNotEmpty) {
        meta['Marca da Ração'] = racaoMarcaController.text;
      }
      if (racaoQtdController.text.isNotEmpty) {
        meta['Quantidade (g)'] = racaoQtdController.text;
      }
    }

    if (subtype == playSubtype || subtype == walkSubtype) {
      if (durationController.text.isNotEmpty) {
        meta['Duração (min)'] = durationController.text;
      }
    }

    if (subtype == walkSubtype) {
      if (distanciaController.text.isNotEmpty) {
        meta['Distância (km)'] = distanciaController.text;
      }
    }

    return meta;
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> save({
    required RoutineViewModel routineVM,
    required AuthViewModel authVM,
    required String? selectedSubtype,
    required Map<String, dynamic> formData,
    required List<Map<String, dynamic>> mediaAttachments,
    required DateTime resolvedTimestamp,
    required void Function(String) onStatus,
    required void Function(Map<String, dynamic>) onUploading,
    required void Function(Map<String, dynamic>, String) onUploaded,
    required void Function(Map<String, dynamic>) onPending,
  }) async {
    onStatus('Fazendo upload de mídias...');
    final finalMedia = await ActivityMediaUploader.upload(
      attachments: mediaAttachments,
      folder: 'routines',
      onUploading: onUploading,
      onUploaded: onUploaded,
      onPending: onPending,
    );

    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
    final metadata = {...formData, ...buildMetadata(subtype: selectedSubtype)};

    final routine = ActivityRecordPayloadBuilder.routine(
      documentId: documentId,
      dogId: dogId,
      dogName: dogName,
      currentRa: currentRa,
      initialHandlerId: initialData?['_rawHandlerId']?.toString(),
      activityType: selectedSubtype!,
      timestamp: resolvedTimestamp,
      notes: descriptionController.text,
      mediaAttachments: finalMedia,
      metadata: metadata,
    );

    if (documentId != null) {
      await routineVM.updateRoutine(routine);
    } else {
      await routineVM.addRoutine(routine);
    }
  }

  // -------------------------------------------------------------------------
  // Resolve timestamp
  // -------------------------------------------------------------------------

  DateTime resolveTimestamp({required DateTime? rawDate}) {
    return const PtBrDateTimeService().withTimeText(
      base: rawDate ?? DateTime.now(),
      timeText: timeController.text,
    );
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    descriptionController.dispose();
    timeController.dispose();
    durationController.dispose();
    racaoMarcaController.dispose();
    racaoQtdController.dispose();
    distanciaController.dispose();
  }
}
