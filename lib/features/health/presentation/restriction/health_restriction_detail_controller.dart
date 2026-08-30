import 'package:flutter/foundation.dart';

import '../../domain/health_restriction_read_gateway.dart';
import '../../domain/operational_restriction.dart';

/// Estado de carregamento do detalhe canônico de UMA restrição.
///
/// B4-C.2. Somente leitura: END/CANCEL entram em B4-C.3/B4-C.4.
enum HealthRestrictionDetailStatus { idle, loading, loaded, failed }

/// Controller do detalhe canônico de restrição operacional.
///
/// ## Autoridade
///
/// A identidade vem de `dogId` + `restrictionId`, ambos imutáveis e recebidos de
/// fora. Nunca de descrição, nível, categoria, posição em lista ou "primeira
/// restrição ativa". O `restrictionId` já chega canônico — a tradução do id de
/// projeção acontece antes, na boundary do B4-C.1.
///
/// ## Fronteira de I/O
///
/// Todo acesso a dados passa pelo [HealthRestrictionReadGateway] (B4-B2). Este
/// controller não conhece Firestore, não monta path e não faz query: exatamente
/// UM `getById` por carga.
///
/// ## Falha nunca vira dado
///
/// Uma leitura que falha permanece `failed` com a falha tipada preservada. Não
/// existe fallback para a projeção resumida: a projeção pode estar obsoleta, e
/// isso não autoriza inventar detalhe canônico.
final class HealthRestrictionDetailController extends ChangeNotifier {
  HealthRestrictionDetailController({
    required this.dogId,
    required this.restrictionId,
    required HealthRestrictionReadGateway gateway,
  }) : _gateway = gateway;

  /// K9 cujo Health está sendo exibido. Capturado na navegação, nunca relido
  /// de uma seleção global que pode mudar durante o carregamento.
  final String dogId;

  /// Id canônico da restrição tocada. Já sem o prefixo de projeção.
  final String restrictionId;

  final HealthRestrictionReadGateway _gateway;

  HealthRestrictionDetailStatus _status = HealthRestrictionDetailStatus.idle;
  OperationalRestriction? _restriction;
  HealthRestrictionReadFailure? _failure;
  bool _loading = false;

  HealthRestrictionDetailStatus get status => _status;

  /// Restrição canônica carregada. Não-nula apenas em [loaded].
  OperationalRestriction? get restriction => _restriction;

  /// Falha tipada da última tentativa. Não-nula apenas em [failed].
  HealthRestrictionReadFailure? get failure => _failure;

  /// Carrega (ou recarrega) o detalhe canônico.
  ///
  /// Guarda contra carga dupla: um rebuild durante a leitura não dispara um
  /// segundo `getById`. Retry repete exatamente a mesma identidade.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _status = HealthRestrictionDetailStatus.loading;
    _failure = null;
    notifyListeners();

    try {
      final result = await _gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );
      switch (result) {
        case HealthRestrictionReadSuccess(:final restriction):
          _restriction = restriction;
          _status = HealthRestrictionDetailStatus.loaded;
        case HealthRestrictionReadError(:final failure):
          // Preserva o código tipado: notFound, permissionDenied, unavailable,
          // integrity e validation exigem apresentações distintas.
          _failure = failure;
          _status = HealthRestrictionDetailStatus.failed;
      }
    } catch (e) {
      debugPrint('[HealthRestrictionDetail] leitura falhou: $e');
      _failure = const HealthRestrictionReadFailure(
        code: HealthRestrictionReadErrorCode.unexpected,
        message: 'Não foi possível carregar a restrição.',
      );
      _status = HealthRestrictionDetailStatus.failed;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
