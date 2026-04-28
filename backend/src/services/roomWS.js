/**
 * roomWS.js — WebSocket hub for the Salons (Rooms) feature.
 *
 * Handles connections at: ws://<host>/ws/rooms/:roomId
 *
 * This module does NOT create a WebSocketServer itself.
 * It exports handleRoomConnection(), which threadRooms.js routes to
 * when req.url starts with /ws/rooms/.
 *
 * Protocol (JSON frames):
 *
 *   Client → Server:
 *     { type: 'join',  roomId, userId, displayName }
 *     { type: 'ping' }
 *
 *   Server → Client:
 *     { type: 'joined',    roomId, memberCount }
 *     { type: 'message',   roomId, message }   — new RoomMessage object
 *     { type: 'typing',    roomId, userId }     — someone is typing (including AI)
 *     { type: 'challenge', roomId, messageId, challenge }
 *     { type: 'artifact_created', roomId, artifact, version }
 *     { type: 'artifact_version_created', roomId, artifactId, version }
 *     { type: 'mission_status', roomId, mission }
 *     { type: 'decision_created', roomId, message }
 *     { type: 'research_attached', roomId, message }
 *     { type: 'synthesis_suggested', roomId, message }
 *     { type: 'brief_suggested',     roomId, message }
 *     { type: 'share_result',        roomId, message }
 *     { type: 'notion_exported',      roomId, message }
 *     { type: 'presence',  roomId, userIds }    — current online users
 *     { type: 'pong' }
 *     { type: 'error',     reason }
 */

/** @type {Map<string, Set<WebSocket>>} roomId → active sockets */
const rooms = new Map();

/** @type {WeakMap<WebSocket, { roomId: string, userId: string }>} */
const meta = new WeakMap();

// ── Entry point (called by threadRooms.js) ────────────────────────────────────

/**
 * Route an incoming WS upgrade to the room handler.
 * @param {import('ws').WebSocket} ws
 * @param {import('http').IncomingMessage} req
 */
export function handleRoomConnection(ws, req) {
  const match = req.url?.match(/^\/ws\/rooms\/([a-f0-9]{24})$/i);
  if (!match) {
    ws.close(4001, 'Invalid room path');
    return;
  }
  const roomId = match[1];

  // Track without userId until 'join' frame arrives
  meta.set(ws, { roomId, userId: null });

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
        _handleJoin(ws, roomId, msg.userId, msg.displayName);
        break;
      case 'ping':
        _send(ws, { type: 'pong' });
        break;
      default:
        _send(ws, { type: 'error', reason: `Unknown type: ${msg.type}` });
    }
  });

  ws.on('close', () => _leave(ws));
  ws.on('error', () => _leave(ws));
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function _handleJoin(ws, roomId, userId, _displayName) {
  if (!userId) {
    _send(ws, { type: 'error', reason: 'userId required' });
    return;
  }

  meta.set(ws, { roomId, userId });

  if (!rooms.has(roomId)) rooms.set(roomId, new Set());
  rooms.get(roomId).add(ws);

  _send(ws, { type: 'joined', roomId, memberCount: rooms.get(roomId).size });
  _broadcastPresence(roomId);
}

function _leave(ws) {
  const info = meta.get(ws);
  if (!info) return;
  const { roomId } = info;
  rooms.get(roomId)?.delete(ws);
  if (rooms.get(roomId)?.size === 0) rooms.delete(roomId);
  _broadcastPresence(roomId);
  meta.delete(ws);
}

function _broadcastPresence(roomId) {
  const sockets = rooms.get(roomId);
  if (!sockets) return;
  const userIds = [...sockets]
    .map((s) => meta.get(s)?.userId)
    .filter(Boolean);
  _broadcast(roomId, { type: 'presence', roomId, userIds });
  _broadcast(roomId, { type: 'presence.updated', roomId, userIds });
}

function _broadcast(roomId, payload) {
  rooms.get(roomId)?.forEach((ws) => _send(ws, payload));
}

function _send(ws, payload) {
  if (ws.readyState === 1 /* OPEN */) {
    ws.send(JSON.stringify(payload));
  }
}

// ── Exported helpers (called by roomGemini.js and rooms.js) ──────────────────

export function broadcastRoomMessage(roomId, message, requestId = null) {
  _broadcast(roomId, { type: 'message', roomId, message, requestId });
}

export function broadcastRoomTyping(roomId, userId) {
  _broadcast(roomId, { type: 'typing', roomId, userId });
}

/** Stream a partial AI response. delta = cumulative content generated so far. */
export function broadcastRoomMessageChunk(roomId, tempId, delta) {
  _broadcast(roomId, { type: 'message_chunk', roomId, tempId, delta });
}

export function broadcastRoomChallenge(roomId, messageId, challenge, requestId = null) {
  _broadcast(roomId, { type: 'challenge', roomId, messageId, challenge, requestId });
}

export function broadcastRoomArtifactCreated(roomId, artifact, version) {
  _broadcast(roomId, { type: 'artifact_created', roomId, artifact, version });
}

export function broadcastRoomArtifactVersionCreated(roomId, artifactId, version) {
  _broadcast(roomId, {
    type: 'artifact_version_created',
    roomId,
    artifactId,
    version,
  });
}

export function broadcastRoomMissionStatus(roomId, mission, requestId = null) {
  _broadcast(roomId, { type: 'mission_status', roomId, mission, requestId });
}

export function broadcastRoomDecisionCreated(roomId, message, requestId = null) {
  _broadcast(roomId, { type: 'decision_created', roomId, message, requestId });
}

export function broadcastRoomResearchAttached(roomId, message) {
  _broadcast(roomId, { type: 'research_attached', roomId, message });
}

export function broadcastRoomSynthesisSuggested(roomId, message) {
  _broadcast(roomId, { type: 'synthesis_suggested', roomId, message });
}

export function broadcastRoomBriefSuggested(roomId, message) {
  _broadcast(roomId, { type: 'brief_suggested', roomId, message });
}

export function broadcastRoomShareResult(roomId, message, requestId = null) {
  _broadcast(roomId, { type: 'share_result', roomId, message, requestId });
}

export function broadcastRoomNotionExported(roomId, message) {
  _broadcast(roomId, { type: 'notion_exported', roomId, message });
}

export function broadcastPageBlockUpdated(roomId, payload, requestId = null) {
  _broadcast(roomId, { type: 'page.block.updated', roomId, ...payload, requestId });
}

export function broadcastCommentCreated(roomId, payload, requestId = null) {
  _broadcast(roomId, { type: 'comment.created', roomId, ...payload, requestId });
}

export function broadcastCommentResolved(roomId, payload, requestId = null) {
  _broadcast(roomId, { type: 'comment.resolved', roomId, ...payload, requestId });
}

/** Returns the list of currently online userIds for a room (used by REST endpoint). */
export function getOnlineUserIds(roomId) {
  const sockets = rooms.get(roomId);
  if (!sockets) return [];
  return [...sockets]
    .map((s) => meta.get(s)?.userId)
    .filter(Boolean);
}
