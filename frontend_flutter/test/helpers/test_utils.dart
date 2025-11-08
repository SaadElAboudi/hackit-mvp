import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Mock Classes
class MockSharedPreferences extends Mock implements SharedPreferences {}
class MockConnectivity extends Mock implements Connectivity {}
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// Test Data
class TestData {
  static const testVideoId = "test_video_id";
  static const testVideoTitle = "Test Video Title";
  static const testVideoDescription = "Test video description";
  static const testThumbnailUrl = "https://example.com/thumbnail.jpg";
  static const testChannelId = "test_channel_id";
  static const testChannelTitle = "Test Channel";
  
  static const testSearchQuery = "flutter tutorial";
  static const testErrorMessage = "Test error message";
}

// Widget Test Helpers
extension WidgetTesterExtension on WidgetTester {
  Future<void> pumpApp(Widget widget) async {
    await pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: widget,
        ),
      ),
    );
    await pump();
  }

  Future<void> pumpThemedApp(Widget widget, {ThemeData? theme}) async {
    await pumpWidget(
      MaterialApp(
        theme: theme ?? ThemeData.light(),
        home: Scaffold(
          body: widget,
        ),
      ),
    );
    await pump();
  }
}

// Common Test Utilities
class TestUtils {
  static void setupConnectivityMock(MockConnectivity mockConnectivity,
      {ConnectivityResult result = ConnectivityResult.wifi}) {
    when(() => mockConnectivity.checkConnectivity())
        .thenAnswer((_) async => result);
    when(() => mockConnectivity.onConnectivityChanged)
        .thenAnswer((_) => Stream.value(result));
  }

  static void setupSharedPreferencesMock(
      MockSharedPreferences mockPrefs, Map<String, dynamic> values) {
    for (var entry in values.entries) {
      if (entry.value is String) {
        when(() => mockPrefs.getString(entry.key))
            .thenReturn(entry.value as String);
      } else if (entry.value is bool) {
        when(() => mockPrefs.getBool(entry.key))
            .thenReturn(entry.value as bool);
      } else if (entry.value is int) {
        when(() => mockPrefs.getInt(entry.key))
            .thenReturn(entry.value as int);
      } else if (entry.value is double) {
        when(() => mockPrefs.getDouble(entry.key))
            .thenReturn(entry.value as double);
      } else if (entry.value is List<String>) {
        when(() => mockPrefs.getStringList(entry.key))
            .thenReturn(entry.value as List<String>);
      }
    }
  }

  static void setupSecureStorageMock(
      MockFlutterSecureStorage mockStorage, Map<String, String> values) {
    for (var entry in values.entries) {
      when(() => mockStorage.read(key: entry.key))
          .thenAnswer((_) async => entry.value);
    }
  }
}