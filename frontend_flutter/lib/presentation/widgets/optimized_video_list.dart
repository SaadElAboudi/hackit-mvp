import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/video_model.dart';
import 'optimized_image.dart';

class OptimizedVideoList extends StatefulWidget {
  final List<VideoModel> videos;
  final Function(VideoModel) onVideoTap;
  final bool hasReachedEnd;
  final Function() onLoadMore;

  const OptimizedVideoList({
    super.key,
    required this.videos,
    required this.onVideoTap,
    required this.hasReachedEnd,
    required this.onLoadMore,
  });

  @override
  _OptimizedVideoListState createState() => _OptimizedVideoListState();
}

class _OptimizedVideoListState extends State<OptimizedVideoList> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoadingMore && 
        _scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!widget.hasReachedEnd) {
      setState(() {
        _isLoadingMore = true;
      });

      await widget.onLoadMore();

      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.custom(
      controller: _scrollController,
      childrenDelegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          if (index < widget.videos.length) {
            return RepaintBoundary(
              child: OptimizedVideoCard(
                video: widget.videos[index],
                onTap: () => widget.onVideoTap(widget.videos[index]),
              ),
            );
          } else if (!widget.hasReachedEnd) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }
          return null;
        },
        childCount: widget.videos.length + (widget.hasReachedEnd ? 0 : 1),
        findChildIndexCallback: (Key key) {
          if (key is ValueKey<String>) {
            final index = widget.videos
                .indexWhere((video) => video.id == key.value);
            return index != -1 ? index : null;
          }
          return null;
        },
      ),
      cacheExtent: 800.0, // Cache plus d'éléments pour un défilement plus fluide
    );
  }
}

class OptimizedVideoCard extends StatelessWidget {
  final VideoModel video;
  final VoidCallback onTap;

  const OptimizedVideoCard({
    super.key,
    required this.video,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey<String>(video.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: OptimizedImage(
                imageUrl: video.thumbnailUrl,
                width: double.infinity,
                height: 200,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    video.channelTitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}