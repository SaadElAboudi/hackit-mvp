import 'package:dartz/dartz.dart';
import '../models/video_model.dart';
import '../models/search_result.dart';
import '../core/failure.dart';

abstract class VideoRepository {
  /// Recherche des vidéos avec une requête donnée
  Future<Either<Failure, List<VideoModel>>> searchVideos(String query);

  /// Récupère les détails d'une vidéo par son ID
  Future<Either<Failure, VideoModel>> getVideoById(String id);

  /// Récupère plusieurs vidéos par leurs IDs
  Future<Either<Failure, List<VideoModel>>> getVideosByIds(List<String> ids);

  /// Récupère l'historique des recherches
  Future<Either<Failure, List<SearchResult>>> getSearchHistory();

  /// Efface l'historique des recherches
  Future<Either<Failure, void>> clearSearchHistory();
}