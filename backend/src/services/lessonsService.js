import mongoose from 'mongoose';
import crypto from 'crypto';

import Lesson from '../models/lesson.js';
import User from '../models/User.js';

function isValidObjectId(id) {
  return mongoose.Types.ObjectId.isValid(id);
}

// ---------------------------------------------------------------------------
// In-memory mock store: used when MOCK_MODE=true or MongoDB is not connected.
// Keyed by lesson id. Not persisted across restarts — suitable for demos/dev.
// ---------------------------------------------------------------------------
const _mockStore = new Map(); // id -> lesson object

function _isMock() {
  return (process.env.MOCK_MODE || '').toLowerCase() === 'true';
}

function _mockId() {
  return crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2);
}

function _mockCreate({ userId, title, steps, videoUrl, summary }) {
  const now = new Date();
  const lesson = {
    _id: _mockId(),
    id: undefined,
    userId,
    title,
    steps: steps || [],
    videoUrl: videoUrl || '',
    summary: summary || '',
    favorite: false,
    views: 0,
    createdAt: now,
    updatedAt: now,
  };
  lesson.id = lesson._id;
  _mockStore.set(lesson._id, lesson);
  return lesson;
}

// ---------------------------------------------------------------------------

export async function createLessonForUser({ userId, title, steps, videoUrl, summary }) {
  if (_isMock()) {
    return _mockCreate({ userId, title, steps, videoUrl, summary });
  }

  const lesson = await Lesson.create({ userId, title, steps, videoUrl, summary });

  if (isValidObjectId(userId)) {
    await User.findByIdAndUpdate(userId, { $push: { savedLessons: lesson._id } });
  }

  return lesson;
}

export async function deleteLessonForUser({ lessonId, userId }) {
  if (_isMock()) {
    const lesson = _mockStore.get(lessonId);
    if (!lesson) return { invalidId: false, deletedCount: 0 };
    if (lesson.userId !== userId) return { invalidId: false, deletedCount: 0 };
    _mockStore.delete(lessonId);
    return { invalidId: false, deletedCount: 1 };
  }

  if (!isValidObjectId(lessonId)) {
    return { invalidId: true, deletedCount: 0 };
  }

  const result = await Lesson.deleteOne({ _id: lessonId, userId });
  return { invalidId: false, deletedCount: result.deletedCount || 0 };
}

export async function setFavoriteForUser({ lessonId, userId, favorite }) {
  if (_isMock()) {
    const lesson = _mockStore.get(lessonId);
    if (!lesson || lesson.userId !== userId) return null;
    lesson.favorite = favorite;
    lesson.updatedAt = new Date();
    return lesson;
  }

  return await Lesson.findOneAndUpdate(
    { _id: lessonId, userId },
    { favorite, updatedAt: new Date() },
    { new: true }
  );
}

export async function recordLessonViewForUser({ lessonId, userId }) {
  if (_isMock()) {
    const lesson = _mockStore.get(lessonId);
    if (!lesson || lesson.userId !== userId) return null;
    lesson.views = (lesson.views || 0) + 1;
    lesson.updatedAt = new Date();
    return lesson;
  }

  return await Lesson.findOneAndUpdate(
    { _id: lessonId, userId },
    { $inc: { views: 1 }, lastViewedAt: new Date(), updatedAt: new Date() },
    { new: true }
  );
}

export async function listLessonsForUser({ userId, favorite, sortBy, order, limit, offset }) {
  if (_isMock()) {
    let items = [..._mockStore.values()].filter((l) => l.userId === userId);
    if (favorite !== undefined) items = items.filter((l) => l.favorite === favorite);
    items.sort((a, b) => {
      const va = a[sortBy] instanceof Date ? a[sortBy].getTime() : (a[sortBy] ?? 0);
      const vb = b[sortBy] instanceof Date ? b[sortBy].getTime() : (b[sortBy] ?? 0);
      return order === 1 ? va - vb : vb - va;
    });
    return items.slice(offset, offset + limit);
  }

  const filter = { userId };
  if (favorite !== undefined) {
    filter.favorite = favorite;
  }

  return await Lesson.find(filter)
    .sort({ [sortBy]: order })
    .skip(offset)
    .limit(limit)
    .lean();
}
