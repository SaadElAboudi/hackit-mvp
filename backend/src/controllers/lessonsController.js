import {
  createLessonForUser,
  deleteLessonForUser,
  listLessonsForUser,
  recordLessonViewForUser,
  setFavoriteForUser,
} from '../services/lessonsService.js';

function shapeLesson(lesson) {
  return {
    id: lesson._id?.toString?.() ?? lesson.id ?? '',
    userId: lesson.userId?.toString?.() ?? '',
    title: lesson.title?.toString?.() ?? '',
    summary: lesson.summary?.toString?.() ?? '',
    steps: Array.isArray(lesson.steps) ? lesson.steps.map((s) => s?.toString?.() ?? '') : [],
    videoUrl: lesson.videoUrl?.toString?.() ?? '',
    favorite: Boolean(lesson.favorite),
    views: typeof lesson.views === 'number' ? lesson.views : 0,
    createdAt: lesson.createdAt?.toISOString?.() ?? new Date().toISOString(),
    updatedAt: lesson.updatedAt?.toISOString?.() ?? new Date().toISOString(),
  };
}

export async function createLesson(req, res) {
  try {
    const { title, steps, videoUrl, summary } = req.body || {};
    const userId = req.userId;

    if (!userId || typeof userId !== 'string' || userId.length < 3 || userId.length > 128) {
      return res.status(400).json({ error: 'Invalid userId' });
    }

    const isAnon = userId.startsWith('anon_');
    const isNumeric = /^[0-9]+$/.test(userId);
    const isAlphaNum = /^[a-zA-Z0-9_-]+$/.test(userId);
    if (!(isAnon || isNumeric || isAlphaNum)) {
      return res.status(400).json({ error: 'userId must be anon_, numeric, or alphanum' });
    }

    if (!title || typeof title !== 'string' || title.length < 2 || title.length > 120) {
      return res.status(400).json({ error: 'Title must be 2-120 chars' });
    }

    if (!videoUrl || typeof videoUrl !== 'string' || !/^https?:\/\/.{8,}/.test(videoUrl)) {
      return res.status(400).json({ error: 'Invalid videoUrl' });
    }

    if (!Array.isArray(steps) || steps.length === 0 || steps.length > 20 || !steps.every((s) => typeof s === 'string' && s.length > 1 && s.length < 200)) {
      return res.status(400).json({ error: 'steps[] must be 1-20 non-empty strings, each 2-200 chars' });
    }

    const lesson = await createLessonForUser({ userId, title, steps, videoUrl, summary });
    return res.json(shapeLesson(lesson));
  } catch (e) {
    return res.status(500).json({ error: 'Failed to save lesson', detail: 'Internal error' });
  }
}

export async function deleteLesson(req, res) {
  const id = String(req.params.id || '').trim();
  if (!id) return res.status(400).json({ error: 'id is required' });

  try {
    const result = await deleteLessonForUser({ lessonId: id, userId: req.userId });
    if (result.invalidId) return res.status(400).json({ error: 'Invalid lesson id' });
    if (result.deletedCount === 0) return res.status(404).json({ error: 'Lesson not found' });

    return res.json({ deleted: true, id });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to delete lesson', detail: e?.message || 'Unknown error' });
  }
}

export async function setFavorite(req, res) {
  const id = String(req.params.id || '').trim();
  const favorite = !!req.body?.favorite;
  if (!id) return res.status(400).json({ error: 'id is required' });

  try {
    const updated = await setFavoriteForUser({ lessonId: id, userId: req.userId, favorite });
    if (!updated) return res.status(404).json({ error: 'Not found' });
    return res.json({ ok: true, lesson: shapeLesson(updated) });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to update favorite', detail: e?.message || 'Unknown error' });
  }
}

export async function recordView(req, res) {
  const id = String(req.params.id || '').trim();
  if (!id) return res.status(400).json({ error: 'id is required' });

  try {
    const updated = await recordLessonViewForUser({ lessonId: id, userId: req.userId });
    if (!updated) return res.status(404).json({ error: 'Not found' });
    return res.json(shapeLesson(updated));
  } catch (e) {
    return res.status(500).json({ error: 'Failed to record view', detail: e?.message || 'Unknown error' });
  }
}

export async function listLessons(req, res) {
  const userId = req.userId;
  if (!userId) return res.status(400).json({ error: 'userId is required' });

  const favorite = req.query.favorite === undefined ? undefined : String(req.query.favorite).toLowerCase() === 'true';
  const sortBy = ['createdAt', 'lastViewedAt', 'views'].includes(String(req.query.sort || '')) ? String(req.query.sort) : 'createdAt';
  const order = String(req.query.order || 'desc').toLowerCase() === 'asc' ? 1 : -1;
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit || '50'), 10)));
  const offset = Math.max(0, parseInt(String(req.query.offset || '0'), 10));

  try {
    const items = await listLessonsForUser({ userId, favorite, sortBy, order, limit, offset });
    const shapedItems = items.map((lesson) => ({
      ...shapeLesson(lesson),
      progress: lesson.progress || 0,
      reminder: lesson.reminder || null,
      guestPrompt: (!req.isAuthenticated?.() && !req.user)
        ? 'Save progress or unlock premium features by signing in.'
        : undefined,
    }));

    const suggestedActions = shapedItems.length === 0 ? [
      { label: 'Search for a lesson', action: '/api/search' },
      { label: 'Request help', action: '/support' },
    ] : undefined;

    return res.json({ items: shapedItems, total: shapedItems.length, suggestedActions });
  } catch (e) {
    return res.status(500).json({
      error: 'Failed to list lessons', detail: e?.message || 'Unknown error', suggestedActions: [
        { label: 'Retry', action: '/api/lessons' },
        { label: 'Request help', action: '/support' },
      ],
    });
  }
}
