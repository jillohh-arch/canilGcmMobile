import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/media_processing_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/core/services/speech_dictation_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_team_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

class FinalizeOccurrenceScreen extends StatefulWidget {
  final String occurrenceId;
  final String typeName;
  final String durationLabel;
  final int eventCount;
  final String dogName;
  final String handlerName;
  final String? locationAddress;

  const FinalizeOccurrenceScreen({
    super.key,
    required this.occurrenceId,
    required this.typeName,
    required this.durationLabel,
    required this.eventCount,
    required this.dogName,
    required this.handlerName,
    this.locationAddress,
  });

  @override
  State<FinalizeOccurrenceScreen> createState() =>
      _FinalizeOccurrenceScreenState();
}

class _FinalizeOccurrenceScreenState extends State<FinalizeOccurrenceScreen> {
  final _pageController = PageController();
  final _reportController = TextEditingController();
  final _speechService = SpeechDictationService();

  int _currentStep = 0;
  bool _isListening = false;
  bool _isFinalizing = false;
  bool _draftLoaded = false;
  Timer? _draftDebounce;
  Occurrence? _occurrence;

  // Passo 2
  final Set<OccurrenceResult> _selectedResults = {};

  // Passo 3
  final Map<String, Map<String, TextEditingController>> _detailControllers = {};
  final List<_DrugEntry> _drugEntries = [];
  final List<File> _finalizationPhotos = [];
  final _imagePicker = ImagePicker();
  final _mediaService = const MediaProcessingService();
  final _storageService = StorageService();

  static const _drugTypes = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Ecstasy',
    'Outros',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoreDraftIfNeeded(),
    );
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _pageController.dispose();
    _reportController.dispose();
    _speechService.stop();
    for (final map in _detailControllers.values) {
      for (final ctrl in map.values) {
        ctrl.dispose();
      }
    }
    for (final entry in _drugEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  // ─── Navigation ─────────────────────────────────────────────────────

  void _goNext() {
    if (_currentStep == 0 && _reportController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Preencha o relato para avançar',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_currentStep == 1 && _selectedResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selecione pelo menos um resultado',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _scheduleDraftSave();
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _scheduleDraftSave();
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // ─── Speech ─────────────────────────────────────────────────────────

  Future<void> _toggleSpeech() async {
    if (_isListening) {
      _speechService.stop();
      setState(() => _isListening = false);
    } else {
      final started = await _speechService.start(
        controller: _reportController,
        onListeningStarted: () => setState(() => _isListening = true),
        onListeningStopped: () => setState(() => _isListening = false),
      );
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Microfone não disponível',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ─── Results ────────────────────────────────────────────────────────

  void _toggleResult(OccurrenceResult result) {
    setState(() {
      if (result == OccurrenceResult.noOccurrence) {
        if (_selectedResults.contains(result)) {
          _selectedResults.remove(result);
        } else {
          _selectedResults.clear();
          _selectedResults.add(result);
          for (final e in _drugEntries) {
            e.dispose();
          }
          _drugEntries.clear();
        }
      } else {
        _selectedResults.remove(OccurrenceResult.noOccurrence);
        if (_selectedResults.contains(result)) {
          _selectedResults.remove(result);
          if (result == OccurrenceResult.drugSeized) {
            for (final e in _drugEntries) {
              e.dispose();
            }
            _drugEntries.clear();
          }
        } else {
          _selectedResults.add(result);
          if (result == OccurrenceResult.drugSeized && _drugEntries.isEmpty) {
            _drugEntries.add(_DrugEntry());
          }
        }
      }
    });
    _scheduleDraftSave();
  }

  // ─── Details ────────────────────────────────────────────────────────

  TextEditingController _getDetailController(String resultKey, String field) {
    _detailControllers.putIfAbsent(resultKey, () => {});
    _detailControllers[resultKey]!.putIfAbsent(
      field,
      () => TextEditingController(),
    );
    return _detailControllers[resultKey]![field]!;
  }

  void _addDrugEntry() {
    setState(() {
      _drugEntries.add(_DrugEntry());
    });
    _scheduleDraftSave();
  }

  void _removeDrugEntry(int index) {
    setState(() {
      _drugEntries[index].dispose();
      _drugEntries.removeAt(index);
    });
    _scheduleDraftSave();
  }

  Map<String, dynamic>? _buildDetails() {
    final details = <String, dynamic>{};
    for (final result in _selectedResults) {
      if (result == OccurrenceResult.noOccurrence ||
          result == OccurrenceResult.supportProvided) {
        continue;
      }
      final key = result.toMap();

      // Drogas: lista dinâmica
      if (result == OccurrenceResult.drugSeized) {
        final drugs = <Map<String, dynamic>>[];
        for (final entry in _drugEntries) {
          final type = entry.type ?? '';
          final weight = entry.weightController.text.trim();
          if (type.isNotEmpty || weight.isNotEmpty) {
            drugs.add({'type': type, 'weight_grams': weight});
          }
        }
        if (drugs.isNotEmpty) details[key] = drugs;
        continue;
      }

      final fields = _detailControllers[key];
      if (fields == null) continue;
      final map = <String, dynamic>{};
      for (final entry in fields.entries) {
        final val = entry.value.text.trim();
        if (val.isNotEmpty) map[entry.key] = val;
      }
      if (map.isNotEmpty) details[key] = map;
    }
    return details.isNotEmpty ? details : null;
  }

  bool get _canAdvance {
    return !_isFinalizing;
  }

  String? _missingDetailMessage() {
    for (final result in _selectedResults) {
      final message = _missingDetailFor(result);
      if (message != null) return message;
    }
    return null;
  }

  String? _missingDetailFor(OccurrenceResult result) {
    if (result == OccurrenceResult.noOccurrence ||
        result == OccurrenceResult.supportProvided) {
      return null;
    }

    if (result == OccurrenceResult.drugSeized) {
      if (_drugEntries.isEmpty) return 'Informe ao menos uma droga apreendida';
      for (final entry in _drugEntries) {
        if ((entry.type ?? '').trim().isEmpty) {
          return 'Informe o tipo da droga apreendida';
        }
        if (entry.weightController.text.trim().isEmpty) {
          return 'Informe a quantidade da droga apreendida';
        }
      }
      return null;
    }

    final key = result.toMap();
    String field(String name) =>
        _detailControllers[key]?[name]?.text.trim() ?? '';

    return switch (result) {
      OccurrenceResult.weaponSeized
          when field('type').isEmpty || field('quantity').isEmpty =>
        'Informe tipo e quantidade da arma apreendida',
      OccurrenceResult.personDetained
          when field('count').isEmpty || field('referral').isEmpty =>
        'Informe quantidade e encaminhamento da pessoa detida',
      OccurrenceResult.boCreated when field('bo_number').isEmpty =>
        'Informe o número do BO',
      _ => null,
    };
  }

  /// Monta a ocorrência enriquecida (relato, resultados, detalhes e fotos de
  /// finalização) usada como entrada única do cálculo de hash. Mantém o estado
  /// que será efetivamente selado idêntico ao que o serviço serializa.
  Occurrence? _enrichedOccurrenceForHash({
    required String report,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    required List<String> finalizationPhotoHashes,
    required List<String> finalizationPhotos,
  }) {
    final vm = context.read<OccurrenceViewModel>();
    final occ = _occurrence ?? vm.openOccurrence;
    if (occ == null) return null;
    return occ.copyWith(
      finalReport: report,
      results: results,
      details: details,
      finalizationPhotos: finalizationPhotos,
      finalizationPhotoHashes: finalizationPhotoHashes,
    );
  }

  /// Fonte única do selo: delega ao [OccurrenceFinalizationService] (hash v4),
  /// garantindo que a finalização direta produza o mesmo hash que a verificação
  /// e a co-assinatura. Não reimplementar a serialização aqui.
  String? _buildIntegrityHash({
    required String report,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    required List<String> finalizationPhotos,
    List<String> finalizationPhotoHashes = const [],
  }) {
    final occ = _enrichedOccurrenceForHash(
      report: report,
      results: results,
      details: details,
      finalizationPhotoHashes: finalizationPhotoHashes,
      finalizationPhotos: finalizationPhotos,
    );
    if (occ == null) return null;
    final vm = context.read<OccurrenceViewModel>();
    return OccurrenceFinalizationService.calculateIntegrityHashV4For(
      occ,
      events: vm.events,
    );
  }

  // ─── Finalize ───────────────────────────────────────────────────────

  bool get _hasCoSigners {
    final occurrence =
        _occurrence ?? context.read<OccurrenceViewModel>().openOccurrence;
    return occurrence?.team.any((member) => member.role.name != 'titular') ??
        false;
  }

  Future<void> _finalize() async {
    _draftDebounce?.cancel();
    final missing = _missingDetailMessage();
    if (missing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(missing, style: GoogleFonts.inter()),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isFinalizing = true);
    HapticFeedback.heavyImpact();

    try {
      final vm = context.read<OccurrenceViewModel>();
      final report = _reportController.text.trim();
      final results = _selectedResults.toList();
      final details = _buildDetails();
      _occurrence ??= await vm.getById(widget.occurrenceId);

      if (_occurrence?.status == OccurrenceStatus.awaitingSignatures) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                OccurrenceTeamScreen(occurrenceId: widget.occurrenceId),
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ocorrencia ja esta aguardando assinaturas.'),
          ),
        );
        return;
      }

      // Upload fotos de finalização (se houver)
      final photoUploadResults = await _uploadFinalizationPhotos();
      final photoUrls = photoUploadResults.map((r) => r.url).toList();
      final photoHashes = photoUploadResults.map((r) => r.sha256Hash).toList();

      if (_hasCoSigners) {
        await vm
            .closeForSignatures(
              id: widget.occurrenceId,
              finalReport: report,
              results: results,
              details: details,
              finalizationPhotos: photoUrls,
              finalizationPhotoHashes: photoHashes,
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                debugPrint('[Finalize] TIMEOUT após 30s ao fechar assinatura');
                throw TimeoutException(
                  'Tempo limite excedido ao fechar para assinaturas. Verifique sua conexão.',
                );
              },
            );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  OccurrenceTeamScreen(occurrenceId: widget.occurrenceId),
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ocorrência fechada para assinaturas.'),
            ),
          );
        }
        return;
      }

      debugPrint('[Finalize] Construindo hash... events=${vm.events.length}');

      final hash = _buildIntegrityHash(
        report: report,
        results: results,
        details: details,
        finalizationPhotos: photoUrls,
        finalizationPhotoHashes: photoHashes,
      );

      if (hash == null) {
        throw StateError('Ocorrência indisponível para selar o hash.');
      }

      debugPrint('[Finalize] Hash construído. Chamando finalizeOccurrence...');

      await vm
          .finalizeOccurrence(
            id: widget.occurrenceId,
            integrityHash: hash,
            finalReport: report,
            results: results,
            details: details,
            finalizationPhotos: photoUrls,
            finalizationPhotoHashes: photoHashes,
            hashVersion: 4,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('[Finalize] TIMEOUT após 30s');
              throw TimeoutException(
                'Tempo limite excedido ao finalizar. Verifique sua conexão.',
              );
            },
          );

      debugPrint('[Finalize] Finalização concluída com sucesso!');
      final sealedOccurrence = await vm.getById(widget.occurrenceId);
      final confirmedHash =
          sealedOccurrence?.integrityHash?.trim().isNotEmpty == true
          ? sealedOccurrence!.integrityHash!
          : hash;

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OccurrenceConfirmationScreen(
              data: OccurrenceConfirmationData(
                occurrenceId: widget.occurrenceId,
                typeName: widget.typeName,
                durationLabel: widget.durationLabel,
                locationAddress: widget.locationAddress,
                dogName: widget.dogName,
                handlerName: widget.handlerName,
                eventCount: widget.eventCount,
                results: results,
                details: details,
                integrityHash: confirmedHash,
              ),
            ),
          ),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Tempo limite excedido'),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  // ─── Draft ──────────────────────────────────────────────────────────

  Future<void> _restoreDraftIfNeeded() async {
    if (_draftLoaded || !mounted) return;
    _draftLoaded = true;

    final vm = context.read<OccurrenceViewModel>();
    final occurrence =
        vm.openOccurrence ?? await vm.getById(widget.occurrenceId);

    if (mounted) {
      setState(() {
        _occurrence = occurrence;
      });
    }

    final draft = _mergedDraftForOccurrence(occurrence);
    if (draft == null || draft.isEmpty || !mounted) return;

    _applyDraft(draft);
  }

  Map<String, dynamic>? _mergedDraftForOccurrence(Occurrence? occurrence) {
    final storedDraft = occurrence?.finalizationDraft;
    final finalFieldsDraft = _draftFromFinalizationFields(occurrence);
    if (!_hasFinalizationDraftContent(storedDraft)) {
      return finalFieldsDraft ?? storedDraft;
    }
    if (finalFieldsDraft == null) return storedDraft;

    return {
      ...finalFieldsDraft,
      ...storedDraft!,
      'final_report':
          _nonEmptyDraftString(storedDraft['final_report']) ??
          finalFieldsDraft['final_report'],
      'results':
          _nonEmptyDraftList(storedDraft['results']) ??
          finalFieldsDraft['results'],
      'details': _mergeDraftDetails(
        finalFieldsDraft['details'],
        storedDraft['details'],
      ),
    };
  }

  bool _hasFinalizationDraftContent(Map<String, dynamic>? draft) {
    if (draft == null || draft.isEmpty) return false;
    final report = draft['final_report'];
    if (report is String && report.trim().isNotEmpty) return true;
    final results = draft['results'];
    if (results is List && results.isNotEmpty) return true;
    final details = draft['details'];
    if (details is Map && details.isNotEmpty) return true;
    return false;
  }

  String? _nonEmptyDraftString(dynamic value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  List<dynamic>? _nonEmptyDraftList(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    return value;
  }

  Map<String, dynamic> _mergeDraftDetails(dynamic base, dynamic override) {
    final output = <String, dynamic>{};
    if (base is Map) {
      output.addAll(base.map((key, value) => MapEntry(key.toString(), value)));
    }
    if (override is Map) {
      for (final entry in override.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map && output[key] is Map) {
          output[key] = {
            ...(output[key] as Map).map(
              (nestedKey, nestedValue) =>
                  MapEntry(nestedKey.toString(), nestedValue),
            ),
            ...value.map(
              (nestedKey, nestedValue) =>
                  MapEntry(nestedKey.toString(), nestedValue),
            ),
          };
        } else if (value is List && value.isEmpty) {
          continue;
        } else {
          output[key] = value;
        }
      }
    }
    return output;
  }

  Map<String, dynamic>? _draftFromFinalizationFields(Occurrence? occurrence) {
    if (occurrence == null) return null;
    final hasReport = occurrence.finalReport?.trim().isNotEmpty == true;
    final hasResults = occurrence.results.isNotEmpty;
    final hasDetails = occurrence.details?.isNotEmpty == true;
    if (!hasReport && !hasResults && !hasDetails) return null;

    return {
      'current_step': 2,
      'final_report': occurrence.finalReport ?? '',
      'results': occurrence.results.map((result) => result.toMap()).toList(),
      'details': occurrence.details ?? const <String, dynamic>{},
      'restored_from_finalization': true,
    };
  }

  void _applyDraft(Map<String, dynamic> draft) {
    final report = draft['final_report'];
    if (report is String) {
      _reportController.text = report;
    }

    final rawResults = draft['results'];
    if (rawResults is List) {
      _selectedResults
        ..clear()
        ..addAll(
          rawResults
              .map((value) => OccurrenceResult.fromMap(value?.toString()))
              .where(
                (result) => rawResults
                    .map((value) => value?.toString())
                    .contains(result.toMap()),
              ),
        );
    }

    final rawDetails = draft['details'];
    if (rawDetails is Map) {
      _restoreDetails(rawDetails);
    }

    final step = draft['current_step'];
    final restoredStep = step is int ? step.clamp(0, 2) : 0;
    setState(() => _currentStep = restoredStep);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(_currentStep);
      }
    });
  }

  void _restoreDetails(Map rawDetails) {
    final details = rawDetails.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final drugs = details[OccurrenceResult.drugSeized.toMap()];
    if (drugs is List) {
      for (final entry in _drugEntries) {
        entry.dispose();
      }
      _drugEntries.clear();
      for (final raw in drugs.whereType<Map>()) {
        final drug = _DrugEntry();
        drug.type = raw['type']?.toString();
        drug.weightController.text = raw['weight_grams']?.toString() ?? '';
        _drugEntries.add(drug);
      }
    }

    for (final result in OccurrenceResult.values) {
      if (result == OccurrenceResult.drugSeized) continue;
      final resultDetails = details[result.toMap()];
      if (resultDetails is! Map) continue;
      for (final entry in resultDetails.entries) {
        _getDetailController(result.toMap(), entry.key.toString()).text =
            entry.value?.toString() ?? '';
      }
    }
  }

  Map<String, dynamic> _buildDraft() {
    return {
      'current_step': _currentStep,
      'final_report': _reportController.text.trim(),
      'results': _selectedResults.map((r) => r.toMap()).toList()..sort(),
      'details': _buildDetails(),
      'saved_at': DateTime.now().toIso8601String(),
    };
  }

  void _scheduleDraftSave() {
    if (!_draftLoaded || _isFinalizing) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (!mounted || _isFinalizing) return;
    final vm = context.read<OccurrenceViewModel>();
    await vm.saveDraft(widget.occurrenceId, _buildDraft());
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Salvar como rascunho?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Você poderá retomar a finalização depois.',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary.withAlpha(200),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(
              'DESCARTAR',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _saveDraft();
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(
              'SALVAR RASCUNHO',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildContextCard(),
              _buildProgressBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildStep1(), _buildStep2(), _buildStep3()],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showExitDialog,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.close,
                color: AppTheme.textPrimary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FINALIZAR OCORRÊNCIA',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Passo ${_currentStep + 1} de 3',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withAlpha(40)),
      ),
      child: Row(
        children: [
          Text('🛡', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.typeName} · ${widget.durationLabel} · ${widget.eventCount} evento${widget.eventCount != 1 ? 's' : ''}',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(200),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: List.generate(3, (i) {
          final Color color;
          if (i < _currentStep) {
            color = AppTheme.success;
          } else if (i == _currentStep) {
            color = AppTheme.primary;
          } else {
            color = AppTheme.textPrimary.withAlpha(30);
          }
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFooter() {
    final isLast = _currentStep == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: AppTheme.textPrimary.withAlpha(10)),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _goBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.textPrimary.withAlpha(40)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '‹ VOLTAR',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _canAdvance ? (isLast ? _finalize : _goNext) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast ? AppTheme.success : AppTheme.primary,
                disabledBackgroundColor: AppTheme.textPrimary.withAlpha(30),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isFinalizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textPrimary,
                      ),
                    )
                  : Text(
                      isLast ? '✓ CONCLUIR' : 'PRÓXIMO ›',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 1: Relato ─────────────────────────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RELATO INSTITUCIONAL',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _toggleSpeech,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isListening
                    ? AppTheme.error.withAlpha(20)
                    : AppTheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isListening
                      ? AppTheme.error.withAlpha(80)
                      : AppTheme.primary.withAlpha(60),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _isListening ? AppTheme.error : AppTheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isListening ? 'PARAR GRAVAÇÃO' : '🎙 GRAVAR RELATO',
                    style: GoogleFonts.inter(
                      color: _isListening ? AppTheme.error : AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isListening)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ouvindo...',
                    style: GoogleFonts.inter(
                      color: AppTheme.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'ou digite diretamente:',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(120),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reportController,
            maxLines: 8,
            minLines: 5,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
            onChanged: (_) {
              setState(() {});
              _scheduleDraftSave();
            },
            decoration: InputDecoration(
              hintText: 'Equipe foi acionada às... descreva o que aconteceu...',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(60),
              ),
              filled: true,
              fillColor: AppTheme.textPrimary.withAlpha(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Caracteres: ${_reportController.text.length}',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(80),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: Resultados ─────────────────────────────────────────────

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESULTADO DA OCORRÊNCIA',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Marque todos que se aplicam',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(100),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: OccurrenceResult.values.map((result) {
              final selected = _selectedResults.contains(result);
              return _ResultCard(
                result: result,
                selected: selected,
                onTap: () => _toggleResult(result),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_selectedResults.isNotEmpty)
            Text(
              '${_selectedResults.length} resultado${_selectedResults.length != 1 ? 's' : ''} selecionado${_selectedResults.length != 1 ? 's' : ''}',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Step 3: Detalhes ───────────────────────────────────────────────

  Widget _buildStep3() {
    final needsDetails = _selectedResults.where(
      (r) =>
          r != OccurrenceResult.noOccurrence &&
          r != OccurrenceResult.supportProvided,
    );

    if (needsDetails.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.success,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum detalhe adicional necessário',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary.withAlpha(180),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildFinalizationPhotosSection(),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DETALHES DOS RESULTADOS',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...needsDetails.map((result) => _buildDetailSection(result)),
          const SizedBox(height: 8),
          _buildFinalizationPhotosSection(),
        ],
      ),
    );
  }

  // ─── Fotos de finalização ───────────────────────────────────────────

  Widget _buildFinalizationPhotosSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'FOTOS DA FINALIZAÇÃO',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                'opcional',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(80),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Foto do B.O., apreensões ou documentos relevantes.',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(120),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (_finalizationPhotos.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _finalizationPhotos.asMap().entries.map((entry) {
                return _buildPhotoThumb(entry.key, entry.value);
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _buildPhotoButton(
                icon: Icons.camera_alt_outlined,
                label: 'Câmera',
                onTap: () => _pickFinalizationPhoto(ImageSource.camera),
              ),
              const SizedBox(width: 10),
              _buildPhotoButton(
                icon: Icons.photo_library_outlined,
                label: 'Galeria',
                onTap: () => _pickFinalizationPhoto(ImageSource.gallery),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumb(int index, File file) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 64, height: 64, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () {
              setState(() => _finalizationPhotos.removeAt(index));
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.background.withAlpha(180),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 12,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: AppTheme.primary.withAlpha(15),
          border: Border.all(color: AppTheme.primary.withAlpha(50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFinalizationPhoto(ImageSource source) async {
    try {
      // Solicitar permissão de runtime antes de abrir o picker
      final permission = source == ImageSource.camera
          ? Permission.camera
          : Permission.photos;
      var status = await permission.request();
      if (!status.isGranted) {
        // Fallback para storage em Android < 13
        status = await Permission.storage.request();
      }
      if (!status.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão negada para acessar mídia')),
        );
        return;
      }

      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _finalizationPhotos.add(File(picked.path)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao capturar foto: $e')));
      }
    }
  }

  Future<List<UploadResult>> _uploadFinalizationPhotos() async {
    if (_finalizationPhotos.isEmpty) return [];

    final results = <UploadResult>[];
    final folder = 'occurrences/${widget.occurrenceId}/finalization';

    for (final file in _finalizationPhotos) {
      final compressed = await _mediaService.compressImage(file);
      final result = await _storageService.uploadImageWithHash(
        compressed ?? file,
        folder,
      );
      if (result != null) results.add(result);
    }
    return results;
  }

  Widget _buildDetailSection(OccurrenceResult result) {
    if (result == OccurrenceResult.drugSeized) {
      return _buildDrugSection();
    }

    final fields = _fieldsForResult(result);
    final key = result.toMap();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _iconForResult(result),
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 8),
              Text(
                result.label.toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...fields.map(
            (field) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _getDetailController(key, field.key),
                keyboardType: field.numeric
                    ? TextInputType.number
                    : TextInputType.text,
                inputFormatters: field.numeric
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                onChanged: (_) {
                  setState(() {});
                  _scheduleDraftSave();
                },
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                decoration: _detailFieldDecoration(field.label),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrugSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💊', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DROGA APREENDIDA',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _addDrugEntry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'ADICIONAR',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._drugEntries.asMap().entries.map((entry) {
            final idx = entry.key;
            final drugEntry = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.textPrimary.withAlpha(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Substância ${idx + 1}',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_drugEntries.length > 1)
                        GestureDetector(
                          onTap: () => _removeDrugEntry(idx),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: AppTheme.error.withAlpha(180),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'TIPO',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary.withAlpha(120),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _drugTypes.map((type) {
                      final selected = drugEntry.type == type;
                      return GestureDetector(
                        onTap: () {
                          setState(() => drugEntry.type = type);
                          _scheduleDraftSave();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary.withAlpha(30)
                                : AppTheme.textPrimary.withAlpha(5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary.withAlpha(30),
                            ),
                          ),
                          child: Text(
                            type,
                            style: GoogleFonts.inter(
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary.withAlpha(180),
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: drugEntry.weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _scheduleDraftSave();
                    },
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: _detailFieldDecoration('Peso em gramas'),
                  ),
                ],
              ),
            );
          }),
          if (_drugEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Toque em ADICIONAR para registrar substâncias',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(80),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _detailFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(
        color: AppTheme.textPrimary.withAlpha(120),
        fontSize: 13,
      ),
      filled: true,
      fillColor: AppTheme.textPrimary.withAlpha(8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  String _iconForResult(OccurrenceResult result) => switch (result) {
    OccurrenceResult.drugSeized => '💊',
    OccurrenceResult.weaponSeized => '🔫',
    OccurrenceResult.personDetained => '👤',
    OccurrenceResult.boCreated => '📄',
    OccurrenceResult.noOccurrence => '⊘',
    OccurrenceResult.supportProvided => '✋',
  };

  List<_DetailField> _fieldsForResult(
    OccurrenceResult result,
  ) => switch (result) {
    OccurrenceResult.drugSeized => [], // handled by _buildDrugSection
    OccurrenceResult.weaponSeized => [
      const _DetailField(label: 'Tipo de arma', key: 'type'),
      const _DetailField(label: 'Quantidade', key: 'quantity', numeric: true),
    ],
    OccurrenceResult.personDetained => [
      const _DetailField(label: 'Quantidade', key: 'count', numeric: true),
      const _DetailField(label: 'Encaminhamento (DP, etc)', key: 'referral'),
    ],
    OccurrenceResult.boCreated => [
      const _DetailField(label: 'Número do BO', key: 'bo_number'),
      const _DetailField(label: 'Tipo (flagrante, TCO, etc)', key: 'bo_type'),
    ],
    _ => [],
  };
}

class _DetailField {
  final String label;
  final String key;
  final bool numeric;

  const _DetailField({
    required this.label,
    required this.key,
    this.numeric = false,
  });
}

class _ResultCard extends StatelessWidget {
  final OccurrenceResult result;
  final bool selected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.selected,
    required this.onTap,
  });

  String get _icon => switch (result) {
    OccurrenceResult.drugSeized => '💊',
    OccurrenceResult.weaponSeized => '🔫',
    OccurrenceResult.personDetained => '👤',
    OccurrenceResult.boCreated => '📄',
    OccurrenceResult.noOccurrence => '⊘',
    OccurrenceResult.supportProvided => '✋',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(25)
              : AppTheme.textPrimary.withAlpha(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.textPrimary.withAlpha(20),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: Icon(
                    Icons.check_circle,
                    color: AppTheme.primary,
                    size: 16,
                  ),
                ),
              ),
            Text(_icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              result.label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: selected
                    ? AppTheme.textPrimary
                    : AppTheme.textPrimary.withAlpha(180),
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrugEntry {
  String? type;
  final TextEditingController weightController;

  _DrugEntry() : weightController = TextEditingController();

  void dispose() => weightController.dispose();
}
