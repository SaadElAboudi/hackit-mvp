import mongoose from 'mongoose';

import Lesson from '../models/lesson.js';
import User from '../models/User.js';

function isValidObjectId(id) {
  return mongoose.Types.ObjectId.isValid(id);
}

export async function createLessonForUser({ userId, title, steps, videoUrl, summary }) {
  const lesson = await Lesson.create({ userId, title, steps, videoUrl, summary });

  if (isValidObjectId(userId)) {
    await User.findByIdAndUpdate(userId, { $push: { savedLessons: lesson._id } });
  }

  return lesson;
}

export async function deleteLessonForUser({ lessonId, userId }) {
  if (!isValidObjectId(lessonId)) {
    return { invalidId: true, deletedCount: 0 };
  }

  const result = await Lesson.deleteOne({ _id: lessonId, userId });
  return { invalidId: false, deletedCount: result.deletedCount || 0 };
}

export async function setFavoriteForUser({ lessonId, userId, favorite }) {
  return await Lesson.findOneAndUpdate(
    { _id: lessonId, userId },
    { favorite, updatedAt: new Date() },
    { new: true }
  );
}

export async function recordLessonViewForUser({ lessonId, userId }) {
  return await Lesson.findOneAndUpdate(
    { _id: lessonId, userId },
    { $inc: { views: 1 }, lastViewedAt: new Date(), updatedAt: new Date() },
    { new: true }
  );
}

export async function listLessonsForUser({ userId, favorite, sortBy, order, limit, offset }) {
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
