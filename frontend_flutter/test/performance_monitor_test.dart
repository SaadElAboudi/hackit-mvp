import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/services/performance_monitor.dart';

void main() {
  late PerformanceMonitor monitor;

  setUp(() {
    monitor = PerformanceMonitor();
    monitor.clearMetrics();
  });

  group('PerformanceMonitor Tests', () {
    test('Records operation duration correctly', () {
      monitor.startOperation('test_op');
      Future.delayed(const Duration(milliseconds: 100));
      monitor.stopOperation('test_op');

      final metrics = monitor.getAverageMetrics();
      expect(metrics['test_op'], isNotNull);
      expect(metrics['test_op']!, greaterThan(0));
    });

    test('Calculates average correctly for multiple operations', () {
      for (var i = 0; i < 3; i++) {
        monitor.startOperation('multi_op');
        Future.delayed(const Duration(milliseconds: 50));
        monitor.stopOperation('multi_op');
      }

      final metrics = monitor.getAverageMetrics();
      expect(metrics['multi_op'], isNotNull);
    });

    test('Generates readable report', () {
      monitor.startOperation('op1');
      monitor.stopOperation('op1');
      monitor.startOperation('op2');
      monitor.stopOperation('op2');

      final report = monitor.generateReport();
      expect(report, contains('Performance Report:'));
      expect(report, contains('op1:'));
      expect(report, contains('op2:'));
    });

    test('Clears metrics correctly', () {
      monitor.startOperation('test_clear');
      monitor.stopOperation('test_clear');
      monitor.clearMetrics();

      final metrics = monitor.getAverageMetrics();
      expect(metrics.isEmpty, true);
    });
  });
}