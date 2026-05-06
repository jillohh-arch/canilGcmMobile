import 'dart:io';

import 'package:flutter/material.dart';

import 'package:canil_gcm/services/media_attachment_upload_service.dart';
import 'package:canil_gcm/services/pdf_attachment_service.dart';
import 'package:canil_gcm/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/services/storage_service.dart';
import 'package:canil_gcm/viewmodels/health_viewmodel.dart';

import 'activity_record_payload_builder.dart';

/// Controller que encapsula todo o estado e lógica da categoria Saúde
/// dentro do [DynamicActivitySheet].
///
/// Opção B: possui seus próprios TextEditingControllers; o State lê
/// do controller ativo conforme a categoria.
class ActivitySheetHealthCtrl {
  ActivitySheetHealthCtrl({
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
  final descriptionController = TextEditingController(); // healthObservations
  final timeController = TextEditingController();
  final vetNameController = TextEditingController();
  final clinicaController = TextEditingController();
  final motivoController = TextEditingController();
  final tipoVacinaController = TextEditingController();
  final tipoExameController = TextEditingController();
  final produtosBanhoController = TextEditingController();
  final returnDateController = TextEditingController();
  final materiaisController = TextEditingController();

  // -------------------------------------------------------------------------
  // Estado específico de Saúde
  // -------------------------------------------------------------------------
  String? selectedVacina;
  File? examePdfFile;
  String? examePdfName;

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
    vetNameController.text = data['vetName'] ?? '';

    final obs = data['healthObservations'] as String? ?? '';
    if (obs.contains('Retorno agendado: ')) {
      final split = obs.split('Retorno agendado: ');
      descriptionController.text = split[0].trim();
      if (split.length > 1) {
        returnDateController.text = split[1].trim();
      }
    } else {
      descriptionController.text = obs;
    }

    // subtype (logType) é gerenciado pelo State
  }

  // -------------------------------------------------------------------------
  // Metadados (construídos antes do save)
  // -------------------------------------------------------------------------

  /// Retorna mapa de metadados de saúde para ser mesclado ao [formData] do State.
  Map<String, dynamic> buildMetadata(Map<String, dynamic> formData) {
    final meta = Map<String, dynamic>.from(formData);
    if (returnDateController.text.isNotEmpty) {
      meta['Data de Retorno'] = returnDateController.text;
    }
    return meta;
  }

  // -------------------------------------------------------------------------
  // Upload do PDF de exame
  // -------------------------------------------------------------------------

  Future<String?> uploadExamePdf({
    required void Function(String) onStatus,
  }) async {
    if (examePdfFile == null) return null;
    onStatus('Enviando PDF do Exame...');
    return const PdfAttachmentService().uploadExamPdf(examePdfFile!);
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> save({
    required HealthViewModel healthVM,
    required String? selectedSubtype,
    required Map<String, dynamic> formData,
    required List<Map<String, dynamic>> mediaAttachments,
    required void Function(String) onStatus,
    required bool Function() isMounted,
    required void Function(Map<String, dynamic>) onUploading,
    required void Function(Map<String, dynamic>, String) onUploaded,
    required void Function(Map<String, dynamic>) onPending,
  }) async {
    onStatus('Fazendo upload de mídias...');
    final finalMedia = await _uploadMedia(
      attachments: mediaAttachments,
      isMounted: isMounted,
      onUploading: onUploading,
      onUploaded: onUploaded,
      onPending: onPending,
    );

    final pdfUrl = await uploadExamePdf(onStatus: onStatus);
    if (pdfUrl != null) {
      finalMedia.add({
        'url': pdfUrl,
        'caption': 'PDF do Exame: ${examePdfName ?? "documento.pdf"}',
        'type': 'pdf',
      });
    }

    final hLog = ActivityRecordPayloadBuilder.healthLog(
      documentId: documentId,
      dogId: dogId,
      dogName: dogName,
      date: initialData?['_rawDate'] ?? DateTime.now(),
      logType: selectedSubtype!,
      observations: descriptionController.text,
      returnDate: returnDateController.text,
      vetName: vetNameController.text,
      mediaAttachments: finalMedia,
    );

    if (documentId != null) {
      await healthVM.updateHealthLog(hLog);
    } else {
      await healthVM.addHealthLog(hLog);
    }
  }

  // -------------------------------------------------------------------------
  // Upload de mídias (delegado ao State via callbacks para manter setState)
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _uploadMedia({
    required List<Map<String, dynamic>> attachments,
    required bool Function() isMounted,
    required void Function(Map<String, dynamic>) onUploading,
    required void Function(Map<String, dynamic>, String) onUploaded,
    required void Function(Map<String, dynamic>) onPending,
  }) async {
    if (attachments.isEmpty) return [];
    return MediaAttachmentUploadService(
      storageService: StorageService(),
    ).uploadAll(
      attachments: attachments,
      folder: 'health',
      onUploading: onUploading,
      onUploaded: onUploaded,
      onPending: onPending,
    );
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
    descriptionController.dispose();
    timeController.dispose();
    vetNameController.dispose();
    clinicaController.dispose();
    motivoController.dispose();
    tipoVacinaController.dispose();
    tipoExameController.dispose();
    produtosBanhoController.dispose();
    returnDateController.dispose();
    materiaisController.dispose();
  }
}
