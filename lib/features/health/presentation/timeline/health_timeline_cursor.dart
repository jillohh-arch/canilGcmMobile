/// Cursor opaco de paginação da timeline.
///
/// A apresentação e o controller não interpretam o conteúdo.
/// Apenas a [HealthTimelineSource] que produziu o cursor deve decodificá-lo.
///
/// Não expõe DocumentSnapshot, offset, path de collection ou Firestore.
final class HealthTimelineCursor {
  /// Cria um cursor a partir de um token opaco controlado pela source.
  const HealthTimelineCursor(this.token)
    : assert(token != '', 'token do cursor não pode ser vazio');

  /// Token opaco. Não deve ser interpretado pela UI.
  final String token;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineCursor && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'HealthTimelineCursor(<opaque>)';
}
