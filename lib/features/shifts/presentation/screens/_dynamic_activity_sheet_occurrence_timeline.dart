part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrenceTimeline
    on _DynamicActivitySheetState {
  void _populateOccurrenceTimeline(Map<String, dynamic> data) {
    _occurrenceTimeline.clear();

    if (data['progressUpdates'] is List) {
      _occurrenceTimeline.addAll(
        (data['progressUpdates'] as List).map(
          (e) => IncidentProgressUpdate.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        ),
      );
    }

    _ensureInitialOccurrenceTimelineEntry(
      timestamp: _timelineStartFromOccurrenceData(data),
      authorId: data['_rawHandlerId']?.toString(),
    );
  }

  DateTime _timelineStartFromOccurrenceData(Map<String, dynamic> data) {
    if (data['startedAt'] != null) {
      return parseFirestoreDate(data['startedAt']);
    }
    if (data['_rawDate'] is DateTime) {
      return data['_rawDate'] as DateTime;
    }
    if (data['date'] != null) {
      return parseFirestoreDate(data['date']);
    }
    return _activeOccurrenceStartedAt ?? _resolveFormTimestamp();
  }

  IncidentProgressUpdate _initialOccurrenceTimelineEntry({
    DateTime? timestamp,
    String? authorId,
    String? authorName,
  }) {
    final description = _descriptionController.text.trim();

    return IncidentProgressUpdate(
      title: 'Início da ocorrência',
      description: description.isNotEmpty
          ? description
          : 'Ocorrência iniciada pela equipe.',
      timestamp:
          timestamp ?? _activeOccurrenceStartedAt ?? _resolveFormTimestamp(),
      location: _locationController.text.trim(),
      authorId: authorId,
      authorName: authorName,
    );
  }

  bool _isInitialOccurrenceTimelineEntry(IncidentProgressUpdate update) {
    final normalized = const TextMatchService().normalizePtBr(update.title);
    return normalized.contains('inicio') ||
        normalized.contains('registro inicial');
  }

  void _ensureInitialOccurrenceTimelineEntry({
    DateTime? timestamp,
    String? authorId,
    String? authorName,
  }) {
    if (_occurrenceTimeline.any(_isInitialOccurrenceTimelineEntry)) {
      return;
    }

    _occurrenceTimeline.insert(
      0,
      _initialOccurrenceTimelineEntry(
        timestamp: timestamp,
        authorId: authorId,
        authorName: authorName,
      ),
    );
  }
}
