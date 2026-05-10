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
}
