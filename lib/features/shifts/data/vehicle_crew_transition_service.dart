import 'package:cloud_functions/cloud_functions.dart';

class VehicleCrewTransitionService {
  VehicleCrewTransitionService({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFunctions _functions;

  Future<void> inviteMember({
    required String crewId,
    required String handlerId,
  }) async {
    final callable = _functions.httpsCallable('inviteVehicleCrewMember');
    await callable.call<void>({'crew_id': crewId, 'handler_id': handlerId});
  }

  Future<void> respondToInvitation({
    required String crewId,
    required bool accept,
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('respondVehicleCrewInvitation');
    await callable.call<void>({
      'crew_id': crewId,
      'accept': accept,
      'reason': reason,
    });
  }
}
