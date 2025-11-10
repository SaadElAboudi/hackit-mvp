import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';

class LessonView extends StatelessWidget {
  final String title;
  final List<String> steps;
  final String videoUrl;
  const LessonView(
      {super.key,
      required this.title,
      required this.steps,
      required this.videoUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SummaryView(title: title, steps: steps),
        SizedBox(height: AdaptiveSpacing.medium),
        VideoCard(title: title, videoUrl: videoUrl),
      ],
    );
  }
}
