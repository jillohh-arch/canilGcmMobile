import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'handler_identity_service.dart';

class OperatorContext {
  final String ra;
  final String name;

  const OperatorContext({required this.ra, required this.name});
}

class OperatorContextService {
  const OperatorContextService();

  OperatorContext fromViewModels({
    required AuthViewModel authVM,
    required UserViewModel userVM,
  }) {
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
    return OperatorContext(
      ra: currentRa,
      name: userVM.displayNameFor(ra: currentRa, firebaseUser: authVM.user),
    );
  }
}
