import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:hackit_mvp_flutter/features/search/domain/repository/search_repository.dart';
import 'package:hackit_mvp_flutter/features/search/domain/usecases/search_usecase.dart';
import 'package:hackit_mvp_flutter/features/search/presentation/bloc/search_bloc.dart';
import 'package:hackit_mvp_flutter/core/network/network_client.dart';

// Mocks
class MockSearchRepository extends Mock implements SearchRepository {}
class MockSearchUseCase extends Mock implements SearchUseCase {}
class MockNetworkClient extends Mock implements NetworkClient {}

// Test Data Generator
class TestData {
  static const testQuery = "comment déboucher un évier";
  
  static final testVideo = {
    'id': 'test123',
    'title': 'Comment déboucher un évier - Guide complet',
    'description': 'Un guide étape par étape pour déboucher votre évier',
    'thumbnailUrl': 'https://example.com/thumbnail.jpg',
    'videoUrl': 'https://youtube.com/watch?v=test123',
    'channelTitle': 'BricolageExpert',
    'publishedAt': '2025-11-04T10:00:00Z',
    'viewCount': 1000,
    'likeCount': 100
  };

  static final testSearchResult = {
    'query': testQuery,
    'videos': [testVideo],
    'steps': [
      'Étape 1: Utiliser une ventouse',
      'Étape 2: Verser du bicarbonate',
      'Étape 3: Ajouter du vinaigre',
      'Étape 4: Rincer à l\'eau chaude',
      'Étape 5: Vérifier le résultat'
    ],
    'summary': 'Guide de débouchage d\'évier en 5 étapes simples'
  };
}

extension PumpApp on WidgetTester {
  Future<void> pumpTestApp(Widget widget) async {
    await pumpWidget(
      MaterialApp(
        home: widget,
      ),
    );
    await pump();
  }
}