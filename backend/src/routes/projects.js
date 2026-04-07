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
