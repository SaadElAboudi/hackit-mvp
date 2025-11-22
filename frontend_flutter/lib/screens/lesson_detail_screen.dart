import 'package:flutter/material.dart';

import '../models/lesson.dart';
import 'package:provider/provider.dart';
import '../providers/lessons_provider.dart';
import '../widgets/lesson_view.dart';

class LessonDetailScreen extends StatelessWidget {
  final Lesson lesson;
  const LessonDetailScreen({super.key, required this.lesson});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 3,
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_rounded,
                  color: Color(0xFF00C48C), size: 28),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Color(0xFF222B45),
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Color(0x22000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 38,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Color(0xFF00C48C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                lesson.favorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: lesson.favorite ? Colors.amber : Color(0xFF8F9BB3),
                size: 28,
              ),
              tooltip: lesson.favorite
                  ? 'Retirer des favoris'
                  : 'Ajouter aux favoris',
              onPressed: () async {
                await Provider.of<LessonsProvider>(context, listen: false)
                    .toggleFavorite(lesson.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(lesson.favorite
                        ? 'Retiré des favoris'
                        : 'Ajouté aux favoris'),
                    backgroundColor:
                        lesson.favorite ? Colors.red : Colors.green,
                  ),
                );
              },
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete, color: Color(0xFFEB5757), size: 28),
              tooltip: 'Supprimer',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Supprimer la leçon'),
                    content: const Text(
                        'Voulez-vous vraiment supprimer cette leçon ?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Supprimer',
                            style: TextStyle(color: Color(0xFFEB5757))),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await Provider.of<LessonsProvider>(context, listen: false)
                      .deleteLesson(lesson.id);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Leçon supprimée'),
                        backgroundColor: Colors.green),
                  );
                }
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Card(
            elevation: 8,
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lesson.videoUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18.0),
                      child: Row(
                        children: [
                          const Icon(Icons.play_circle_fill,
                              color: Colors.blueAccent, size: 22),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Vidéo : ${lesson.videoUrl}',
                              style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  LessonView(
                    title: lesson.title,
                    steps: lesson.steps,
                    videoUrl: lesson.videoUrl,
                    transcript:
                        lesson.summary.isNotEmpty ? [lesson.summary] : null,
                    chapters: lesson.steps.isNotEmpty ? lesson.steps : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
