import 'package:firebase_analytics/firebase_analytics.dart';

extension PerformanceAnalytics on FirebaseAnalytics {
  Future<void> logApiLatency({
    required String endpoint,
    required double latencyMs,
    bool isSuccess = true,
    String? errorMessage,
  }) async {
    await logEvent(
      name: 'api_latency',
      parameters: {
        'endpoint': endpoint,
        'latency_ms': latencyMs,
        'success': isSuccess,
        'error_message': errorMessage ?? '',
      },
    );
  }

  Future<void> logAppStartup({
    required double coldStartMs,
    required bool isColdStart,
  }) async {
    await logEvent(
      name: 'app_startup',
      parameters: {
        'duration_ms': coldStartMs,
        'is_cold_start': isColdStart,
      },
    );
  }

  Future<void> logMemoryUsage({
    required int memoryMb,
    required String screen,
  }) async {
    await logEvent(
      name: 'memory_usage',
      parameters: {
        'memory_mb': memoryMb,
        'screen': screen,
      },
    );
  }

  Future<void> logFrameDrop({
    required String screen,
    required int droppedFrames,
    required double duration,
  }) async {
    await logEvent(
      name: 'frame_drop',
      parameters: {
        'screen': screen,
        'dropped_frames': droppedFrames,
        'duration_ms': duration,
      },
    );
  }
}