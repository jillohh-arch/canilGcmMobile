part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetEventDetails on _DynamicActivitySheetState {
  Future<List<File>> _pickOccurrenceEventPhotos() async {
    final files = await _occCtrl.pickEventPhotos();
    if (files.isEmpty) return const [];
    HapticFeedback.lightImpact();
    return files;
  }

  Future<List<Map<String, dynamic>>> _uploadOccurrenceEventPhotos(
    List<File> files,
  ) async {
    return _occCtrl.uploadEventPhotos(files);
  }

  Future<ResolvedLocation> _captureOccurrenceEventLocation() async {
    final location = await const LocationResolutionService()
        .currentHighAccuracy();
    HapticFeedback.lightImpact();
    return location;
  }

  Future<void> _openOccurrenceEventDetails(int index) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;
    final update = _occurrenceTimeline[index];
    final draft = OccurrenceEventDraft(update);
    final result = await _showOccurrenceEventDetailsSheet(update, draft);
    draft.dispose();
    if (result == null || !mounted) return;
    await _applyOccurrenceEventChange(index, result);
  }

  Future<OccurrenceEventChange?> _showOccurrenceEventDetailsSheet(
    IncidentProgressUpdate update,
    OccurrenceEventDraft draft,
  ) {
    return _showTacticalBottomSheet<OccurrenceEventChange>(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => OccurrenceEventDetailsSheet(
            update: update,
            titleController: draft.titleController,
            descriptionController: draft.descriptionController,
            timestampLabel: _formatOccurrenceEventTimestamp(update.timestamp),
            eventLocation: draft.location,
            eventAttachments: draft.attachments,
            pendingPhotoCount: draft.pendingPhotoCount,
            backgroundColor: _kHudBackground,
            panelColor: _kHudPanel,
            accentColor: _kHudCyan,
            successColor: _kHudGreen,
            warningColor: _kHudAmber,
            dangerColor: _kHudRed,
            onAddPhotos: () async {
              final files = await _pickOccurrenceEventPhotos();
              if (files.isEmpty) return;
              setSheetState(() => draft.addPendingPhotos(files));
            },
            onCaptureLocation: () async {
              try {
                final eventPoint = await _captureOccurrenceEventLocation();
                setSheetState(() => draft.applyLocation(eventPoint));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Não foi possível capturar o local: $e'),
                  ),
                );
              }
            },
            onDelete: () =>
                Navigator.of(context).pop(const OccurrenceEventChange.delete()),
            onSave: () async {
              try {
                final uploaded = await _uploadOccurrenceEventPhotos(
                  draft.pendingPhotos,
                );
                draft.addAttachments(uploaded);
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pop(OccurrenceEventChange.update(draft.toProgressUpdate()));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _cleanSaveError(e).isEmpty
                          ? 'Não foi possível salvar as evidências.'
                          : _cleanSaveError(e),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  String _formatOccurrenceEventTimestamp(DateTime timestamp) {
    return '${_formatDatePtBr(timestamp)} às ${_formatTimeOfDay(timestamp)}';
  }

  Future<void> _syncActiveOccurrenceSnapshot(DateTime updatedAt) async {
    if (!_hasActiveIncidentDocument) return;
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);
    await _saveActiveOccurrenceSnapshot(
      incidentVM: incidentVM,
      currentRa: operatorContext.ra,
      currentOperatorName: operatorContext.name,
      updatedAt: updatedAt,
    );
  }

  Future<void> _applyOccurrenceEventChange(
    int index,
    OccurrenceEventChange change,
  ) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;
    final previousTimeline = List<IncidentProgressUpdate>.from(
      _occurrenceTimeline,
    );

    setState(() {
      _isSaving = true;
      _saveStatus = change.delete
          ? 'Excluindo evento...'
          : 'Atualizando evento...';
      _saveFailed = false;
      if (change.delete) {
        _occurrenceTimeline.removeAt(index);
      } else if (change.update != null) {
        _occurrenceTimeline[index] = change.update!;
      }
    });

    try {
      await _syncActiveOccurrenceSnapshot(DateTime.now());
      if (!mounted) return;
      _setSaveStatus('Linha do tempo sincronizada.');
      _showOperationalSnack(
        change.delete ? 'Evento excluído.' : 'Evento atualizado.',
        backgroundColor: const Color(0xFF123044),
        icon: change.delete
            ? Icons.delete_outline_rounded
            : Icons.cloud_done_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _occurrenceTimeline
          ..clear()
          ..addAll(previousTimeline);
        _saveFailed = true;
        _saveStatus = 'Falha ao sincronizar evento.';
      });
      _showOperationalSnack(
        _cleanSaveError(e).isEmpty
            ? 'Não foi possível sincronizar o evento.'
            : _cleanSaveError(e),
        backgroundColor: const Color(0xFFE53935),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
