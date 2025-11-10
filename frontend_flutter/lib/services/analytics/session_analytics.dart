import 'package:firebase_analytics/firebase_analytics.dart';

// NOTE: FirebaseAnalytics does not expose a public session start time; we manage it externally.
// This extension avoids referencing private state and expects callers to provide timing data.
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

  Future<void> logSessionDuration({required int durationSeconds}) async {
    await logEvent(
      name: 'session_duration',
      parameters: {
        'duration_seconds': durationSeconds,
      },
    );
  }
}
