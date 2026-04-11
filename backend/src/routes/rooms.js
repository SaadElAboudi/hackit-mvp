/**
 * rooms.js — REST API for Hackit Channels.
 *
 * The backend still uses "rooms" as the storage primitive, while the product
 * exposes them as shareable collaborative channels with shared AI.
 */

import express from 'express';
import mongoose from 'mongoose';

import ArtifactVersion from '../models/ArtifactVersion.js';
import Room from '../models/Room.js';
import RoomArtifact from '../models/RoomArtifact.js';
import RoomMemory from '../models/RoomMemory.js';
import RoomMessage from '../models/RoomMessage.js';
import RoomMission from '../models/RoomMission.js';
import {
  createRoomArtifact,
  parseRoomCommand,
  reviseRoomArtifact,
  triggerRoomAutomation,
} from '../services/roomOrchestrator.js';
import {
  broadcastRoomChallenge,
  broadcastRoomMessage,
  getOnlineUserIds,
} from '../services/roomWS.js';

const router = express.Router();
const APP_BASE_URL =
  process.env.APP_BASE_URL || 'https://saadelaboudi.github.io/hackit-mvp';

router.use((req, res, next) => {
  if (mongoose.connection.readyState !== 1) {
    return res
      .status(503)
      .json({ error: 'Database not available. Set MONGODB_URI on the server.' });
  }

  const userId = String(req.headers['x-user-id'] || '').trim();
  if (!userId) {
    return res.status(401).json({ error: 'x-user-id header required' });
  }

  req.userId = userId;
  req.displayName =
    String(req.headers['x-display-name'] || '').trim() ||
    `User_${userId.slice(-6)}`;
  next();
});

function isRoomMember(room, userId) {
  return room.members.some((member) => member.userId === userId);
}

function isRoomOwner(room, userId) {
  return room.members.some(
    (member) => member.userId === userId && member.role === 'owner'
  );
}

async function loadRoomOr404(roomId, res) {
  const room = await Room.findById(roomId);
  if (!room) {
    res.status(404).json({ error: 'Room not found' });
    return null;
  }
  return room;
}

function roomResponse(room) {
  const json = room.toObject ? room.toObject() : room;
  return {
    ...json,
    lastActivityAt: json.lastActivityAt || json.updatedAt,
  };
}

function missionSummary(mission) {
  const json = mission.toObject ? mission.toObject() : mission;
  return {
    ...json,
    promptPreview: String(json.prompt || '').slice(0, 140),
  };
}

function artifactSummary(artifact, version) {
  const json = artifact.toObject ? artifact.toObject() : artifact;
  return {
    ...json,
    currentVersion: version
      ? {
          ...(version.toObject ? version.toObject() : version),
          contentPreview: String(version.content || '').slice(0, 240),
        }
      : null,
  };
}

router.get('/', async (req, res) => {
  try {
    const rooms = await Room.find({ 'members.userId': req.userId })
      .sort({ lastActivityAt: -1, updatedAt: -1 })
      .lean();
    res.json({ rooms });
  } catch (err) {
    console.error('[rooms] list error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/', async (req, res) => {
  try {
    const {
      name,
      type = 'group',
      members = [],
      purpose = '',
      visibility = 'invite_only',
    } = req.body || {};

    if (!['dm', 'group'].includes(type)) {
      return res.status(400).json({ error: 'type must be "dm" or "group"' });
    }
    if (!['invite_only', 'public'].includes(visibility)) {
      return res.status(400).json({
        error: 'visibility must be "invite_only" or "public"',
      });
    }

    const allMembers = [
      {
        userId: req.userId,
        displayName: req.displayName,
        role: 'owner',
      },
      ...members
        .filter((member) => member.userId && member.userId !== req.userId)
        .map((member) => ({
          userId: String(member.userId).trim(),
          displayName:
            String(member.displayName || '').trim() ||
            `User_${String(member.userId).trim().slice(-6)}`,
          role: ['owner', 'member', 'guest'].includes(member.role)
            ? member.role
            : 'member',
        })),
    ];

    const room = await Room.create({
      name: String(name || '').trim() || 'Nouveau channel',
      type,
      purpose: String(purpose || '').trim().slice(0, 240),
      visibility,
      ownerId: req.userId,
      members: allMembers,
      lastActivityAt: new Date(),
    });

    res.status(201).json({ room: roomResponse(room) });
  } catch (err) {
    console.error('[rooms] create error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/messages', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;

    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const messages = await RoomMessage.find({ roomId: req.params.id })
      .sort({ createdAt: 1 })
      .limit(150)
      .lean();

    res.json({ messages, room: roomResponse(room) });
  } catch (err) {
    console.error('[rooms] messages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/messages', async (req, res) => {
  try {
    const { content } = req.body || {};
    if (!String(content || '').trim()) {
      return res.status(400).json({ error: 'content is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const message = await RoomMessage.create({
      roomId: room._id,
      senderId: req.userId,
      senderName: req.displayName,
      isAI: false,
      content: String(content).trim(),
      type: 'text',
      data: {
        command: parseRoomCommand(content).kind,
      },
    });

    broadcastRoomMessage(req.params.id, message.toObject());

    room.lastActivityAt = new Date();
    await room.save();

    res.status(201).json({ message });

    const parsed = parseRoomCommand(content);
    if (parsed.kind !== 'none') {
      triggerRoomAutomation({
        room,
        roomId: req.params.id,
        triggeringMessage: message.toObject(),
        actor: {
          userId: req.userId,
          displayName: req.displayName,
        },
      }).catch((error) => {
        console.error('[rooms] automation error:', error);
      });
    }
  } catch (err) {
    console.error('[rooms] send message error:', err);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

router.patch('/:id/directives', async (req, res) => {
  try {
    const directives = String(req.body?.directives || '');
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    room.aiDirectives = directives.slice(0, 2000);
    await room.save();
    res.json({ room: roomResponse(room) });
  } catch (err) {
    console.error('[rooms] directives error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/messages/:msgId/challenge', async (req, res) => {
  try {
    const content = String(req.body?.content || '').trim();
    if (!content) {
      return res.status(400).json({ error: 'content is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const roomMessage = await RoomMessage.findById(req.params.msgId);
    if (!roomMessage || String(roomMessage.roomId) !== req.params.id) {
      return res.status(404).json({ error: 'Message not found' });
    }

    roomMessage.challenges.push({
      userId: req.userId,
      userName: req.displayName,
      content,
    });
    await roomMessage.save();

    const savedChallenge =
      roomMessage.challenges[roomMessage.challenges.length - 1];

    const artifactId = roomMessage.data?.artifactId;
    if (artifactId) {
      const artifact = await RoomArtifact.findById(artifactId);
      const versionId = artifact?.currentVersionId || roomMessage.data?.versionId;
      if (versionId) {
        const version = await ArtifactVersion.findById(versionId);
        if (version) {
          version.comments.push({
            authorId: req.userId,
            authorName: req.displayName,
            text: content,
          });
          await version.save();
        }
      }
    }

    broadcastRoomChallenge(
      req.params.id,
      req.params.msgId,
      savedChallenge.toObject()
    );

    res.status(201).json({ challenge: savedChallenge });
  } catch (err) {
    console.error('[rooms] challenge error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/members', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const onlineIds = getOnlineUserIds(req.params.id);
    const members = room.members.map((member) => ({
      ...member.toObject(),
      online: onlineIds.includes(member.userId),
    }));

    res.json({ members, onlineCount: onlineIds.length });
  } catch (err) {
    console.error('[rooms] members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/members', async (req, res) => {
  try {
    const userId = String(req.body?.userId || '').trim();
    const displayName = String(req.body?.displayName || '').trim();
    const role = String(req.body?.role || 'member').trim();
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    if (room.members.some((member) => member.userId === userId)) {
      return res.status(409).json({ error: 'User is already a member' });
    }

    room.members.push({
      userId,
      displayName: displayName || `User_${userId.slice(-6)}`,
      role: ['owner', 'member', 'guest'].includes(role) ? role : 'member',
    });
    room.lastActivityAt = new Date();
    await room.save();

    res.status(201).json({ room: roomResponse(room) });
  } catch (err) {
    console.error('[rooms] add member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/:id/members/:uid', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomOwner(room, req.userId)) {
      return res.status(403).json({ error: 'Owner role required' });
    }
    if (room.members.length <= 1) {
      return res.status(400).json({ error: 'Cannot remove the last member' });
    }

    room.members = room.members.filter(
      (member) => member.userId !== req.params.uid
    );
    room.lastActivityAt = new Date();
    await room.save();

    res.json({ room: roomResponse(room) });
  } catch (err) {
    console.error('[rooms] remove member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/invite', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const link = `${APP_BASE_URL}/#/channel/${req.params.id}`;
    res.json({ link, roomName: room.name });
  } catch (err) {
    console.error('[rooms] invite error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/artifacts', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const artifacts = await RoomArtifact.find({ roomId: req.params.id })
      .sort({ updatedAt: -1 })
      .limit(40);
    const versionIds = artifacts
      .map((artifact) => artifact.currentVersionId)
      .filter(Boolean);
    const versions = versionIds.length
      ? await ArtifactVersion.find({ _id: { $in: versionIds } })
      : [];
    const versionsById = new Map(
      versions.map((version) => [String(version._id), version])
    );

    res.json({
      artifacts: artifacts.map((artifact) =>
        artifactSummary(
          artifact,
          artifact.currentVersionId
            ? versionsById.get(String(artifact.currentVersionId))
            : null
        )
      ),
    });
  } catch (err) {
    console.error('[rooms] artifacts list error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/artifacts', async (req, res) => {
  try {
    const title = String(req.body?.title || '').trim();
    const content = String(req.body?.content || '').trim();
    const kind = String(req.body?.kind || 'canvas').trim();
    if (!content) {
      return res.status(400).json({ error: 'content is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const result = await createRoomArtifact({
      roomId: req.params.id,
      title: title || 'Canvas partagé',
      content,
      kind: ['canvas', 'document', 'decision', 'research'].includes(kind)
        ? kind
        : 'canvas',
      createdBy: req.userId,
      createdByName: req.displayName,
      sourcePrompt: content,
      isAI: false,
      senderId: req.userId,
      senderName: req.displayName,
    });

    room.lastActivityAt = new Date();
    if (!room.pinnedArtifactId) {
      room.pinnedArtifactId = result.artifact._id;
      await room.save();
    }

    res.status(201).json({
      artifact: artifactSummary(result.artifact, result.version),
      message: result.message,
    });
  } catch (err) {
    console.error('[rooms] artifact create error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/artifacts/:artifactId/versions', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const artifact = await RoomArtifact.findOne({
      _id: req.params.artifactId,
      roomId: req.params.id,
    });
    if (!artifact) {
      return res.status(404).json({ error: 'Artifact not found' });
    }

    const versions = await ArtifactVersion.find({ artifactId: artifact._id }).sort({
      number: -1,
    });
    res.json({
      artifact: artifactSummary(artifact),
      versions: versions.map((version) => ({
        ...(version.toObject ? version.toObject() : version),
        contentPreview: String(version.content || '').slice(0, 240),
      })),
    });
  } catch (err) {
    console.error('[rooms] artifact versions error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/artifacts/:artifactId/revise', async (req, res) => {
  try {
    const instructions = String(req.body?.instructions || '').trim();
    if (!instructions) {
      return res.status(400).json({ error: 'instructions is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const artifact = await RoomArtifact.findOne({
      _id: req.params.artifactId,
      roomId: req.params.id,
    });
    if (!artifact) {
      return res.status(404).json({ error: 'Artifact not found' });
    }

    const result = await reviseRoomArtifact({
      room,
      artifact,
      instructions,
      actor: {
        userId: req.userId,
        displayName: req.displayName,
      },
    });

    room.lastActivityAt = new Date();
    await room.save();

    res.status(201).json({
      artifact: artifactSummary(artifact, result.version),
      version: result.version,
      message: result.message,
    });
  } catch (err) {
    console.error('[rooms] artifact revise error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/missions', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const missions = await RoomMission.find({ roomId: req.params.id })
      .sort({ createdAt: -1 })
      .limit(30);
    res.json({ missions: missions.map(missionSummary) });
  } catch (err) {
    console.error('[rooms] missions list error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/memory', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const memory = await RoomMemory.find({ roomId: req.params.id })
      .sort({ pinned: -1, createdAt: -1 })
      .limit(50)
      .lean();
    res.json({ memory });
  } catch (err) {
    console.error('[rooms] memory list error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/memory', async (req, res) => {
  try {
    const content = String(req.body?.content || '').trim();
    const type = String(req.body?.type || 'fact').trim();
    const pinned = req.body?.pinned !== false;
    if (!content) {
      return res.status(400).json({ error: 'content is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const memory = await RoomMemory.create({
      roomId: req.params.id,
      type: ['fact', 'preference', 'decision'].includes(type) ? type : 'fact',
      content,
      createdBy: req.userId,
      createdByName: req.displayName,
      pinned,
    });
    room.lastActivityAt = new Date();
    await room.save();

    res.status(201).json({ memory });
  } catch (err) {
    console.error('[rooms] memory create error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/:id/memory/:memoryId', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const deleted = await RoomMemory.findOneAndDelete({
      _id: req.params.memoryId,
      roomId: req.params.id,
    });
    if (!deleted) {
      return res.status(404).json({ error: 'Memory not found' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('[rooms] memory delete error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/decisions', async (req, res) => {
  try {
    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const decisions = await RoomMessage.find({
      roomId: req.params.id,
      type: 'decision',
    })
      .sort({ createdAt: -1 })
      .limit(20)
      .lean();
    res.json({ decisions });
  } catch (err) {
    console.error('[rooms] decisions list error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/search', async (req, res) => {
  try {
    const query = String(req.body?.query || '').trim();
    if (!query) {
      return res.status(400).json({ error: 'query is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const result = await triggerRoomAutomation({
      room,
      roomId: req.params.id,
      triggeringMessage: { content: `/search ${query}` },
      actor: {
        userId: req.userId,
        displayName: req.displayName,
      },
    });

    room.lastActivityAt = new Date();
    await room.save();

    res.status(201).json(result);
  } catch (err) {
    console.error('[rooms] collaborative search error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/documents', async (req, res) => {
  try {
    const title = String(req.body?.title || '').trim();
    const content = String(req.body?.content || '').trim();
    if (!content) {
      return res.status(400).json({ error: 'content is required' });
    }

    const room = await loadRoomOr404(req.params.id, res);
    if (!room) return;
    if (!isRoomMember(room, req.userId)) {
      return res.status(403).json({ error: 'Not a member of this room' });
    }

    const result = await createRoomArtifact({
      roomId: req.params.id,
      title: title || 'Document partagé',
      content,
      kind: 'document',
      createdBy: req.userId,
      createdByName: req.displayName,
      sourcePrompt: content,
      isAI: false,
      senderId: req.userId,
      senderName: req.displayName,
    });

    room.lastActivityAt = new Date();
    if (!room.pinnedArtifactId) {
      room.pinnedArtifactId = result.artifact._id;
    }
    await room.save();

    res.status(201).json({ message: result.message, artifact: result.artifact });
  } catch (err) {
    console.error('[rooms] document error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
