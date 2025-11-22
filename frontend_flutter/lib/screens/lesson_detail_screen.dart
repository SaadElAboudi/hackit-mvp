import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../widgets/lesson_view.dart';

class LessonDetailScreen extends StatelessWidget {
  final Lesson lesson;
  const LessonDetailScreen({super.key, required this.lesson});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(lesson.title),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: LessonView(
                title: lesson.title,
                steps: lesson.steps,
                videoUrl: lesson.videoUrl,
                transcript: lesson.summary.isNotEmpty ? [lesson.summary] : null,
                chapters: lesson.steps.isNotEmpty ? lesson.steps : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
