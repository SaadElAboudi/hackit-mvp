import { randomBytes } from 'crypto';
import mongoose from 'mongoose';

import Project from '../models/Project.js';
import Thread from '../models/Thread.js';
import Version from '../models/Version.js';

// ─── helpers ────────────────────────────────────────────────────────────────

function requireAuth(req) {
  // userId is set by userIdMiddleware (JWT or anon cookie)
  const userId = req.userId;
  if (!userId) throw Object.assign(new Error('Unauthorized'), { status: 401 });
  return userId;
}

function assertMember(project, userId, minRole = 'viewer') {
  const roles = ['viewer', 'editor', 'owner'];
  const member = project.members.find((m) => m.userId.toString() === userId.toString());
  if (!member || roles.indexOf(member.role) < roles.indexOf(minRole)) {
    throw Object.assign(new Error('Forbidden'), { status: 403 });
  }
  return member;
}

// ─── Project CRUD ─────────────────────────────────────────────────────────────

/**
 * POST /api/projects
 * Create a new project. The caller becomes the owner.
 */
export async function createProject(req, res) {
  try {
    const userId = requireAuth(req);
    const { title, description, isPublic } = req.body;
    if (!title?.trim()) {
      return res.status(400).json({ error: 'title is required' });
    }

    const slug = Project.generateSlug(title);
    const project = await Project.create({
      title: title.trim(),
      description: description?.trim() ?? '',
      slug,
      isPublic: Boolean(isPublic),
      members: [{ userId, role: 'owner' }],
    });

    res.status(201).json({ project: _safeProject(project) });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * GET /api/projects
 * List projects the authenticated user is a member of.
 */
export async function listProjects(req, res) {
  try {
    const userId = requireAuth(req);
    const projects = await Project.find({ 'members.userId': userId, archivedAt: null })
      .sort({ updatedAt: -1 })
      .limit(50)
      .select('-inviteToken')
      .lean();
    res.json({ projects });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * GET /api/projects/:slug
 * Get a project by slug. Must be a member or project must be public.
 */
export async function getProject(req, res) {
  try {
    const userId = req.userId; // may be null for public projects
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });

    const isMember = project.members.some((m) => m.userId.toString() === userId?.toString());
    if (!project.isPublic && !isMember) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    // Strip inviteToken from non-owner responses
    const isOwner = project.members.some(
      (m) => m.userId.toString() === userId?.toString() && m.role === 'owner'
    );
    const safe = { ...project };
    if (!isOwner) delete safe.inviteToken;
    res.json({ project: safe });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * PATCH /api/projects/:slug
 * Update title / description / isPublic. Owner only.
 */
export async function updateProject(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug });
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'owner');

    const { title, description, isPublic } = req.body;
    if (title !== undefined) project.title = title.trim();
    if (description !== undefined) project.description = description.trim();
    if (isPublic !== undefined) project.isPublic = Boolean(isPublic);
    await project.save();

    res.json({ project: _safeProject(project) });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * DELETE /api/projects/:slug
 * Soft-delete (archive) a project. Owner only.
 */
export async function archiveProject(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug });
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'owner');

    project.archivedAt = new Date();
    await project.save();
    res.json({ ok: true });
  } catch (err) {
    _handleError(res, err);
  }
}

// ─── Invite ───────────────────────────────────────────────────────────────────

/**
 * POST /api/projects/:slug/invite/regenerate
 * Rotate the invite token (invalidates all previous invite links). Owner only.
 */
export async function regenerateInvite(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug });
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'owner');

    project.inviteToken = randomBytes(16).toString('hex');
    await project.save();
    res.json({ inviteToken: project.inviteToken });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * POST /api/projects/join/:token
 * Join a project using an invite token. Adds the caller as an editor.
 */
export async function joinProject(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ inviteToken: req.params.token, archivedAt: null });
    if (!project) return res.status(404).json({ error: 'Invalid or expired invite link' });

    const already = project.members.some((m) => m.userId.toString() === userId.toString());
    if (!already) {
      project.members.push({ userId, role: 'editor' });
      await project.save();
    }
    res.json({ project: _safeProject(project) });
  } catch (err) {
    _handleError(res, err);
  }
}

// ─── Members ──────────────────────────────────────────────────────────────────

/**
 * PATCH /api/projects/:slug/members/:memberId
 * Change a member's role. Owner only.
 */
export async function updateMemberRole(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug });
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'owner');

    const { role } = req.body;
    if (!['editor', 'viewer'].includes(role)) {
      return res.status(400).json({ error: 'role must be editor or viewer' });
    }
    const member = project.members.find(
      (m) => m.userId.toString() === req.params.memberId
    );
    if (!member) return res.status(404).json({ error: 'Member not found' });
    if (member.role === 'owner') {
      return res.status(400).json({ error: 'Cannot change owner role' });
    }
    member.role = role;
    await project.save();
    res.json({ ok: true, member });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * DELETE /api/projects/:slug/members/:memberId
 * Remove a member. Owner only (or self-remove).
 */
export async function removeMember(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug });
    if (!project) return res.status(404).json({ error: 'Project not found' });

    const isSelf = req.params.memberId === userId.toString();
    if (!isSelf) assertMember(project, userId, 'owner');

    const targetMember = project.members.find(
      (m) => m.userId.toString() === req.params.memberId
    );
    if (!targetMember) return res.status(404).json({ error: 'Member not found' });
    if (targetMember.role === 'owner') {
      return res.status(400).json({ error: 'Cannot remove the owner' });
    }

    project.members = project.members.filter(
      (m) => m.userId.toString() !== req.params.memberId
    );
    await project.save();
    res.json({ ok: true });
  } catch (err) {
    _handleError(res, err);
  }
}

// ─── Threads ─────────────────────────────────────────────────────────────────

/**
 * POST /api/projects/:slug/threads
 * Create a new thread in the project.
 */
export async function createThread(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug, archivedAt: null });
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'editor');

    const { title, mode, context, parentThreadId, forkMessageIndex } = req.body;

    // Validate fork reference if provided
    if (parentThreadId) {
      const parent = await Thread.findOne({
        _id: parentThreadId,
        projectId: project._id,
      });
      if (!parent) return res.status(404).json({ error: 'Parent thread not found' });
    }

    const thread = await Thread.create({
      projectId: project._id,
      title: title?.trim() || 'Conversation',
      mode: mode || null,
      context: context || {},
      parentThreadId: parentThreadId || null,
      forkMessageIndex: forkMessageIndex ?? null,
    });

    project.threadIds.push(thread._id);
    await project.save();

    res.status(201).json({ thread });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * GET /api/projects/:slug/threads
 * List threads in a project (summary, no messages).
 */
export async function listThreads(req, res) {
  try {
    const userId = req.userId;
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });

    const isMember = project.members.some((m) => m.userId.toString() === userId?.toString());
    if (!project.isPublic && !isMember) return res.status(403).json({ error: 'Forbidden' });

    const threads = await Thread.find({ projectId: project._id, archivedAt: null })
      .sort({ createdAt: -1 })
      .select('-messages') // don't send messages in list
      .lean();
    res.json({ threads });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * GET /api/projects/:slug/threads/:threadId
 * Get a thread with its messages.
 */
export async function getThread(req, res) {
  try {
    const userId = req.userId;
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });

    const isMember = project.members.some((m) => m.userId.toString() === userId?.toString());
    if (!project.isPublic && !isMember) return res.status(403).json({ error: 'Forbidden' });

    if (!mongoose.Types.ObjectId.isValid(req.params.threadId)) {
      return res.status(400).json({ error: 'Invalid threadId' });
    }

    const thread = await Thread.findOne({
      _id: req.params.threadId,
      projectId: project._id,
    }).lean();
    if (!thread) return res.status(404).json({ error: 'Thread not found' });

    res.json({ thread });
  } catch (err) {
    _handleError(res, err);
  }
}

// ─── Versions ────────────────────────────────────────────────────────────────

/**
 * GET /api/projects/:slug/threads/:threadId/versions
 * List versions of a thread.
 */
export async function listVersions(req, res) {
  try {
    const userId = req.userId;
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });

    const isMember = project.members.some((m) => m.userId.toString() === userId?.toString());
    if (!project.isPublic && !isMember) return res.status(403).json({ error: 'Forbidden' });

    if (!mongoose.Types.ObjectId.isValid(req.params.threadId)) {
      return res.status(400).json({ error: 'Invalid threadId' });
    }

    const versions = await Version.find({ threadId: req.params.threadId })
      .sort({ number: -1 })
      .select('-content') // content fetched individually to keep list light
      .lean();
    res.json({ versions });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * GET /api/projects/:slug/threads/:threadId/versions/:versionId
 * Get a full version (including content).
 */
export async function getVersion(req, res) {
  try {
    const userId = req.userId;
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });

    const isMember = project.members.some((m) => m.userId.toString() === userId?.toString());
    if (!project.isPublic && !isMember) return res.status(403).json({ error: 'Forbidden' });

    const version = await Version.findById(req.params.versionId).lean();
    if (!version || version.threadId.toString() !== req.params.threadId) {
      return res.status(404).json({ error: 'Version not found' });
    }
    res.json({ version });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * POST /api/projects/:slug/threads/:threadId/versions/:versionId/approve
 * Approve or reject a version. Any editor or owner can vote.
 */
export async function approveVersion(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'editor');

    const { decision, comment } = req.body;
    if (!['approved', 'rejected'].includes(decision)) {
      return res.status(400).json({ error: 'decision must be approved or rejected' });
    }

    const version = await Version.findById(req.params.versionId);
    if (!version || version.threadId.toString() !== req.params.threadId) {
      return res.status(404).json({ error: 'Version not found' });
    }

    // Remove existing vote from this user, then add new one
    version.approvals = version.approvals.filter(
      (a) => a.userId.toString() !== userId.toString()
    );
    version.approvals.push({ userId, decision, comment: comment?.slice(0, 500) ?? '' });

    // Auto-update status: if any owner approves → approved
    const ownerIds = project.members
      .filter((m) => m.role === 'owner')
      .map((m) => m.userId.toString());
    const ownerApproved = version.approvals.some(
      (a) => ownerIds.includes(a.userId.toString()) && a.decision === 'approved'
    );
    if (ownerApproved) version.status = 'approved';

    await version.save();
    res.json({ version });
  } catch (err) {
    _handleError(res, err);
  }
}

/**
 * POST /api/projects/:slug/threads/:threadId/versions/:versionId/comments
 * Add a review comment to a version.
 */
export async function addComment(req, res) {
  try {
    const userId = requireAuth(req);
    const project = await Project.findOne({ slug: req.params.slug }).lean();
    if (!project) return res.status(404).json({ error: 'Project not found' });
    assertMember(project, userId, 'editor');

    const { text, sectionAnchor } = req.body;
    if (!text?.trim()) return res.status(400).json({ error: 'text is required' });

    const version = await Version.findById(req.params.versionId);
    if (!version || version.threadId.toString() !== req.params.threadId) {
      return res.status(404).json({ error: 'Version not found' });
    }

    version.comments.push({
      authorId: userId,
      text: text.trim().slice(0, 2000),
      sectionAnchor: sectionAnchor ?? null,
    });
    await version.save();
    res.status(201).json({ comment: version.comments[version.comments.length - 1] });
  } catch (err) {
    _handleError(res, err);
  }
}

// ─── Internals ───────────────────────────────────────────────────────────────

function _safeProject(project) {
  const obj = project.toObject ? project.toObject() : { ...project };
  return obj;
}

function _handleError(res, err) {
  const status = err.status || 500;
  console.error('[projects]', err.message);
  res.status(status).json({ error: err.message || 'Internal server error' });
}
