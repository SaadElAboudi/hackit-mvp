import { Router } from 'express';

import {
    addComment,
    approveVersion,
    archiveProject,
    createProject,
    createThread,
    getProject,
    getThread,
    getVersion,
    joinProject,
    listProjects,
    listThreads,
    listVersions,
    regenerateInvite,
    removeMember,
    updateMemberRole,
    updateProject,
} from '../controllers/projectsController.js';
import { sendThreadMessage } from '../services/threadGemini.js';
import mongoose from 'mongoose';
import { userIdMiddleware } from '../utils/userIdMiddleware.js';

const router = Router();

// Fail fast if MongoDB is not connected — avoids 10 s buffer timeout
router.use((_req, res, next) => {
  if (mongoose.connection.readyState !== 1) {
    return res.status(503).json({ error: 'Database not available. Set MONGODB_URI on the server.' });
  }
  next();
});

// Attach userId (from x-user-id header, cookie, or generate anon) on every request
router.use(userIdMiddleware);

// ── Projects ──────────────────────────────────────────────────────────────────
router.post('/', createProject);
router.get('/', listProjects);
router.get('/:slug', getProject);
router.patch('/:slug', updateProject);
router.delete('/:slug', archiveProject);

// ── Invite ────────────────────────────────────────────────────────────────────
router.post('/join/:token', joinProject);
router.post('/:slug/invite/regenerate', regenerateInvite);

// ── Members ───────────────────────────────────────────────────────────────────
router.patch('/:slug/members/:memberId', updateMemberRole);
router.delete('/:slug/members/:memberId', removeMember);

// ── Threads ───────────────────────────────────────────────────────────────────
router.post('/:slug/threads', createThread);
router.get('/:slug/threads', listThreads);
router.get('/:slug/threads/:threadId', getThread);

// ── Thread messages (Gemini) ─────────────────────────────────────────────────
router.post('/:slug/threads/:threadId/messages', sendThreadMessage);

// ── Versions ──────────────────────────────────────────────────────────────────
router.get('/:slug/threads/:threadId/versions', listVersions);
router.get('/:slug/threads/:threadId/versions/:versionId', getVersion);
router.post('/:slug/threads/:threadId/versions/:versionId/approve', approveVersion);
router.post('/:slug/threads/:threadId/versions/:versionId/comments', addComment);

export default router;
