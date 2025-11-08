import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/core/state/app_state_manager.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late AppStateManager stateManager;
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    stateManager = AppStateManager(mockPrefs);
  });

  group('AppStateManager', () {
    test('should create and update state stream', () async {
      // Arrange
      const testKey = 'test';
      const testValue = 42;

      // Act
      stateManager.updateState(testKey, testValue);

      // Assert
      expect(
        stateManager.getStateStream<int>(testKey),
        emits(testValue),
      );
    });

    test('should combine multiple states', () async {
      // Arrange
      stateManager.updateState('key1', 1);
      stateManager.updateState('key2', 2);

      // Act
      final combined = stateManager.combineStates<String>(
        keys: ['key1', 'key2'],
        combiner: (values) => '${values[0]}-${values[1]}',
      );

      // Assert
      expect(combined, emits('1-2'));
    });

    test('should create derived state', () async {
      // Arrange
      const sourceKey = 'source';
      stateManager.updateState(sourceKey, 10);

      // Act
      final derived = stateManager.createDerivedState<int, bool>(
        sourceKey: sourceKey,
        derivation: (value) => value > 5,
      );

      // Assert
      expect(derived, emits(true));
    });

    test('should filter state', () async {
      // Arrange
      const key = 'numbers';
      stateManager.updateState(key, 1);
      stateManager.updateState(key, 2);
      stateManager.updateState(key, 3);

      // Act
      final filtered = stateManager.filterState<int>(
        key,
        (value) => value % 2 == 0,
      );

      // Assert
      expect(filtered, emits(2));
    });

    test('should handle cache operations', () async {
      // Arrange
      const key = 'cached';
      const value = 'test-value';
      when(() => mockPrefs.setString(key, value))
          .thenAnswer((_) => Future.value(true));
      when(() => mockPrefs.getString(key)).thenReturn(value);

      // Act
      stateManager.updateState(key, value);
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert
      verify(() => mockPrefs.setString(key, value)).called(1);
    });

    test('should cleanup resources on dispose', () async {
      // Arrange
      stateManager.updateState('key1', 1);
      stateManager.updateState('key2', 2);

      // Act
      stateManager.dispose();

      // Assert
      // Verify streams are closed by trying to add new values
      expect(
        () => stateManager.updateState('key1', 3),
        throwsA(anything),
      );
    });
  });
}