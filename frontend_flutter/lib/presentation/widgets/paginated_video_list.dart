import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/search_bloc.dart';
import '../models/video_model.dart';
import 'video_card.dart';

class PaginatedVideoList extends StatefulWidget {
  final List<VideoModel> videos;
  final bool hasReachedEnd;
  final Function() onLoadMore;

  const PaginatedVideoList({
    super.key,
    required this.videos,
    required this.hasReachedEnd,
    required this.onLoadMore,
  });

  @override
  _PaginatedVideoListState createState() => _PaginatedVideoListState();
}

class _PaginatedVideoListState extends State<PaginatedVideoList> {
  final _scrollController = ScrollController();
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
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.videos.length + (widget.hasReachedEnd ? 0 : 1),
      itemBuilder: (context, index) {
        if (index < widget.videos.length) {
          return VideoCard(video: widget.videos[index]);
        } else {
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
      },
    );
  }
}