/**
 * threadGemini.js — Connects a persistent Thread to the Gemini generation
 * pipeline and handles message persistence + WebSocket broadcasting.
 *
 * This module is intentionally a thin orchestration layer:
 *   1. Validate the caller is a project member with editor rights.
 *   2. Append the user message to the Thread.
 *   3. Build the Gemini prompt from the thread history + user input.
 *   4. Call Gemini (via the HTTP API — same as the main search flow).
 *   5. Persist the AI response as a new Thread message.
 *   6. Broadcast both messages to all room subscribers.
 *   7. Optionally auto-pin the response as a new Version.
 *
 * Route handler:
 *   POST /api/projects/:slug/threads/:threadId/messages
 *   Body: { prompt: string, pin?: boolean, versionLabel?: string }
 */

import Project from '../models/Project.js';
import Thread from '../models/Thread.js';
import Version from '../models/Version.js';
import { broadcastMessage, broadcastVersion, broadcastTyping } from './threadRooms.js';
import { generateWithGemini } from './gemini.js';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'models/gemini-2.0-flash-lite';
const GEMINI_TIMEOUT_MS = parseInt(process.env.GEMINI_TIMEOUT_MS || '30000', 10);
const MAX_HISTORY_MESSAGES = 20; // how many past messages are fed to Gemini as context

/**
 * Express route handler.
 * POST /api/projects/:slug/threads/:threadId/messages
 */
export async function sendThreadMessage(req, res) {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: 'Unauthorized' });

  const { slug, threadId } = req.params;
  const { prompt, pin = false, versionLabel } = req.body;

  if (!prompt?.trim()) {
    return res.status(400).json({ error: 'prompt is required' });
  }

  // ── 1. Load project + check membership ─────────────────────────────────────
  const project = await Project.findOne({ slug, archivedAt: null }).lean();
  if (!project) return res.status(404).json({ error: 'Project not found' });

  const member = project.members.find((m) => m.userId.toString() === userId.toString());
  if (!member || member.role === 'viewer') {
    return res.status(403).json({ error: 'Editor or owner role required' });
  }

  // ── 2. Load thread ──────────────────────────────────────────────────────────
  const thread = await Thread.findOne({ _id: threadId, projectId: project._id });
  if (!thread) return res.status(404).json({ error: 'Thread not found' });

  // ── 3. Append user message ──────────────────────────────────────────────────
  const userMsg = {
    role: 'user',
    content: prompt.trim(),
    authorId: userId,
  };
  thread.messages.push(userMsg);
  const userMsgIndex = thread.messages.length - 1;

  // ── 4. Build Gemini prompt ──────────────────────────────────────────────────
  const history = thread.messages
    .slice(-MAX_HISTORY_MESSAGES - 1, -1) // exclude the message we just pushed
    .filter((m) => m.role !== 'system')
    .map((m) => `[${m.role === 'ai' ? 'assistant' : 'user'}]: ${m.content}`)
    .join('\n\n');

  const systemPreamble = _buildSystemPreamble(thread);
  const fullPrompt = history
    ? `${systemPreamble}\n\n${history}\n\n[user]: ${prompt.trim()}`
    : `${systemPreamble}\n\n[user]: ${prompt.trim()}`;

  // Notify other room members that Gemini is processing (they'll show a typing bubble)
  broadcastTyping(threadId, userId);

  // ── 5. Call Gemini ──────────────────────────────────────────────────────────
  const t0 = Date.now();
  let aiText;
  try {
    aiText = await _callGemini(fullPrompt);
  } catch (err) {
    // Persist the user message even on Gemini failure so history isn't lost
    await thread.save();
    broadcastMessage(threadId, thread.messages[userMsgIndex].toObject());
    console.error('[threadGemini] Gemini error:', err.message);
    return res.status(502).json({ error: `Gemini failed: ${err.message}` });
  }
  const latencyMs = Date.now() - t0;

  // ── 6. Persist AI message ───────────────────────────────────────────────────
  const aiMsg = {
    role: 'ai',
    content: aiText,
    authorId: null,
    meta: { model: GEMINI_MODEL, latencyMs },
  };
  thread.messages.push(aiMsg);
  const aiMsgIndex = thread.messages.length - 1;

  // ── 7. Optionally pin as a new Version ──────────────────────────────────────
  let version = null;
  if (pin) {
    const versionCount = await Version.countDocuments({ threadId: thread._id });
    version = await Version.create({
      threadId: thread._id,
      projectId: project._id,
      number: versionCount + 1,
      label: versionLabel?.trim() || null,
      content: aiText,
      prompt: prompt.trim(),
      createdBy: userId,
      messageIndex: aiMsgIndex,
    });
    thread.messages[aiMsgIndex].versionRef = version._id;
    thread.activeVersionId = version._id;
  }

  await thread.save();

  // ── 8. Broadcast to WebSocket room ──────────────────────────────────────────
  broadcastMessage(threadId, thread.messages[userMsgIndex].toObject());
  broadcastMessage(threadId, thread.messages[aiMsgIndex].toObject());
  if (version) broadcastVersion(threadId, _summariseVersion(version));

  res.status(201).json({
    userMessage: thread.messages[userMsgIndex],
    aiMessage: thread.messages[aiMsgIndex],
    version: version ? _summariseVersion(version) : null,
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _buildSystemPreamble(thread) {
  const mode = thread.mode ? `Mode: ${thread.mode}.` : '';
  const ctx = thread.context && Object.keys(thread.context).length > 0
    ? `Context: ${JSON.stringify(thread.context)}.`
    : '';
  return [
    'You are a collaborative AI assistant helping a team work on a shared project.',
    'Be structured, actionable, specific, and concise.',
    'Avoid generic filler. Ground your response in the thread context and user request details.',
    'If context is missing, ask at most 2 targeted clarification questions instead of giving a vague template.',
    mode,
    ctx,
  ]
    .filter(Boolean)
    .join(' ');
}

async function _callGemini(prompt) {
  if (!GEMINI_API_KEY) throw new Error('GEMINI_API_KEY missing');
  return await generateWithGemini(prompt, 2048, {
    model: GEMINI_MODEL,
    preferModels: [GEMINI_MODEL],
    timeoutMs: GEMINI_TIMEOUT_MS,
    temperature: 0.35,
    maxAttemptsPerModel: 2,
    allowQualityRepair: true,
  });
}

/** Strip heavy content field for WS broadcast */
function _summariseVersion(v) {
  const obj = v.toObject ? v.toObject() : { ...v };
  delete obj.content;
  return obj;
}
