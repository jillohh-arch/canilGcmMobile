import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_result.dart';

/// Contrato abstrato de leitura **global** (multi-K9) da Agenda Preventiva.
///
/// - Sem Firebase/Firestore nesta fronteira (implementação concreta em `data/`).
/// - Somente leitura.
/// - Sempre bounded: consulta exige catálogo autorizado de `dog_id`.
///
/// Erros continuam sendo sinalizados por `HealthScheduleSourceException`
/// (mesma fronteira tipada do reader per-dog): `permission-denied` permanece
/// erro de autorização e `failed-precondition` permanece erro de query/índice.
/// Nenhum dos dois vira estado vazio.
abstract interface class HealthScheduleGlobalSource {
  /// Carrega a janela bounded conforme [query].
  ///
  /// Catálogo vazio devolve resultado vazio **sem emitir query**.
  Future<HealthScheduleGlobalResult> loadGlobal(
    HealthScheduleGlobalQuery query,
  );
}
