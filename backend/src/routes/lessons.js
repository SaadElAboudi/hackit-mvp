import express from 'express';

import {
  createLesson,
  deleteLesson,
  listLessons,
  recordView,
  setFavorite,
} from '../controllers/lessonsController.js';
import { requireJwtAuthOrGoogle } from '../utils/jwtAuth.js';
import { userIdMiddleware } from '../utils/userIdMiddleware.js';

const router = express.Router();

router.get('/', requireJwtAuthOrGoogle, userIdMiddleware, listLessons);
router.post('/', requireJwtAuthOrGoogle, userIdMiddleware, createLesson);
router.delete('/:id', requireJwtAuthOrGoogle, userIdMiddleware, deleteLesson);
router.patch('/:id/favorite', requireJwtAuthOrGoogle, userIdMiddleware, setFavorite);
router.post('/:id/view', requireJwtAuthOrGoogle, userIdMiddleware, recordView);

export default router;
