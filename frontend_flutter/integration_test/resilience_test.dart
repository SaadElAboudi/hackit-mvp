import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
// TEMP DISABLED: package name mismatched; keeping reference commented to avoid analyzer errors.
// import 'package:hackit_mvp_flutter/main.dart' as app;
// import 'package:hackit_mvp_flutter/core/network/network_client.dart';
import 'package:dio/dio.dart';

class MockConnectivity extends Mock implements Connectivity {}

class MockNetworkClient extends Mock implements NetworkClient {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockConnectivity mockConnectivity;
  late MockNetworkClient mockNetworkClient;

  setUp(() {
    mockConnectivity = MockConnectivity();
    mockNetworkClient = MockNetworkClient();
  });

  group('Resilience Tests', () {
    testWidgets('handles network loss during search', (tester) async {
      await tester.runAsync(() async {
        // Setup mock to simulate network loss
        when(() => mockConnectivity.checkConnectivity())
            .thenAnswer((_) async => ConnectivityResult.none);

        // Initialize app
        app.main();
        await tester.pumpAndSettle();

        // Start search
        await tester.enterText(
          find.byType(TextField),
          'test query',
        );
        await tester.tap(find.byIcon(Icons.search));
        await tester.pump();

        // Verify error message
        expect(
          find.text('Vérifiez votre connexion internet'),
          findsOneWidget,
        );

        // Simulate network recovery
        when(() => mockConnectivity.checkConnectivity())
            .thenAnswer((_) async => ConnectivityResult.wifi);

        // Verify retry button
        expect(find.text('Réessayer'), findsOneWidget);
        await tester.tap(find.text('Réessayer'));
        await tester.pumpAndSettle();

        // Verify search continues
        expect(find.byType(VideoCard), findsWidgets);
      });
    });

    testWidgets('handles timeout gracefully', (tester) async {
      await tester.runAsync(() async {
        // Setup mock to simulate timeout
        when(() => mockNetworkClient.dio.post(any())).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.receiveTimeout,
        ));

        // Initialize app
        app.main();
        await tester.pumpAndSettle();

        // Start search
        await tester.enterText(
          find.byType(TextField),
          'test query',
        );
        await tester.tap(find.byIcon(Icons.search));
        await tester.pump();

        // Verify timeout message
        expect(
          find.text('La requête a pris trop de temps, veuillez réessayer'),
          findsOneWidget,
        );
      });
    });

    testWidgets('handles partial API response', (tester) async {
      await tester.runAsync(() async {
        // Setup mock to simulate partial response
        when(() => mockNetworkClient.dio.post(any()))
            .thenAnswer((_) async => Response(
                  requestOptions: RequestOptions(path: ''),
                  data: {'partial': true, 'videos': []},
                  statusCode: 206,
                ));

        // Initialize app
        app.main();
        await tester.pumpAndSettle();

        // Start search
        await tester.enterText(
          find.byType(TextField),
          'test query',
        );
        await tester.tap(find.byIcon(Icons.search));
        await tester.pump();

        // Verify partial results handling
        expect(
          find.text('Résultats partiels disponibles'),
          findsOneWidget,
        );
      });
    });

    testWidgets('handles app restart during search', (tester) async {
      await tester.runAsync(() async {
        // Initialize app
        app.main();
        await tester.pumpAndSettle();

        // Start search
        await tester.enterText(
          find.byType(TextField),
          'test query',
        );
        await tester.tap(find.byIcon(Icons.search));

        // Simulate app restart
        await app.main();
        await tester.pumpAndSettle();

        // Verify state recovery
        expect(
          find.byType(TextField),
          findsOneWidget,
        );
        expect(
          find.text('test query'),
          findsOneWidget,
        );
      });
    });

    testWidgets('handles low memory conditions', (tester) async {
      await tester.runAsync(() async {
        // Initialize app
        app.main();
        await tester.pumpAndSettle();

        // Simulate low memory condition
        await tester.binding.defaultBinaryMessenger
            .handlePlatformMessage('memory_pressure', null, null);

        // Verify app remains responsive
        await tester.enterText(
          find.byType(TextField),
          'test query',
        );
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();

        expect(find.byType(VideoCard), findsWidgets);
      });
    });
  });
}
