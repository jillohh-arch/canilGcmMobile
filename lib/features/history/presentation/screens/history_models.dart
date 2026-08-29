// ignore_for_file: curly_braces_in_flow_control_structures

part of 'history_screen.dart';

enum HistoryEntryType { health, training, occurrence, nutrition }

class HistoryEntry {
  final String id;
  final HistoryEntryType type;
  final String title;
  final String subtitle;
  final DateTime time;
  final String author;
  final String authorId;
  final String tag;
  final IconData icon;
  final Color color;
  final String location;
  final bool isInProgress;
  final DateTime? editedAt;
  final dynamic originalModel;
  final Map<String, dynamic> details;

  const HistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.author,
    this.authorId = '',
    required this.tag,
    required this.icon,
    required this.color,
    this.location = '',
    this.isInProgress = false,
    this.editedAt,
    this.originalModel,
    this.details = const {},
  });

  DateTime get date => DateTime(time.year, time.month, time.day);

  String get category {
    switch (type) {
      case HistoryEntryType.health:
        return 'Saúde';
      case HistoryEntryType.training:
        return 'Treino';
      case HistoryEntryType.occurrence:
        return 'Ocorrência';
      case HistoryEntryType.nutrition:
        return 'Nutrição';
    }
  }

  Color get categoryColor => color;

  IconData get categoryIcon => icon;

  String get heroTag => '${type.name}_$id';

  HistoryEntry copyWith({
    String? id,
    HistoryEntryType? type,
    String? title,
    String? subtitle,
    DateTime? time,
    String? author,
    String? authorId,
    String? tag,
    IconData? icon,
    Color? color,
    String? location,
    bool? isInProgress,
    DateTime? editedAt,
    dynamic originalModel,
    Map<String, dynamic>? details,
  }) {
    return HistoryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      time: time ?? this.time,
      author: author ?? this.author,
      authorId: authorId ?? this.authorId,
      tag: tag ?? this.tag,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      location: location ?? this.location,
      isInProgress: isInProgress ?? this.isInProgress,
      editedAt: editedAt ?? this.editedAt,
      originalModel: originalModel ?? this.originalModel,
      details: details ?? this.details,
    );
  }
}

class HistoryDayGroup {
  final DateTime date;
  final String label;
  final String dateFormatted;
  final List<HistoryEntry> entries;

  const HistoryDayGroup({
    required this.date,
    required this.label,
    required this.dateFormatted,
    required this.entries,
  });
}

class RecordDetail {
  final String id;
  final HistoryEntryType type;
  final String category;
  final String title;
  final String subtitle;
  final String location;
  final DateTime dateTime;
  final String author;
  final String dogName;
  final String handlerName;
  final String status;
  final String syncStatus;
  final String duration;
  final String team;
  final String notes;
  final IconData icon;
  final Color color;
  final List<InternalEvent> internalEvents;
  final List<AuditEvent> auditEvents;
  final HistoryEntry source;

  const RecordDetail({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.dateTime,
    required this.author,
    required this.dogName,
    required this.handlerName,
    required this.status,
    required this.syncStatus,
    required this.duration,
    required this.team,
    required this.notes,
    required this.icon,
    required this.color,
    required this.internalEvents,
    required this.auditEvents,
    required this.source,
  });

  String get typeLabel {
    switch (type) {
      case HistoryEntryType.health:
        return 'Saúde';
      case HistoryEntryType.training:
        return 'Treino';
      case HistoryEntryType.occurrence:
        return 'Ocorrência';
      case HistoryEntryType.nutrition:
        return 'Nutrição';
    }
  }

  String get typeChip => typeLabel.toUpperCase();

  String get headerTitle {
    if (title.trim().isEmpty || title == typeLabel) return typeLabel;
    return '$typeLabel • $title';
  }

  bool get isOccurrence => type == HistoryEntryType.occurrence;

  static RecordDetail fromEntry(HistoryEntry entry) {
    final normalizedTitle = _cleanText(entry.title);
    final typeLabel = _typeLabel(entry.type);
    final splitTitle = _lastTitlePart(normalizedTitle);
    final details = entry.details;

    final category = _firstNonEmpty([
      if (entry.type == HistoryEntryType.occurrence ||
          entry.type == HistoryEntryType.training)
        splitTitle,
      _detailValue(details, const ['Categoria', 'category']),
      _detailValue(details, const ['Tipo', 'type']),
      entry.category,
    ]);

    final title = _firstNonEmpty([
      if (entry.type == HistoryEntryType.occurrence ||
          entry.type == HistoryEntryType.training)
        category,
      normalizedTitle,
      typeLabel,
    ]);

    final location = _firstNonEmpty([
      entry.location,
      _detailValue(details, const ['Local', 'local']),
      if (entry.type == HistoryEntryType.occurrence) entry.subtitle,
      'Local não informado',
    ]);

    // Pesagem recognized-legacy sem recorder chega com author vazio. Nesse
    // caso a autoria permanece ausente: não aplicar o fallback padrão
    // ('Ragonha'/'GCM ...'), não inventar condutor nem responsável técnico.
    final isAuthorlessWeight =
        details['_healthKind'] == 'weight' && entry.author.trim().isEmpty;

    final author = isAuthorlessWeight ? '' : _normalizeAuthor(entry.author);
    final handlerName = isAuthorlessWeight
        ? _detailValue(details, const [
            'Condutor',
            'Responsável',
            'Responsavel',
          ])
        : _firstNonEmpty([
            _detailValue(details, const [
              'Condutor',
              'Responsável',
              'Responsavel',
            ]),
            author.replaceFirst('GCM ', ''),
            'Ragonha',
          ]);
    final dogName = _firstNonEmpty([
      _detailValue(details, const ['Cão', 'Cao', 'Dog', 'dogName']),
      'Bono',
    ]);

    final rawStatus = _firstNonEmpty([
      _detailValue(details, const ['Status', 'status']),
      entry.isInProgress ? 'Em andamento' : 'Finalizado',
    ]);
    final status = entry.isInProgress
        ? 'Em andamento'
        : _normalizeStatus(rawStatus);

    final notes = _firstNonEmpty([
      _detailValue(details, const [
        'Observações',
        'Observacoes',
        'ObservaÃÂ§ÃÂµes',
        'Descrição',
        'Descricao',
        'DescriÃÂ§ÃÂ£o',
        'Notas',
        'Detalhes',
      ]),
      if (entry.type != HistoryEntryType.occurrence) entry.subtitle,
    ]);

    final duration = _firstNonEmpty([
      _detailValue(details, const ['Duração', 'Duracao', 'DuraÃÂ§ÃÂ£o']),
      _occurrenceDuration(entry),
      entry.type == HistoryEntryType.occurrence ? '42 min' : 'Não informado',
    ]);

    return RecordDetail(
      id: entry.id,
      type: entry.type,
      category: category,
      title: title,
      subtitle: _cleanText(entry.subtitle),
      location: location,
      dateTime: entry.time,
      author: author,
      dogName: dogName,
      handlerName: handlerName,
      status: status,
      syncStatus: entry.isInProgress ? 'Pendente' : 'Sincronizado',
      duration: duration,
      team: _firstNonEmpty([
        _detailValue(details, const ['Equipe', 'team']),
        entry.type == HistoryEntryType.occurrence
            ? '2 GCMs'
            : 'Equipe não informada',
      ]),
      notes: notes,
      icon: entry.icon,
      color: entry.color,
      internalEvents: _internalEventsFor(entry),
      auditEvents: _auditEventsFor(entry, author),
      source: entry,
    );
  }

  static String _typeLabel(HistoryEntryType type) {
    switch (type) {
      case HistoryEntryType.health:
        return 'Saúde';
      case HistoryEntryType.training:
        return 'Treino';
      case HistoryEntryType.occurrence:
        return 'Ocorrência';
      case HistoryEntryType.nutrition:
        return 'Nutrição';
    }
  }

  static String _lastTitlePart(String title) {
    final normalized = title.replaceAll('ââ‚¬Â¢', '•');
    final parts = normalized
        .split('•')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? normalized : parts.last;
  }

  static String _detailValue(Map<String, dynamic> details, List<String> keys) {
    for (final key in keys) {
      if (!details.containsKey(key)) continue;
      final value = details[key];
      if (value == null) continue;
      if (value is DateTime)
        return DateFormat('dd/MM/yyyy HH:mm').format(value);
      final text = _cleanText(value.toString());
      if (text.trim().isNotEmpty && text.trim() != 'null') return text.trim();
    }
    return '';
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final cleaned = _cleanText(value).trim();
      if (cleaned.isNotEmpty && cleaned != 'null' && cleaned != '--') {
        return cleaned;
      }
    }
    return '';
  }

  static String _normalizeAuthor(String author) {
    final cleaned = _cleanText(author).trim();
    if (cleaned.isEmpty) return 'GCM Ragonha';
    if (cleaned == 'Você') return 'GCM Ragonha';
    if (cleaned.startsWith('GCM ') || cleaned.startsWith('Veterinário')) {
      return cleaned;
    }
    return 'GCM $cleaned';
  }

  static String _normalizeStatus(String status) {
    final cleaned = _cleanText(status).trim();
    final lower = cleaned.toLowerCase();
    if (lower.contains('andamento')) return 'Em andamento';
    if (lower.contains('conclu') || lower.contains('final'))
      return 'Finalizado';
    if (cleaned.isEmpty) return 'Finalizado';
    return cleaned;
  }

  static String _occurrenceDuration(HistoryEntry entry) {
    final startRaw = _detailValue(entry.details, const [
      'Início',
      'Inicio',
      'InÃÂ­cio',
    ]);
    final endRaw = _detailValue(entry.details, const [
      'Fim',
      'Término',
      'Termino',
    ]);
    if (startRaw.isEmpty || endRaw.isEmpty) return '';

    final start = _parseTimeOnDate(startRaw, entry.time);
    final end = _parseTimeOnDate(endRaw, entry.time);
    if (start == null || end == null || end.isBefore(start)) return '';

    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return '';
    return '$minutes min';
  }

  static DateTime? _parseTimeOnDate(String raw, DateTime date) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static List<InternalEvent> _internalEventsFor(HistoryEntry entry) {
    final updates = entry.details['_progressUpdates'];
    if (updates is List && updates.isNotEmpty) {
      return updates.map((update) {
        final timestamp = _readUpdateTimestamp(update) ?? entry.time;
        return InternalEvent(
          time: timestamp,
          title: _firstNonEmpty([
            _readUpdateField(update, 'title'),
            'Atualização operacional',
          ]),
          subtitle: _readUpdateField(update, 'description'),
        );
      }).toList();
    }

    if (entry.type == HistoryEntryType.occurrence) {
      final events = [
        InternalEvent(time: entry.time, title: 'Registro iniciado'),
        InternalEvent(
          time: entry.time.add(const Duration(minutes: 5)),
          title: 'Chegada ao local',
        ),
        InternalEvent(
          time: entry.time.add(const Duration(minutes: 11)),
          title: 'Cão empregado na varredura',
        ),
        if (_hasMedia(entry))
          InternalEvent(
            time: entry.time.add(const Duration(minutes: 14)),
            title: 'Foto anexada',
          ),
        InternalEvent(
          time: entry.time.add(const Duration(minutes: 17)),
          title: 'Área verificada',
        ),
        InternalEvent(
          time: entry.time.add(const Duration(minutes: 42)),
          title: entry.isInProgress
              ? 'Registro em andamento'
              : 'Registro finalizado',
        ),
      ];
      return events;
    }

    return [
      InternalEvent(time: entry.time, title: 'Registro criado'),
      InternalEvent(
        time: (entry.editedAt ?? entry.time).add(const Duration(minutes: 1)),
        title: entry.isInProgress
            ? 'Aguardando sincronização'
            : 'Sincronizado com o sistema',
      ),
    ];
  }

  static String _readUpdateField(dynamic update, String key) {
    if (update is Map) return _cleanText(update[key]?.toString() ?? '');
    try {
      final value = key == 'title' ? update.title : update.description;
      return _cleanText(value?.toString() ?? '');
    } catch (_) {
      return '';
    }
  }

  static DateTime? _readUpdateTimestamp(dynamic update) {
    dynamic value;
    if (update is Map) {
      value = update['timestamp'];
    } else {
      try {
        value = update.timestamp;
      } catch (_) {
        value = null;
      }
    }

    if (value is DateTime) return value;
    return null;
  }

  static List<AuditEvent> _auditEventsFor(HistoryEntry entry, String author) {
    final rawTrail = entry.details['_auditTrail'];
    if (rawTrail is List && rawTrail.isNotEmpty) {
      final events =
          rawTrail
              .whereType<Map>()
              .map((raw) => _auditEventFromMap(raw, author, entry.time))
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (events.isNotEmpty) return events;
    }

    final editedAt = entry.editedAt;
    // Sem autor factual (ex.: pesagem legada sem recorder), o evento de criação
    // não afirma autoria: usa 'Registro criado' em vez de 'Criado por <nome>'.
    final hasAuthor = author.trim().isNotEmpty;
    return [
      AuditEvent(
        timestamp: entry.time,
        action: hasAuthor ? 'Criado por' : 'Registro criado',
        user: author,
      ),
      if (_hasMedia(entry))
        AuditEvent(
          timestamp: entry.time.add(const Duration(minutes: 14)),
          action: 'Foto anexada por',
          user: author,
        ),
      if (editedAt != null)
        AuditEvent(timestamp: editedAt, action: 'Editado por', user: author),
      AuditEvent(
        timestamp: (editedAt ?? entry.time).add(const Duration(minutes: 1)),
        action: entry.isInProgress
            ? 'Sincronização pendente'
            : 'Sincronizado com o sistema',
      ),
    ];
  }

  static AuditEvent _auditEventFromMap(
    Map raw,
    String fallbackUser,
    DateTime fallbackTime,
  ) {
    final action = _cleanText(raw['action']?.toString() ?? '');
    final fieldName = _cleanText(raw['field_name']?.toString() ?? '');
    final user = _cleanText(
      raw['by_name']?.toString() ??
          raw['by_ra']?.toString() ??
          raw['performed_by']?.toString() ??
          fallbackUser,
    );
    final timestamp =
        _parseAuditTimestamp(raw['at']) ??
        _parseAuditTimestamp(raw['performed_at']) ??
        _parseAuditTimestamp(raw['created_at']) ??
        fallbackTime;

    final label = _auditActionLabel(action, fieldName);

    return AuditEvent(timestamp: timestamp, action: label, user: user);
  }

  static String _auditActionLabel(String action, String fieldName) {
    final fieldLabel = _auditFieldLabel(fieldName);
    return switch (action) {
      'created' => 'Criado por',
      'updated' when fieldLabel.isNotEmpty => 'Alterou $fieldLabel por',
      'updated' => 'Editado por',
      'finalized' => 'Finalizado por',
      'finalized_with_pending' => 'Finalizado com pendência por',
      'closed_for_signatures' => 'Enviado para assinatura por',
      'signature_added' => 'Assinatura registrada por',
      'signature_completed' => 'Assinaturas concluídas por',
      'correction_requested' => 'Correção solicitada por',
      'ai_draft_generated' => 'Relato por IA gerado por',
      'event_created' => 'Evento registrado por',
      'event_updated' when fieldLabel.isNotEmpty =>
        'Ajustou $fieldLabel do evento por',
      'event_updated' => 'Evento ajustado por',
      'event_deleted' => 'Evento arquivado por',
      'deleted' => 'Arquivado por',
      'restored' => 'Restaurado por',
      _ => action.isEmpty ? 'Registrado por' : 'Registro atualizado por',
    };
  }

  static String _auditFieldLabel(String fieldName) {
    if (fieldName.isEmpty) return '';
    final normalized = fieldName
        .split('.')
        .where((part) => !_looksLikeGeneratedId(part))
        .lastOrNull;
    final key = normalized ?? fieldName;
    return switch (key) {
      'duration_so_far' => 'duração da ocorrência',
      'final_report' => 'relato institucional',
      'finalization_photos' => 'fotos de finalização',
      'finalization_photo_hashes' => 'metadados das fotos',
      'location_address' => 'endereço',
      'place_label' => 'local do evento',
      'gps_lat' || 'gps_lng' || 'gps_accuracy' => 'coordenada GPS',
      'photo_urls' || 'photo_metadata' => 'mídias',
      'results' => 'resultado',
      'details' => 'detalhes',
      'team' => 'equipe',
      'signature_deadline' => 'prazo de assinatura',
      'signature_round' => 'rodada de assinatura',
      'participation_status' => 'ciência da guarnição',
      'description' => 'descrição',
      'title' => 'título',
      'category' => 'tipo',
      'timestamp' => 'horário',
      _ => '',
    };
  }

  static bool _looksLikeGeneratedId(String value) {
    if (value.length < 12) return false;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
  }

  static DateTime? _parseAuditTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      final converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _hasMedia(HistoryEntry entry) {
    final media = entry.details['_mediaAttachments'];
    return media is List && media.isNotEmpty;
  }

  static String _cleanText(String value) {
    return value
        .replaceAll('ÃÂ¡', 'á')
        .replaceAll('ÃÂ ', 'à')
        .replaceAll('ÃÂ£', 'ã')
        .replaceAll('ÃÂ¢', 'â')
        .replaceAll('ÃÂ©', 'é')
        .replaceAll('ÃÂª', 'ê')
        .replaceAll('ÃÂ­', 'í')
        .replaceAll('ÃÂ³', 'ó')
        .replaceAll('ÃÂ´', 'ô')
        .replaceAll('ÃÂµ', 'õ')
        .replaceAll('ÃÂº', 'ú')
        .replaceAll('ÃÂ§', 'ç')
        .replaceAll('Ãâ€¡', 'Ç')
        .replaceAll('ÃÅ¡', 'Ú')
        .replaceAll('ÃÂª', 'ê')
        .replaceAll('ââ‚¬Â¢', '•')
        .replaceAll('ââ‚¬â€œ', 'â€“')
        .replaceAll('ââ‚¬â€', '—');
  }
}

class InternalEvent {
  final DateTime time;
  final String title;
  final String subtitle;

  const InternalEvent({
    required this.time,
    required this.title,
    this.subtitle = '',
  });
}

class AuditEvent {
  final DateTime timestamp;
  final String action;
  final String user;

  const AuditEvent({
    required this.timestamp,
    required this.action,
    this.user = '',
  });
}
