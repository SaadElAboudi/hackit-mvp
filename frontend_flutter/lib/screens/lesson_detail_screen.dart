import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../widgets/lesson_view.dart';

class LessonDetailScreen extends StatelessWidget {
  final Lesson lesson;
  const LessonDetailScreen({super.key, required this.lesson});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: LessonView(
            title: lesson.title,
            steps: lesson.steps,
            videoUrl: lesson.videoUrl,
          ),
        ),
      ),
    );
  }
}
