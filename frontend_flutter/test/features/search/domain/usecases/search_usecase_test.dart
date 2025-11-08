import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hackit_mvp/features/search/domain/usecases/search_usecase.dart';
import 'package:hackit_mvp/core/error/failures.dart';
import 'package:hackit_mvp/shared/domain/models/video.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  late SearchUseCase searchUseCase;
  late MockSearchRepository mockSearchRepository;

  setUp(() {
    mockSearchRepository = MockSearchRepository();
    searchUseCase = SearchUseCase(mockSearchRepository);
  });

  group('execute', () {
    final testResult = SearchResult.fromJson(TestData.testSearchResult);

    test(
      'should return SearchResult when repository call is successful',
      () async {
        // arrange
        when(() => mockSearchRepository.search(TestData.testQuery))
            .thenAnswer((_) async => Right(testResult));

        // act
        final result = await searchUseCase.execute(TestData.testQuery);

        // assert
        expect(result, Right(testResult));
        verify(() => mockSearchRepository.search(TestData.testQuery)).called(1);
      },
    );

    test(
      'should return ValidationFailure when query is empty',
      () async {
        // act
        final result = await searchUseCase.execute('');

        // assert
        expect(
          result,
          const Left(ValidationFailure('La recherche ne peut pas être vide')),
        );
        verifyNever(() => mockSearchRepository.search(''));
      },
    );

    test(
      'should return ServerFailure when repository call fails',
      () async {
        // arrange
        when(() => mockSearchRepository.search(TestData.testQuery))
            .thenAnswer((_) async => const Left(
                  ServerFailure('Une erreur est survenue'),
                ));

        // act
        final result = await searchUseCase.execute(TestData.testQuery);

        // assert
        expect(
          result,
          const Left(ServerFailure('Une erreur est survenue')),
        );
        verify(() => mockSearchRepository.search(TestData.testQuery)).called(1);
      },
    );
  });
}