import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/services/text_match_service.dart';
import 'package:canil_gcm/core/utils/firestore_date.dart';
import 'package:canil_gcm/core/controllers/media_attachment_rows.dart';
import 'package:canil_gcm/features/incidents/data/occurrence_event_media_service.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_display_text.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_dynamic_rows.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_extra_fields_snapshot.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_form_controller.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_payload_builder.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_progress_update_builder.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_save_validator.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_wizard_result.dart';

import 'package:canil_gcm/core/services/activity_media_uploader.dart';

part 'activity_sheet_occurrence_populate.dart';
part 'activity_sheet_occurrence_nature.dart';
part 'activity_sheet_occurrence_rows.dart';
part 'activity_sheet_occurrence_payload.dart';
part 'activity_sheet_occurrence_wizard_media.dart';

// ---------------------------------------------------------------------------
// Subtype constants (espelhados aqui para evitar dependência circular)
// ---------------------------------------------------------------------------
abstract final class _Sub {
  static const detection = 'Busca de Entorpecentes';
  static const narcoticsSearch = 'Narcoticsearch';
  static const other = 'Outros';
}

/// Controller que encapsula todo o estado e lógica da categoria
/// Ocorrência / Evento dentro do [DynamicActivitySheet].
///
/// Opção B: cada categoria tem seus próprios [locationController] e
/// [descriptionController]; o State lê do controller ativo.
class ActivitySheetOccurrenceCtrl {
  ActivitySheetOccurrenceCtrl({
    required this.dogId,
    required this.dogName,
    required this.onStateChanged,
    this.documentId,
    this.initialData,
  });

  // Deps injetadas pelo State
  final String dogId;
  final String dogName;
  final String? documentId;
  final Map<String, dynamic>? initialData;

  /// Chamado sempre que o controller muta estado que a UI precisa refletir.
  final VoidCallback onStateChanged;

  // -------------------------------------------------------------------------
  // TextEditingControllers
  // -------------------------------------------------------------------------
  final locationController = TextEditingController();
  final descriptionController = TextEditingController();
  final timeController = TextEditingController();
  final naturezaController = TextEditingController();
  final equipeController = TextEditingController();
  final boController = TextEditingController();
  final guarnicaoController = TextEditingController();
  final situacaoController = TextEditingController();
  final desfechoController = TextEditingController();
  final odorObjetoController = TextEditingController();
  final tempoDesaparecimentoController = TextEditingController();
  final condicaoTerrenoController = TextEditingController();
  final numeroOsController = TextEditingController();
  final updateController = TextEditingController();
  final publicoController = TextEditingController();
  final temaController = TextEditingController();
  final orgaoController = TextEditingController();

  // -------------------------------------------------------------------------
  // FocusNodes
  // -------------------------------------------------------------------------
  final naturezaFocusNode = FocusNode();
  final updateFocusNode = FocusNode();

  // -------------------------------------------------------------------------
  // Estado de ocorrência
  // -------------------------------------------------------------------------
  List<OccurrenceNature> natures = OccurrenceNatureSeed.items;
  String status = OccurrenceFormController.statusCompleted;
  bool? successful = true;
  final Set<String> selectedOutcomes = {};
  final List<IncidentProgressUpdate> timeline = [];
  String? selectedUpdateTitle;
  bool showFinalization = false;
  bool finishSubmitted = false;
  String? activeIncidentId;
  DateTime? activeStartedAt;
  LatLng? selectedLocationLatLng;
  bool showStartNatureEditor = false;

  // -------------------------------------------------------------------------
  // Listas dinâmicas de resultado
  // -------------------------------------------------------------------------
  final List<Map<String, dynamic>> detecaoDrogas = [];
  final List<Map<String, dynamic>> detainedIndividuals = [];
  final List<Map<String, dynamic>> seizedObjects = [];
  final List<Map<String, dynamic>> detainedVehicles = [];

  // -------------------------------------------------------------------------
  // Controlador de lógica de negócio (puro Dart)
  // -------------------------------------------------------------------------
  final _formCtrl = OccurrenceFormController();
  String? _selectedNature; // ex: 'Busca de Entorpecentes'

  String? get selectedNature => _selectedNature;

  static const List<String> drugOptions = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Sintéticos',
    'Nose MP',
    'Outros',
  ];

  // -------------------------------------------------------------------------
  // Inicialização
  // -------------------------------------------------------------------------

  /// Deve ser chamado durante [initState] do State.
  void init() {
    if (initialData != null) {
      _populate(initialData!);
    } else {
      // Nova ocorrência
      _formCtrl.startNewOccurrence();
      _copyFormCtrlToFields();
    }

    if (initialData?['startedAt'] != null) {
      activeStartedAt = parseFirestoreDate(initialData!['startedAt']);
    } else if (initialData?['_rawDate'] is DateTime) {
      activeStartedAt = initialData!['_rawDate'] as DateTime;
    }
    activeIncidentId =
        _nonEmptyText(documentId) ??
        _nonEmptyText(initialData?['id']?.toString());
  }

  String? _nonEmptyText(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    locationController.dispose();
    descriptionController.dispose();
    timeController.dispose();
    naturezaController.dispose();
    equipeController.dispose();
    boController.dispose();
    guarnicaoController.dispose();
    situacaoController.dispose();
    desfechoController.dispose();
    odorObjetoController.dispose();
    tempoDesaparecimentoController.dispose();
    condicaoTerrenoController.dispose();
    numeroOsController.dispose();
    updateController.dispose();
    publicoController.dispose();
    temaController.dispose();
    orgaoController.dispose();
    naturezaFocusNode.dispose();
    updateFocusNode.dispose();
    OccurrenceDynamicRows.disposeDrugs(detecaoDrogas);
    OccurrenceDynamicRows.disposeRows(detainedIndividuals, ['quantidade']);
    OccurrenceDynamicRows.disposeRows(seizedObjects, [
      'descricao',
      'quantidade',
    ]);
    OccurrenceDynamicRows.disposeRows(detainedVehicles, ['tipo', 'placa']);
  }
}
