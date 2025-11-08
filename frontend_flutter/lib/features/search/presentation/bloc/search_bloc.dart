import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/search_usecase.dart';
import 'search_state.dart';

@injectable
class SearchBloc extends Cubit<SearchState> {
  final SearchUseCase _searchUseCase;

  SearchBloc(this._searchUseCase) : super(const SearchState.initial());

  Future<void> search(String query) async {
    emit(const SearchState.loading());

    final result = await _searchUseCase.execute(query);
    
    emit(result.fold(
      (failure) => SearchState.error(failure),
      (searchResult) => SearchState.success(searchResult),
    ));
  }

  void reset() {
    emit(const SearchState.initial());
  }
}