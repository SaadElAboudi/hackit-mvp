
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final Map<String, Stopwatch> _watches = {};
  final Map<String, List<int>> _metrics = {};

  void startOperation(String name) {
    _watches[name] = Stopwatch()..start();
  }

  void stopOperation(String name) {
    final watch = _watches[name];
    if (watch == null) return;

    watch.stop();
    final duration = watch.elapsedMilliseconds;
    _watches.remove(name);

    _metrics.putIfAbsent(name, () => []).add(duration);
  }

  Map<String, double> getAverageMetrics() {
    return Map.fromEntries(
      _metrics.entries.map((e) {
        final avg = e.value.reduce((a, b) => a + b) / e.value.length;
        return MapEntry(e.key, avg);
      }),
    );
  }

  void clearMetrics() {
    _metrics.clear();
    _watches.clear();
  }

  String generateReport() {
    final buffer = StringBuffer();
    buffer.writeln('Performance Report:');
    buffer.writeln('-' * 40);

    final metrics = getAverageMetrics();
    metrics.forEach((key, value) {
      buffer.writeln('$key: ${value.toStringAsFixed(2)}ms');
    });

    return buffer.toString();
  }
}