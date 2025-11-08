@Skip('Legacy bloc tests – chat architecture uses Provider; tests disabled.')
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hackit_mvp/features/search/presentation/bloc/search_bloc.dart';
import 'package:hackit_mvp/features/search/presentation/bloc/search_state.dart';
import 'package:hackit_mvp/core/error/failures.dart';
import 'package:hackit_mvp/shared/domain/models/video.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late SearchBloc searchBloc;
  late MockSearchUseCase mockSearchUseCase;

  setUp(() {
    mockSearchUseCase = MockSearchUseCase();
    searchBloc = SearchBloc(mockSearchUseCase);
  });

  tearDown(() {
    searchBloc.close();
  });

  test('initial state should be SearchState.initial', () {
    expect(searchBloc.state, const SearchState.initial());
  });

  group('search', () {
    final testResult = SearchResult.fromJson(TestData.testSearchResult);

    blocTest<SearchBloc, SearchState>(
      'emits [loading, success] when search is successful',
      build: () {
        when(() => mockSearchUseCase.execute(TestData.testQuery))
            .thenAnswer((_) async => Right(testResult));
        return searchBloc;
      },
      act: (bloc) => bloc.search(TestData.testQuery),
      expect: () => [
        const SearchState.loading(),
        SearchState.success(testResult),
      ],
      verify: (_) {
        verify(() => mockSearchUseCase.execute(TestData.testQuery)).called(1);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'emits [loading, error] when search fails',
      build: () {
        when(() => mockSearchUseCase.execute(TestData.testQuery))
            .thenAnswer((_) async => const Left(
                  ServerFailure('Une erreur est survenue'),
                ));
        return searchBloc;
      },
      act: (bloc) => bloc.search(TestData.testQuery),
      expect: () => [
        const SearchState.loading(),
        const SearchState.error(
          ServerFailure('Une erreur est survenue'),
        ),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'emits [loading, error] when query is empty',
      build: () => searchBloc,
      act: (bloc) => bloc.search(''),
      expect: () => [
        const SearchState.loading(),
        const SearchState.error(
          ValidationFailure('La recherche ne peut pas être vide'),
        ),
      ],
      verify: (_) {
        verifyNever(() => mockSearchUseCase.execute(''));
      },
    );
  });

  group('reset', () {
    blocTest<SearchBloc, SearchState>(
      'emits [initial] when reset is called',
      build: () => searchBloc,
      act: (bloc) => bloc.reset(),
      expect: () => [const SearchState.initial()],
    );
  });
}
