import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/repositories/video_repository.dart';
import '../../data/models/video_model.dart';
import '../../data/models/search_result.dart';
import '../../data/models/pagination_data.dart';

// Events
abstract class SearchEvent {}

class SearchVideos extends SearchEvent {
  final String query;
  SearchVideos(this.query);
}

class LoadMoreVideos extends SearchEvent {
  final String query;
  final String pageToken;
  LoadMoreVideos(this.query, this.pageToken);
}

// States
abstract class SearchState {}

class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {}

class SearchLoaded extends SearchState {
  final List<VideoModel> videos;
  final PaginationData pagination;
  final String query;

  SearchLoaded({
    required this.videos,
    required this.pagination,
    required this.query,
  });

  SearchLoaded copyWith({
    List<VideoModel>? videos,
    PaginationData? pagination,
    String? query,
  }) {
    return SearchLoaded(
      videos: videos ?? this.videos,
      pagination: pagination ?? this.pagination,
      query: query ?? this.query,
    );
  }
}

class SearchLoadingMore extends SearchState {
  final List<VideoModel> currentVideos;
  final PaginationData pagination;
  final String query;

  SearchLoadingMore({
    required this.currentVideos,
    required this.pagination,
    required this.query,
  });
}

class SearchError extends SearchState {
  final String message;
  SearchError(this.message);
}

@injectable
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final VideoRepository _repository;

  SearchBloc(this._repository) : super(SearchInitial()) {
    on<SearchVideos>(_onSearchVideos);
    on<LoadMoreVideos>(_onLoadMoreVideos);
  }

  Future<void> _onSearchVideos(
    SearchVideos event,
    Emitter<SearchState> emit,
  ) async {
    emit(SearchLoading());

    final result = await _repository.searchVideos(event.query);

    result.fold(
      (failure) => emit(SearchError(_mapFailureToMessage(failure))),
      (searchResult) => emit(SearchLoaded(
        videos: searchResult.videos,
        pagination: searchResult.pagination,
        query: event.query,
      )),
    );
  }

  Future<void> _onLoadMoreVideos(
    LoadMoreVideos event,
    Emitter<SearchState> emit,
  ) async {
    final currentState = state;
    if (currentState is SearchLoaded) {
      emit(SearchLoadingMore(
        currentVideos: currentState.videos,
        pagination: currentState.pagination,
        query: currentState.query,
      ));

      final result = await _repository.searchVideos(
        event.query,
        pageToken: event.pageToken,
      );

      result.fold(
        (failure) => emit(SearchError(_mapFailureToMessage(failure))),
        (searchResult) => emit(SearchLoaded(
          videos: [...currentState.videos, ...searchResult.videos],
          pagination: searchResult.pagination,
          query: event.query,
        )),
      );
    }
  }

  String _mapFailureToMessage(Failure failure) {
    switch (failure.runtimeType) {
      case NetworkFailure:
        return 'Erreur de connexion. Vérifiez votre connexion internet.';
      case ServerFailure:
        return 'Erreur serveur. Veuillez réessayer plus tard.';
      default:
        return 'Une erreur inattendue s\'est produite.';
    }
  }
}