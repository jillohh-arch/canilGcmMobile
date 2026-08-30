/// Cursor opaco de paginação da Agenda Preventiva.
///
/// A apresentação não interpreta o token — apenas reencaminha à fonte.
final class HealthScheduleCursor {
  HealthScheduleCursor(String token) : token = token.trim() {
    if (this.token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'cursor não pode ser vazio');
    }
  }

  final String token;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleCursor && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'HealthScheduleCursor($token)';
}
