import express from 'express';

import {
  createLesson,
  deleteLesson,
  listLessons,
  recordView,
  setFavorite,
} from '../controllers/lessonsController.js';
import { userIdMiddleware } from '../utils/userIdMiddleware.js';

const router = express.Router();

router.get('/', userIdMiddleware, listLessons);
router.post('/', userIdMiddleware, createLesson);
router.delete('/:id', userIdMiddleware, deleteLesson);
router.patch('/:id/favorite', userIdMiddleware, setFavorite);
router.post('/:id/view', userIdMiddleware, recordView);

export default router;
