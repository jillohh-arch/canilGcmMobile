import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';
import 'package:canil_gcm/features/training/domain/training_promotion_request.dart';

class TrainingPromotionService {
  TrainingPromotionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('promotion_requests');

  Stream<TrainingPromotionRequest?> watchRequest(String requestId) {
    return _requests
        .doc(requestId)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? TrainingPromotionRequest.fromFirestore(snapshot)
              : null,
        );
  }

  Future<TrainingPromotionRequest?> pendingRequestForModule({
    required String dogId,
    required String modality,
    required String moduleId,
    required String requesterRa,
  }) async {
    final snapshot = await _requests
        .where('dog_id', isEqualTo: dogId)
        .where('modality', isEqualTo: modality)
        .where('module_id', isEqualTo: moduleId)
        .where('status', isEqualTo: 'pending')
        .where('requester_ra', isEqualTo: requesterRa)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return TrainingPromotionRequest.fromFirestore(snapshot.docs.first);
  }

  Future<String> requestPromotion({
    required Dog dog,
    required TrainingProgram program,
    required TrainingProgress progress,
    required TrainingModule module,
    required String requesterRa,
    required String requesterName,
    bool directInstructor = false,
  }) async {
    final existing = await pendingRequestForModule(
      dogId: dog.id,
      modality: program.modality,
      moduleId: module.id,
      requesterRa: requesterRa,
    );
    if (existing != null) {
      throw StateError('Ja existe solicitacao pendente para este modulo.');
    }

    final docRef = _requests.doc();
    final entry = AuditService.buildInlineEntry(
      action: 'created',
      fieldName: 'promotion_request',
    );
    final marksSnapshot = _marksSnapshot(program, progress, module);
    await docRef.set({
      'dog_id': dog.id,
      'dog_name': dog.name,
      'modality': program.modality,
      'program_id': program.id,
      'program_version': program.version,
      'module_id': module.id,
      'module_name': module.name,
      'module_order': module.order,
      'status': 'pending',
      'direct_instructor': directInstructor,
      'requester_ra': requesterRa,
      'requester_name': requesterName,
      'requested_by_uid': _auth.currentUser?.uid,
      'requested_by_email': _auth.currentUser?.email?.trim().toLowerCase(),
      'requested_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'marks_snapshot': marksSnapshot,
      'audit_trail': [entry],
    });
    return docRef.id;
  }

  Future<void> decideRequest({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    final trimmedReason = reason?.trim();
    if (!approve && (trimmedReason == null || trimmedReason.isEmpty)) {
      throw ArgumentError('Informe o motivo da reprova.');
    }
    final entry = AuditService.buildInlineEntry(
      action: approve ? 'approved' : 'rejected',
      fieldName: 'promotion_request',
      reason: approve ? null : trimmedReason,
    );
    await _requests.doc(requestId).update({
      'status': approve ? 'approved' : 'rejected',
      'decision': approve ? 'approved' : 'rejected',
      'decision_by': HandlerIdentityService.raFromUser(_auth.currentUser),
      'decision_by_uid': _auth.currentUser?.uid,
      'decision_by_email': _auth.currentUser?.email,
      'decision_reason': approve ? null : trimmedReason,
      'decided_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });
  }

  Future<bool> currentUserIsInstructorK9({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(forceRefresh);
    final claims = token.claims ?? const <String, dynamic>{};
    if (_claimMarksInstructor(claims)) return true;

    final ra = HandlerIdentityService.raFromUser(user);
    if (ra == null) return false;
    final doc = await _firestore.collection('users').doc(ra).get();
    final data = doc.data() ?? const <String, dynamic>{};
    return data['is_k9_instructor'] == true ||
        data['training_role'] == 'instrutor_k9';
  }

  Future<bool> currentUserHasInstructorClaim({
    bool forceRefresh = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(forceRefresh);
    return _claimMarksInstructor(token.claims ?? const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> setK9InstructorRole({
    required String ra,
    required bool enabled,
  }) async {
    final callable = _functions.httpsCallable('setK9InstructorRole');
    final result = await callable.call<Map<String, dynamic>>({
      'ra': ra,
      'enabled': enabled,
    });
    final currentRa = HandlerIdentityService.raFromUser(_auth.currentUser);
    if (currentRa == ra) {
      await _auth.currentUser?.getIdToken(true);
    }
    return result.data;
  }

  List<Map<String, dynamic>> _marksSnapshot(
    TrainingProgram program,
    TrainingProgress progress,
    TrainingModule module,
  ) {
    final achievements = progress.achievementsForModule(module.id);
    return module.activeMilestones.map((milestone) {
      final achieved = achievements[milestone.id];
      return {
        'milestone_id': milestone.id,
        'order': milestone.order,
        'label': milestone.label,
        'required': milestone.isRequired,
        'achieved': achieved?.achieved == true,
        if (achieved?.achievedAt != null)
          'achieved_at': Timestamp.fromDate(achieved!.achievedAt!),
        if (achieved?.achievedBy != null) 'achieved_by': achieved!.achievedBy,
        'program_version': program.version,
      };
    }).toList();
  }

  bool _claimMarksInstructor(Map<String, dynamic> claims) {
    final roles = claims['roles'];
    return claims['role'] == 'instrutor_k9' ||
        claims['instrutor_k9'] == true ||
        claims['training_instructor'] == true ||
        claims['training_role'] == 'instrutor_k9' ||
        (roles is List && roles.contains('instrutor_k9'));
  }
}
