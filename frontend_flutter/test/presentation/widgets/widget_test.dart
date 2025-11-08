import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mockito/mockito.dart';
import 'package:hackit_mvp/presentation/screens/home_screen.dart';
import 'package:hackit_mvp/presentation/widgets/video_card.dart';
import 'package:hackit_mvp/presentation/widgets/chat_input.dart';
import 'package:hackit_mvp/presentation/blocs/search_bloc.dart';
import 'package:hackit_mvp/domain/repositories/video_repository.dart';

class MockSearchBloc extends MockBloc<SearchEvent, SearchState> 
    implements SearchBloc {}

class MockVideoRepository extends Mock implements VideoRepository {}

void main() {
  late MockSearchBloc mockSearchBloc;
  late MockVideoRepository mockRepository;

  setUp(() {
    mockSearchBloc = MockSearchBloc();
    mockRepository = MockVideoRepository();
  });

  group('HomeScreen', () {
    testWidgets('should show loading indicator when searching', 
        (WidgetTester tester) async {
      // arrange
      when(mockSearchBloc.state).thenReturn(SearchLoading());

      // act
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SearchBloc>.value(
            value: mockSearchBloc,
            child: HomeScreen(),
          ),
        ),
      );

      // assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should show error message when search fails', 
        (WidgetTester tester) async {
      // arrange
      when(mockSearchBloc.state)
          .thenReturn(SearchError('Une erreur est survenue'));

      // act
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SearchBloc>.value(
            value: mockSearchBloc,
            child: HomeScreen(),
          ),
        ),
      );

      // assert
      expect(find.text('Une erreur est survenue'), findsOneWidget);
    });

    testWidgets('should show video cards when search succeeds', 
        (WidgetTester tester) async {
      // arrange
      final testVideos = [
        VideoModel(
          id: '1',
          title: 'Test Video',
          description: 'Test Description',
          thumbnailUrl: 'https://example.com/thumb.jpg',
          channelTitle: 'Test Channel',
          publishedAt: DateTime.now(),
        ),
      ];
      
      when(mockSearchBloc.state).thenReturn(SearchLoaded(testVideos));

      // act
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SearchBloc>.value(
            value: mockSearchBloc,
            child: HomeScreen(),
          ),
        ),
      );

      // assert
      expect(find.byType(VideoCard), findsNWidgets(testVideos.length));
    });
  });

  group('ChatInput', () {
    testWidgets('should trigger search when submitted', 
        (WidgetTester tester) async {
      // arrange
      const testQuery = 'test query';

      // act
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SearchBloc>.value(
            value: mockSearchBloc,
            child: ChatInput(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), testQuery);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // assert
      verify(mockSearchBloc.add(SearchVideos(testQuery))).called(1);
    });
  });

  group('VideoCard', () {
    testWidgets('should display video information correctly', 
        (WidgetTester tester) async {
      // arrange
      final testVideo = VideoModel(
        id: '1',
        title: 'Test Video',
        description: 'Test Description',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        channelTitle: 'Test Channel',
        publishedAt: DateTime.now(),
      );

      // act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoCard(video: testVideo),
          ),
        ),
      );

      // assert
      expect(find.text('Test Video'), findsOneWidget);
      expect(find.text('Test Channel'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('should handle tap events', (WidgetTester tester) async {
      // arrange
      final testVideo = VideoModel(
        id: '1',
        title: 'Test Video',
        description: 'Test Description',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        channelTitle: 'Test Channel',
        publishedAt: DateTime.now(),
      );
      bool tapped = false;

      // act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoCard(
              video: testVideo,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(VideoCard));
      await tester.pump();

      // assert
      expect(tapped, true);
    });
  });
}