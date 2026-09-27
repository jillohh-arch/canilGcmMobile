import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import 'authoritative_time_gateway.dart';
import 'authoritative_time_models.dart';

typedef AuthoritativeTimeCallableInvoker =
    Future<Object?> Function(String functionName, Map<String, dynamic> data);

final class FirebaseFunctionsAuthoritativeTimeGateway
    implements AuthoritativeTimeGateway {
  FirebaseFunctionsAuthoritativeTimeGateway({
    FirebaseFunctions? functions,
    AuthoritativeTimeCallableInvoker? invoker,
    Duration requestTimeout = defaultTimeout,
  }) : _functionsOverride = functions,
       _invokerOverride = invoker,
       _requestTimeout = requestTimeout;

  static const String callableName = 'systemAuthoritativeTimeNow';
  static const String region = 'southamerica-east1';
  static const Duration defaultTimeout = Duration(seconds: 10);

  final FirebaseFunctions? _functionsOverride;
  final AuthoritativeTimeCallableInvoker? _invokerOverride;
  final Duration _requestTimeout;
  FirebaseFunctions? _cachedFunctions;

  FirebaseFunctions get _functions {
    return _cachedFunctions ??=
        _functionsOverride ?? FirebaseFunctions.instanceFor(region: region);
  }

  Future<Object?> _invoke(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final override = _invokerOverride;
    if (override != null) {
      return await override(functionName, data).timeout(_requestTimeout);
    }
    final callable = _functions.httpsCallable(
      functionName,
      options: HttpsCallableOptions(timeout: _requestTimeout),
    );
    final result = await callable.call(data).timeout(_requestTimeout);
    return result.data;
  }

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    try {
      final raw = await _invoke(callableName, const {'protocol_version': 1});
      if (raw is! Map) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.invalidResponse,
          'Resposta temporal sem mapa estruturado.',
        );
      }
      return AuthoritativeTimeRemoteResponse.fromMap(
        Map<String, dynamic>.from(raw),
      );
    } on TimeoutException {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unavailable,
        'Horário autoritativo temporariamente indisponível.',
      );
    } on AuthoritativeTimeFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      final code = error.code.trim().toLowerCase();
      if (code == 'unauthenticated') {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unauthenticated,
          'Autenticação necessária para sincronizar o horário.',
        );
      }
      if (code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'network-request-failed') {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unavailable,
          'Horário autoritativo temporariamente indisponível.',
        );
      }
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unexpected,
        'Falha ao sincronizar o horário autoritativo.',
      );
    } catch (_) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unexpected,
        'Falha ao sincronizar o horário autoritativo.',
      );
    }
  }
}
