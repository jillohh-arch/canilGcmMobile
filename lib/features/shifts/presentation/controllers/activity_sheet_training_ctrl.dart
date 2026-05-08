import 'package:flutter/material.dart';

import 'package:canil_gcm/core/domain/activity_subtype_ids.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';

import 'activity_media_uploader.dart';
import 'activity_record_payload_builder.dart';

/// Controller que encapsula todo o estado e lógica da categoria Treino
/// dentro do [DynamicActivitySheet].
///
/// Opção B: possui seus próprios [locationController], [descriptionController]
/// e [timeController]; o State lê do controller ativo conforme a categoria.
class ActivitySheetTrainingCtrl {
  ActivitySheetTrainingCtrl({
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
  // TextEditingControllers (Opção B: cada categoria tem os seus próprios)
  // -------------------------------------------------------------------------
  final locationController = TextEditingController();
  final descriptionController = TextEditingController(); // handlerNotes
  final timeController = TextEditingController();
  final durationController = TextEditingController();

  // Clima / ambiente (Faro)
  final tempController = TextEditingController();
  final humidityController = TextEditingController();

  // Campos específicos de treino
  final objetivoController = TextEditingController();
  final dificuldadesController = TextEditingController();

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
    final trainingType = data['trainingType'] as String?;
    locationController.text = data['location'] ?? '';
    descriptionController.text = data['handlerNotes'] ?? '';

    if (data['searchDuration'] != null) {
      durationController.text = ((data['searchDuration'] as num) ~/ 60)
          .toString();
    }

    if (data['metadata'] is Map) {
      final meta = Map<String, dynamic>.from(data['metadata'] as Map);
      final temp = meta['Temperatura (°C)'];
      if (temp != null) tempController.text = temp.toString();
      final humidity = meta['Umidade (%)'];
      if (humidity != null) humidityController.text = humidity.toString();
    }

    _ = trainingType; // subtype é gerenciado pelo State
  }

  // ignore: unused_field
  dynamic _;

  // -------------------------------------------------------------------------
  // Metadados (preenchidos antes do save)
  // -------------------------------------------------------------------------

  /// Retorna o mapa de metadados de treino para ser mesclado ao [formData]
  /// do State antes do salvamento.
  Map<String, dynamic> buildMetadata({required String? subtype}) {
    final meta = <String, dynamic>{};
    if (durationController.text.isNotEmpty) {
      meta['Duração (min)'] = durationController.text;
    }
    if (subtype == ActivitySubtypeIds.scentWork) {
      if (tempController.text.isNotEmpty) {
        meta['Temperatura (°C)'] = tempController.text;
      }
      if (humidityController.text.isNotEmpty) {
        meta['Umidade (%)'] = humidityController.text;
      }
    }
    return meta;
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> save({
    required TrainingViewModel trainingVM,
    required AuthViewModel authVM,
    required String? selectedSubtype,
    required Map<String, dynamic> formData,
    required List<Map<String, dynamic>> mediaAttachments,
    required void Function(String) onStatus,
    required void Function(Map<String, dynamic>) onUploading,
    required void Function(Map<String, dynamic>, String) onUploaded,
    required void Function(Map<String, dynamic>) onPending,
  }) async {
    onStatus('Fazendo upload de mídias...');
    final finalMedia = await ActivityMediaUploader.upload(
      attachments: mediaAttachments,
      folder: 'trainings',
      onUploading: onUploading,
      onUploaded: onUploaded,
      onPending: onPending,
    );

    final currentRa =
        initialData?['_rawHandlerId'] as String? ??
        HandlerIdentityService.raFromUser(authVM.user) ??
        '';

    final metadata = {...formData, ...buildMetadata(subtype: selectedSubtype)};

    final session = ActivityRecordPayloadBuilder.trainingSession(
      documentId: documentId,
      dogId: dogId,
      dogName: dogName,
      currentRa: currentRa,
      date: initialData?['_rawDate'] ?? DateTime.now(),
      trainingType: selectedSubtype!,
      location: locationController.text,
      notes: descriptionController.text,
      durationMinutes: durationController.text,
      mediaAttachments: finalMedia,
      metadata: metadata,
    );

    if (documentId != null) {
      await trainingVM.updateTrainingSession(session);
    } else {
      await trainingVM.addTrainingSession(session);
    }
  }

  // -------------------------------------------------------------------------
  // Resolve timestamp do formulário
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
    locationController.dispose();
    descriptionController.dispose();
    timeController.dispose();
    durationController.dispose();
    tempController.dispose();
    humidityController.dispose();
    objetivoController.dispose();
    dificuldadesController.dispose();
  }
}
