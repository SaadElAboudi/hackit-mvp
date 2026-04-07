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

const router = Router();

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
