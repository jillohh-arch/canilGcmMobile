import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has completed the onboarding flow.
/// Uses SharedPreferences for persistence across app restarts.
class OnboardingService {
  static const String _key = 'has_seen_onboarding';

  /// Returns true if the user has already seen the onboarding screens.
  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Marks onboarding as completed so it won't show again.
  Future<void> markOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Resets the onboarding flag (useful for testing/debugging).
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
