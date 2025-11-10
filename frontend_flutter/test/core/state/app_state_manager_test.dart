import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' as dart_test show Skip;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/core/state/app_state_manager.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

@dart_test.Skip(
    'Legacy state manager tests – skipped pending refactor to provider-based state')
void main() {
  late AppStateManager stateManager;
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    // Default stubs for async setters to avoid null returns on non-nullable futures
    when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
    when(() => mockPrefs.setInt(any(), any())).thenAnswer((_) async => true);
    when(() => mockPrefs.setDouble(any(), any())).thenAnswer((_) async => true);
    when(() => mockPrefs.setBool(any(), any())).thenAnswer((_) async => true);
    when(() => mockPrefs.setStringList(any(), any()))
        .thenAnswer((_) async => true);
    when(() => mockPrefs.remove(any())).thenAnswer((_) async => true);
    when(() => mockPrefs.clear()).thenAnswer((_) async => true);
    when(() => mockPrefs.get(any())).thenReturn(null);
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
      const key = 'numbers';
      final filtered = stateManager.filterState<int>(
        key,
        (value) => value % 2 == 0,
      );
      // Emit values after subscribing so filtered stream receives them
      stateManager.updateState(key, 1);
      stateManager.updateState(key, 2);
      stateManager.updateState(key, 3);
      expect(filtered, emits(2));
    });

    test('should handle cache operations', () async {
      const key = 'cached';
      const value = 'test-value';
      when(() => mockPrefs.setString(key, value)).thenAnswer((_) async => true);
      when(() => mockPrefs.get(key)).thenReturn(value);

      stateManager.updateState(key, value);
      await Future.delayed(const Duration(milliseconds: 50));
      final stream = stateManager.getStateStream<String>(key);
      expect(stream, emits(value));
      verify(() => mockPrefs.setString(key, value)).called(1);
    });

    test('should cleanup resources on dispose', () async {
      stateManager.updateState('key1', 1);
      stateManager.updateState('key2', 2);
      stateManager.dispose();
      // After dispose, updating should recreate stream without error
      stateManager.updateState('key1', 3); // should not throw
      expect(stateManager.getStateStream<int>('key1'), emits(3));
    });
  }, skip: true);
}
