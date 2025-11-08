import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../shared/domain/models/video.dart';
import '../../../../core/error/failures.dart';

part 'search_state.freezed.dart';

@freezed
class SearchState with _$SearchState {
  const factory SearchState.initial() = _Initial;
  const factory SearchState.loading() = _Loading;
  const factory SearchState.success(SearchResult result) = _Success;
  const factory SearchState.error(Failure failure) = _Error;
}