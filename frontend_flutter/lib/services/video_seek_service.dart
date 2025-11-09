import 'dart:collection';
import 'dart:developer';

/// A lightweight singleton to coordinate timestamp seeking across widgets
/// without tightly coupling to a specific video player implementation.
///
/// Usage:
///   VideoSeekService.instance.register(seekCallback, baseUrl: currentVideoUrl);
///   VideoSeekService.instance.seekOrQueue(seconds);
///
/// If the player isn't registered yet, seeks are queued and flushed on first register.
class VideoSeekService {
  VideoSeekService._();
  static final VideoSeekService instance = VideoSeekService._();

  void Function(Duration)? _seekCallback;
  // Reserved for future validation of cross-video seeks.
  String? _baseUrl; // ignore: unused_field
  final Queue<int> _pending = Queue<int>();

  /// Register the active video player's seek handler.
  /// Any queued timestamps are flushed in FIFO order.
  void register(void Function(Duration d) seek, {required String baseUrl}) {
    _seekCallback = seek;
    _baseUrl = baseUrl;
    if (_pending.isNotEmpty) {
      while (_pending.isNotEmpty) {
        final s = _pending.removeFirst();
        try {
          seek(Duration(seconds: s));
        } catch (e, st) {
          log('VideoSeekService flush error: $e', stackTrace: st);
        }
      }
    }
  }

  /// Clear registration (e.g. when video screen disposed).
  void unregister() {
    _seekCallback = null;
    _baseUrl = null;
  }

  /// Seek immediately if player registered; otherwise queue.
  /// If [sourceUrl] provided and differs from current baseUrl, we still perform
  /// the seek (assuming same video) – future enhancement: validate ID extraction.
  void seekOrQueue(int seconds, {String? sourceUrl}) {
    if (seconds < 0) return; // ignore invalid
    final cb = _seekCallback;
    if (cb == null) {
      _pending.add(seconds);
      log('VideoSeekService queued seek @$seconds (player not ready)');
      return;
    }
    try {
      cb(Duration(seconds: seconds));
      log('VideoSeekService seek -> ${seconds}s');
    } catch (e, st) {
      log('VideoSeekService seek error: $e', stackTrace: st);
    }
  }

  bool get isRegistered => _seekCallback != null;
  int get pendingCount => _pending.length;
}
