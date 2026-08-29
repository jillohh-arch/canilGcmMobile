import 'authoritative_time_models.dart';

abstract interface class AuthoritativeTimeGateway {
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime();
}
