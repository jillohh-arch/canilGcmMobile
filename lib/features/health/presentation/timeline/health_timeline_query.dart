import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';

/// Intervalo temporal estruturado para filtros da timeline.
///
/// - [start] e [end] são opcionais (limites abertos).
/// - Ambos inclusivos no contrato de apresentação.
/// - Intervalo invertido (start > end) é rejeitado.
final class HealthTimelinePeriod {
  HealthTimelinePeriod({this.start, this.end}) {
    final s = start;
    final e = end;
    if (s != null && e != null && s.isAfter(e)) {
      throw ArgumentError.value(
        this,
        'period',
        'start não pode ser posterior a end',
      );
    }
  }

  /// Início inclusivo (opcional).
  final DateTime? start;

  /// Fim inclusivo (opcional).
  final DateTime? end;

  bool get isUnbounded => start == null && end == null;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelinePeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Filtro por identidade profissional clínica (pode ser externa).
///
/// Não representa conta de usuário interno nem role.
/// Pelo menos um critério deve ser informado.
final class HealthTimelineProfessionalFilter {
  HealthTimelineProfessionalFilter({
    String? name,
    this.registrationType,
    String? registrationNumber,
  }) : name = _trimOrNull(name),
       registrationNumber = _trimOrNull(registrationNumber) {
    if (this.name == null &&
        registrationType == null &&
        this.registrationNumber == null) {
      throw ArgumentError(
        'HealthTimelineProfessionalFilter exige ao menos um critério',
      );
    }
  }

  final String? name;
  final ProfessionalRegistrationType? registrationType;
  final String? registrationNumber;

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineProfessionalFilter &&
      other.name == name &&
      other.registrationType == registrationType &&
      other.registrationNumber == registrationNumber;

  @override
  int get hashCode => Object.hash(name, registrationType, registrationNumber);
}

/// Identidade lógica de filtros (sem cursor de paginação).
///
/// Usada pelo controller para:
/// - race protection;
/// - preservação de dados no refresh;
/// - isolamento entre cães/filtros.
///
/// Trocar apenas o cursor **não** altera esta identidade.
final class HealthTimelineFilterIdentity {
  const HealthTimelineFilterIdentity({
    required this.dogId,
    required this.types,
    required this.period,
    required this.caseId,
    required this.professional,
    required this.pageSize,
  });

  final String dogId;

  /// Tipos filtrados (vazio = todos). Conjunto imutável, ordem irrelevante.
  final Set<HealthTimelineType> types;
  final HealthTimelinePeriod period;
  final String? caseId;
  final HealthTimelineProfessionalFilter? professional;
  final int pageSize;

  @override
  bool operator ==(Object other) {
    if (other is! HealthTimelineFilterIdentity) return false;
    if (other.dogId != dogId) return false;
    if (other.period != period) return false;
    if (other.caseId != caseId) return false;
    if (other.professional != professional) return false;
    if (other.pageSize != pageSize) return false;
    if (other.types.length != types.length) return false;
    for (final t in types) {
      if (!other.types.contains(t)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    dogId,
    period,
    caseId,
    professional,
    pageSize,
    Object.hashAllUnordered(types),
  );
}

/// Query estruturada da timeline (sem busca textual).
///
/// ## Identidade de filtro vs cursor
/// - [filterIdentity] descreve o que está sendo consultado.
/// - [cursor] é apenas paginação e **não** faz parte da identidade.
/// - [pageSize] entra na identidade (alterar muda o contrato de página).
final class HealthTimelineQuery {
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  HealthTimelineQuery({
    required String dogId,
    Set<HealthTimelineType> types = const {},
    HealthTimelinePeriod? period,
    String? caseId,
    this.professional,
    this.cursor,
    this.pageSize = defaultPageSize,
  }) : dogId = _normalizeDogId(dogId),
       types = Set.unmodifiable(Set<HealthTimelineType>.of(types)),
       period = period ?? HealthTimelinePeriod(),
       caseId = _trimOrNull(caseId) {
    if (pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'deve ser maior que zero',
      );
    }
    if (pageSize > maxPageSize) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'não pode exceder $maxPageSize',
      );
    }
  }

  final String dogId;
  final Set<HealthTimelineType> types;
  final HealthTimelinePeriod period;
  final String? caseId;
  final HealthTimelineProfessionalFilter? professional;
  final HealthTimelineCursor? cursor;
  final int pageSize;

  HealthTimelineFilterIdentity get filterIdentity =>
      HealthTimelineFilterIdentity(
        dogId: dogId,
        types: types,
        period: period,
        caseId: caseId,
        professional: professional,
        pageSize: pageSize,
      );

  HealthTimelineQuery copyWith({
    String? dogId,
    Set<HealthTimelineType>? types,
    HealthTimelinePeriod? period,
    String? caseId,
    bool clearCaseId = false,
    HealthTimelineProfessionalFilter? professional,
    bool clearProfessional = false,
    HealthTimelineCursor? cursor,
    bool clearCursor = false,
    int? pageSize,
  }) {
    return HealthTimelineQuery(
      dogId: dogId ?? this.dogId,
      types: types ?? this.types,
      period: period ?? this.period,
      caseId: clearCaseId ? null : (caseId ?? this.caseId),
      professional: clearProfessional
          ? null
          : (professional ?? this.professional),
      cursor: clearCursor ? null : (cursor ?? this.cursor),
      pageSize: pageSize ?? this.pageSize,
    );
  }

  /// Cópia sem cursor (primeira página).
  HealthTimelineQuery withoutCursor() => copyWith(clearCursor: true);

  static String _normalizeDogId(String dogId) {
    final n = dogId.trim();
    if (n.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'dogId não pode ser vazio');
    }
    return n;
  }

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineQuery &&
      other.filterIdentity == filterIdentity &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(filterIdentity, cursor);
}
