/**
 * threadRooms.js — WebSocket hub for real-time thread collaboration.
 *
 * Architecture:
 *   - One WebSocketServer attached to the existing HTTP server (no second port).
 *   - Clients connect to  ws://<host>/ws/threads/:threadId
 *   - The threadId is extracted from the URL path.
 *   - All clients in the same "room" (threadId) receive every broadcast.
 *
 * Message protocol (JSON, all frames):
 *
 *   Client → Server:
 *     { type: 'join',      threadId, userId }   — authenticate + subscribe
 *     { type: 'ping' }                          — keepalive
 *
 *   Server → Client:
 *     { type: 'joined',    threadId, memberCount }
 *     { type: 'message',   threadId, message }       — new Thread message object
 *     { type: 'version',   threadId, version }       — new Version pinned
 *     { type: 'approval',  threadId, versionId, approval }
 *     { type: 'presence',  threadId, userIds }       — current active users
 *     { type: 'pong' }
 *     { type: 'error',     reason }
 */

import { WebSocketServer } from 'ws';

/** @type {Map<string, Set<WebSocket>>} threadId → set of connected sockets */
const rooms = new Map();

/** @type {WeakMap<WebSocket, { threadId: string, userId: string }>} */
const meta = new WeakMap();

/**
 * Attach the WebSocket server to an existing http.Server instance.
 * Call this once at startup, after `app.listen()` returns the server.
 *
 * @param {import('http').Server} httpServer
 */
export function attachWebSocketServer(httpServer) {
  const wss = new WebSocketServer({ server: httpServer, path: undefined });

  wss.on('connection', (ws, req) => {
    // Extract threadId from URL: /ws/threads/<threadId>
    const match = req.url?.match(/^\/ws\/threads\/([a-f0-9]{24})$/i);
    if (!match) {
      ws.close(4001, 'Invalid path');
      return;
    }
    const threadId = match[1];

    // Temporarily track the socket without a userId until 'join' arrives
    meta.set(ws, { threadId, userId: null });

    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        _send(ws, { type: 'error', reason: 'Invalid JSON' });
        return;
      }

      switch (msg.type) {
        case 'join':
          _handleJoin(ws, threadId, msg.userId);
          break;
        case 'ping':
          _send(ws, { type: 'pong' });
          break;
        default:
          _send(ws, { type: 'error', reason: `Unknown type: ${msg.type}` });
      }
    });

    ws.on('close', () => {
      _leave(ws);
    });

    ws.on('error', () => {
      _leave(ws);
    });
  });

  console.log('[ws] WebSocket server attached');
  return wss;
}

// ─── Public broadcast helpers (called from the projects controller) ──────────

/**
 * Broadcast a new Thread message to all sockets in the room.
 * @param {string} threadId
 * @param {object} message  — the Mongoose message sub-document (lean object)
 */
export function broadcastMessage(threadId, message) {
  _broadcast(threadId, { type: 'message', threadId, message });
}

/**
 * Broadcast a newly pinned Version to the room.
 * @param {string} threadId
 * @param {object} version  — Version lean object (without content for bandwidth)
 */
export function broadcastVersion(threadId, version) {
  _broadcast(threadId, { type: 'version', threadId, version });
}

/**
 * Broadcast a new approval/rejection event.
 * @param {string} threadId
 * @param {string} versionId
 * @param {object} approval — ApprovalSchema sub-document
 */
export function broadcastApproval(threadId, versionId, approval) {
  _broadcast(threadId, { type: 'approval', threadId, versionId, approval });
}

/**
 * Broadcast a typing/thinking indicator — someone submitted a prompt,
 * Gemini is being called. Other participants can show a "Gemini is thinking" UI.
 * @param {string} threadId
 * @param {string} userId — the user who triggered the call
 */
export function broadcastTyping(threadId, userId) {
  _broadcast(threadId, { type: 'typing', threadId, userId });
}

/**
 * Returns a snapshot of currently connected userIds for a thread.
 * @param {string} threadId
 * @returns {string[]}
 */
export function getPresence(threadId) {
  const room = rooms.get(threadId);
  if (!room) return [];
  return [...room]
    .map((ws) => meta.get(ws)?.userId)
    .filter(Boolean);
}

// ─── Internal ────────────────────────────────────────────────────────────────

function _handleJoin(ws, threadId, userId) {
  if (!userId) {
    _send(ws, { type: 'error', reason: 'userId required in join' });
    return;
  }
  // Add to room
  if (!rooms.has(threadId)) rooms.set(threadId, new Set());
  rooms.get(threadId).add(ws);
  meta.set(ws, { threadId, userId });

  _send(ws, {
    type: 'joined',
    threadId,
    memberCount: rooms.get(threadId).size,
  });

  // Broadcast updated presence to the whole room
  _broadcastPresence(threadId);
}

function _leave(ws) {
  const info = meta.get(ws);
  if (!info) return;
  const { threadId } = info;
  const room = rooms.get(threadId);
  if (room) {
    room.delete(ws);
    if (room.size === 0) rooms.delete(threadId);
    else _broadcastPresence(threadId);
  }
  meta.delete(ws);
}

function _broadcast(threadId, payload) {
  const room = rooms.get(threadId);
  if (!room) return;
  const text = JSON.stringify(payload);
  for (const ws of room) {
    if (ws.readyState === 1 /* OPEN */) ws.send(text);
  }
}

function _broadcastPresence(threadId) {
  _broadcast(threadId, {
    type: 'presence',
    threadId,
    userIds: getPresence(threadId),
  });
}

function _send(ws, payload) {
  if (ws.readyState === 1) ws.send(JSON.stringify(payload));
}
