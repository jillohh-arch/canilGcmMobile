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
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_ai_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_progress_aggregator.dart';
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

  @visibleForTesting
  static String formatUploadStatus({
    required int currentFileIndex,
    required int totalFiles,
    required double? fraction,
    bool hasActiveProgress = false,
  }) {
    final fileNumber = currentFileIndex + 1;
    final prefix = totalFiles == 1 ? 'Enviando foto' : 'Enviando fotos';
    final hasCompletedBaseline = currentFileIndex > 0;
    if (fraction != null && (hasCompletedBaseline || hasActiveProgress)) {
      final pct = (fraction * 100).floor().clamp(0, 100);
      return '$prefix $fileNumber/$totalFiles · $pct%';
    }
    return totalFiles == 1 ? '$prefix...' : '$prefix $fileNumber/$totalFiles...';
  }

  @visibleForTesting
  static List<File> resolveEffectiveFilesAfterCollisionGuard(
    List<({File original, File candidate, bool wasCompressed})> candidates,
  ) {
    final compressedPathCounts = <String, int>{};
    for (final c in candidates) {
      if (c.wasCompressed) {
        compressedPathCounts[c.candidate.path] =
            (compressedPathCounts[c.candidate.path] ?? 0) + 1;
      }
    }

    final taintedPaths = <String>{};
    for (final entry in compressedPathCounts.entries) {
      if (entry.value >= 2) {
        taintedPaths.add(entry.key);
      }
    }

    return candidates.map((c) {
      if (c.wasCompressed && taintedPaths.contains(c.candidate.path)) {
        return c.original;
      }
      return c.candidate;
    }).toList();
  }

  @override
  State<FinalizeOccurrenceScreen> createState() =>
      _FinalizeOccurrenceScreenState();
}

class _FinalizeOccurrenceScreenState extends State<FinalizeOccurrenceScreen> {
  final _pageController = PageController();
  final _reportController = TextEditingController();
  final _speechService = SpeechDictationService();
  final _occurrenceAiService = OccurrenceAiService();

  int _currentStep = 0;
  bool _isListening = false;
  bool _isFinalizing = false;
  String? _finalizeStatus;
  double? _finalizeFraction;
  int _currentFinalizeUploadIndex = 0;
  bool _hasActiveFinalizeProgress = false;
  bool _isGeneratingAiDraft = false;
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
      AppFeedback.warning(context, 'Preencha o relato para avançar');
      return;
    }
    if (_currentStep == 1 && _selectedResults.isEmpty) {
      AppFeedback.warning(context, 'Selecione pelo menos um resultado');
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
        AppFeedback.error(context, 'Microfone não disponível');
      }
    }
  }

  Future<void> _generateAiDraft() async {
    final rawReport = _reportController.text.trim();
    if (rawReport.isEmpty) {
      AppFeedback.warning(
        context,
        'Digite ou grave o relato antes de usar a IA assistiva.',
      );
      return;
    }

    setState(() => _isGeneratingAiDraft = true);
    HapticFeedback.selectionClick();

    try {
      final draft = await _occurrenceAiService.generateInstitutionalDraft(
        occurrenceId: widget.occurrenceId,
        rawReport: rawReport,
      );
      if (!mounted) return;
      final useDraft = await _showAiDraftReviewSheet(draft);
      if (useDraft == true && mounted) {
        _reportController.text = draft.draftText.trim();
        _reportController.selection = TextSelection.collapsed(
          offset: _reportController.text.length,
        );
        setState(() {});
        _scheduleDraftSave();
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Falha ao gerar minuta assistida: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingAiDraft = false);
    }
  }

  Future<bool?> _showAiDraftReviewSheet(OccurrenceAiDraft draft) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceSheet,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: AppTheme.primary.withAlpha(45)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primary.withAlpha(70),
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Minuta institucional',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                draft.usedAi
                                    ? 'Gerada por IA assistiva. Revise antes de usar.'
                                    : 'Gerada por modelo local. Revise antes de usar.',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (draft.attentionPoints.isNotEmpty) ...[
                      _AiAttentionBox(points: draft.attentionPoints),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.background.withAlpha(170),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.textPrimary.withAlpha(22),
                        ),
                      ),
                      child: Text(
                        draft.draftText,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'A IA nao finaliza a ocorrencia. Ela apenas organiza o texto; o responsavel precisa revisar e assumir o relato antes de continuar.',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(false),
                            child: Text(
                              'CANCELAR',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(true),
                            child: Text(
                              'USAR MINUTA',
                              style: GoogleFonts.inter(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
      AppFeedback.error(context, missing);
      return;
    }

    setState(() {
      _isFinalizing = true;
      _finalizeFraction = null;
      _finalizeStatus = _finalizationPhotos.isNotEmpty
          ? 'Preparando fotos...'
          : 'Selando ocorrência...';
    });
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
        AppFeedback.info(context, 'Ocorrência já está aguardando assinaturas.');
        return;
      }

      // Upload fotos de finalização (se houver)
      final photoUploadResults = await _uploadFinalizationPhotos();
      final photoUrls = photoUploadResults.map((r) => r.url).toList();
      final photoHashes = photoUploadResults.map((r) => r.sha256Hash).toList();

      if (mounted) {
        setState(() {
          _currentFinalizeUploadIndex = 0;
          _hasActiveFinalizeProgress = false;
          _finalizeFraction = null;
          _finalizeStatus = 'Selando ocorrência...';
        });
      }

      if (_hasCoSigners) {
        final closeResult = await vm
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

        if (!mounted) return;

        if (closeResult == CloseForSignaturesResult.sealedDirectly) {
          final sealedOccurrence = await vm.getById(widget.occurrenceId);
          final confirmedHash =
              sealedOccurrence?.integrityHash?.trim().isNotEmpty == true
              ? sealedOccurrence!.integrityHash!
              : '';

          if (!mounted) return;
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
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  OccurrenceTeamScreen(occurrenceId: widget.occurrenceId),
            ),
          );
          AppFeedback.success(context, 'Ocorrência fechada para assinaturas.');
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
        AppFeedback.error(context, e.message ?? 'Tempo limite excedido');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Erro ao finalizar: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFinalizing = false;
          _finalizeStatus = null;
          _finalizeFraction = null;
          _currentFinalizeUploadIndex = 0;
          _hasActiveFinalizeProgress = false;
        });
      }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isFinalizing && _finalizeFraction != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                width: double.infinity,
                child: LinearProgressIndicator(
                  value: (_currentFinalizeUploadIndex == 0 &&
                          !_hasActiveFinalizeProgress)
                      ? null
                      : _finalizeFraction,
                  backgroundColor: AppTheme.textPrimary.withAlpha(20),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isFinalizing ? null : _goBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: BorderSide(
                        color: AppTheme.textPrimary.withAlpha(40),
                      ),
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
                  onPressed: _canAdvance
                      ? (isLast ? _finalize : _goNext)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLast
                        ? AppTheme.success
                        : AppTheme.primary,
                    disabledBackgroundColor: AppTheme.textPrimary.withAlpha(30),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isFinalizing
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _finalizeStatus ?? 'Selando ocorrência...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
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
        ],
      ),
    );
  }

  // ─── Step 1: Relato ─────────────────────────────────────────────────

  Widget _buildAiDraftAction() {
    final enabled =
        _reportController.text.trim().isNotEmpty && !_isGeneratingAiDraft;
    final hasContent = _reportController.text.trim().isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : (hasContent ? 0.55 : 0.4),
      child: GestureDetector(
        onTap: enabled ? _generateAiDraft : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: enabled
                ? AppTheme.primary.withAlpha(15)
                : AppTheme.textPrimary.withAlpha(5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? AppTheme.primary.withAlpha(70)
                  : AppTheme.outline.withAlpha(60),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppTheme.primary.withAlpha(25)
                      : AppTheme.textPrimary.withAlpha(8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isGeneratingAiDraft
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.auto_awesome_rounded,
                        color: enabled
                            ? AppTheme.primary
                            : AppTheme.textTertiary,
                        size: 21,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isGeneratingAiDraft
                          ? 'Gerando minuta...'
                          : 'Transformar em minuta',
                      style: GoogleFonts.inter(
                        color: enabled
                            ? AppTheme.textPrimary
                            : AppTheme.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasContent
                          ? 'Organizo seu relato em texto institucional'
                          : 'Digite o relato primeiro',
                      style: GoogleFonts.inter(
                        color: enabled
                            ? AppTheme.textSecondary
                            : AppTheme.textMuted,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (!hasContent)
                Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.textMuted,
                  size: 16,
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppTheme.primary,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }

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
          const SizedBox(height: 12),
          _buildAiDraftAction(),
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
        AppFeedback.warning(context, 'Permissão negada para acessar mídia');
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
        AppFeedback.error(context, 'Erro ao capturar foto: $e');
      }
    }
  }

  Future<List<UploadResult>> _uploadFinalizationPhotos() async {
    if (_finalizationPhotos.isEmpty) return [];

    if (mounted) {
      setState(() {
        _finalizeStatus = 'Preparando fotos...';
        _finalizeFraction = null;
      });
    }

    // Fase 1: Preparação sequencial com tracking de candidatos
    final candidates =
        <({File original, File candidate, bool wasCompressed})>[];
    for (final original in _finalizationPhotos) {
      final compressed = await _mediaService.compressImage(original);
      candidates.add((
        original: original,
        candidate: compressed ?? original,
        wasCompressed: compressed != null,
      ));
    }

    // Fase 2: Aplicação da regra de guarda contra colisão de paths temporários
    final effectiveFiles =
        FinalizeOccurrenceScreen.resolveEffectiveFilesAfterCollisionGuard(
          candidates,
        );

    // Fase 3: Medição dos tamanhos efetivos finais para o denominador
    final fileSizes = <int>[];
    for (final file in effectiveFiles) {
      try {
        fileSizes.add(await file.length());
      } catch (_) {
        fileSizes.add(0);
      }
    }

    final aggregator = UploadProgressAggregator(fileSizes);
    final results = <UploadResult>[];
    final folder = 'occurrences/${widget.occurrenceId}/finalization';

    // Fase 4: Upload sequencial com progresso agregado real em bytes
    for (var i = 0; i < effectiveFiles.length; i++) {
      final file = effectiveFiles[i];
      final startSnap = aggregator.startFile(i);
      if (mounted) {
        setState(() {
          _currentFinalizeUploadIndex = i;
          _hasActiveFinalizeProgress = false;
          _finalizeFraction = startSnap.fraction;
          _finalizeStatus = FinalizeOccurrenceScreen.formatUploadStatus(
            currentFileIndex: i,
            totalFiles: effectiveFiles.length,
            fraction: startSnap.fraction,
            hasActiveProgress: false,
          );
        });
      }

      final result = await _storageService.uploadImageWithHash(
        file,
        folder,
        onProgress: (transferred, total) {
          if (!mounted) return;
          final snapshot = aggregator.updateFileProgress(i, transferred);
          setState(() {
            _currentFinalizeUploadIndex = i;
            _hasActiveFinalizeProgress = snapshot.hasActiveFileProgress;
            _finalizeFraction = snapshot.fraction;
            _finalizeStatus = FinalizeOccurrenceScreen.formatUploadStatus(
              currentFileIndex: i,
              totalFiles: effectiveFiles.length,
              fraction: snapshot.fraction,
              hasActiveProgress: snapshot.hasActiveFileProgress,
            );
          });
        },
      );

      if (result != null) {
        aggregator.completeFile(i);
        _hasActiveFinalizeProgress = false;
        results.add(result);
      } else {
        break;
      }
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

class _AiAttentionBox extends StatelessWidget {
  final List<String> points;

  const _AiAttentionBox({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.report_gmailerrorred_rounded,
                color: AppTheme.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Pontos de atencao',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '-',
                    style: GoogleFonts.inter(
                      color: AppTheme.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      point,
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
