part of 'daily_timeline_screen.dart';

extension _DailyTimelineOperatorHelpers on _DailyTimelineScreenState {
  String _currentOperatorId() {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    return HandlerIdentityService.raFromUser(authVM.user) ?? '';
  }

  String _currentOperatorName(String currentRa) {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    return userVM.displayNameFor(ra: currentRa, firebaseUser: authVM.user);
  }

  IncidentProgressUpdate _authoredIncidentUpdate({
    required String title,
    required String description,
    required DateTime timestamp,
    String? location,
  }) {
    final currentRa = _currentOperatorId();
    return IncidentProgressUpdate(
      title: title,
      description: description,
      timestamp: timestamp,
      location: location,
      authorId: currentRa,
      authorName: _currentOperatorName(currentRa),
    );
  }
}
