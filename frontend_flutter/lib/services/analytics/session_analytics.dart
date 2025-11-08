import 'package:firebase_analytics/firebase_analytics.dart';

extension SessionAnalytics on FirebaseAnalytics {
  Future<void> logSessionStart() async {
    await logEvent(
      name: 'session_start',
      parameters: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    await logEvent(
      name: 'screen_view',
      parameters: {
        'screen_name': screenName,
        'screen_class': screenClass ?? '',
      },
    );
  }

  Future<void> logSessionDuration() async {
    await logEvent(
      name: 'session_duration',
      parameters: {
        'duration_seconds': DateTime.now().difference(_sessionStartTime).inSeconds,
      },
    );
  }
}