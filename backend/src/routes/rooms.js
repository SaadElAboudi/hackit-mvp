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
    suggestRoomBriefIfNeeded,
    triggerRoomAutomation,
    suggestRoomSynthesisIfNeeded,
} from '../services/roomOrchestrator.js';
import { buildSlackShareText, postSlackMessage } from '../services/slack.js';
import { createNotionPage, validateNotionToken } from '../services/notion.js';
import {
    broadcastRoomChallenge,
    broadcastRoomMessage,
    getOnlineUserIds,
} from '../services/roomWS.js';
import {
    validateAddMemberPayload,
    validateBody,
    validateCreateArtifactPayload,
    validateCreateMemoryPayload,
    validateCreateMissionPayload,
    validateCreateRoomPayload,
    validateDirectivesPayload,
    validateSendMessagePayload,
} from '../middleware/validation.js';

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

function tooManyRequestsError(message = 'Too many requests') {
    const err = new Error(message);
    err.status = 429;
    err.code = 'RATE_LIMITED';
    err.details = null;
    return err;
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

router.post('/', validateBody(validateCreateRoomPayload), async (req, res, next) => {
    try {
        const { name, type, members, purpose, visibility } = req.validatedBody;

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
        next(err);
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

router.post('/:id/messages', validateBody(validateSendMessagePayload), async (req, res, next) => {
    try {
        const { content } = req.validatedBody;
        const limiter = req.app?.locals?.simpleRateLimit;
        if (typeof limiter === 'function') {
            const allowed = await limiter(`room-msg:${req.userId}:${req.params.id}`, 40);
            if (!allowed) {
                throw tooManyRequestsError('Rate limit exceeded for room messages');
            }
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

        broadcastRoomMessage(req.params.id, message.toObject(), req.requestId || null);

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
        } else {
            // Controlled proactivity: suggest a synthesis only after enough
            // non-command messages and with cooldown safeguards.
            suggestRoomSynthesisIfNeeded({
                room,
                roomId: req.params.id,
                actor: {
                    userId: req.userId,
                    displayName: req.displayName,
                },
            }).catch((error) => {
                console.error('[rooms] synthesis suggestion error:', error);
            });

            suggestRoomBriefIfNeeded({
                room,
                roomId: req.params.id,
            }).catch((error) => {
                console.error('[rooms] meeting brief suggestion error:', error);
            });
        }
    } catch (err) {
        console.error('[rooms] send message error:', err);
        next(err);
    }
});

router.patch('/:id/directives', validateBody(validateDirectivesPayload), async (req, res, next) => {
    try {
        const { directives } = req.validatedBody;
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
        next(err);
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

router.post('/:id/members', validateBody(validateAddMemberPayload), async (req, res, next) => {
    try {
        const { userId, displayName, role } = req.validatedBody;

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to add members' });
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
        next(err);
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

router.post('/:id/artifacts', validateBody(validateCreateArtifactPayload), async (req, res, next) => {
    try {
        const { title, content, kind } = req.validatedBody;

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
        next(err);
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

router.post('/:id/artifacts/:artifactId/versions/:versionId/approve', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required' });
        }

        const artifact = await RoomArtifact.findOne({
            _id: req.params.artifactId,
            roomId: req.params.id,
        });
        if (!artifact) {
            return res.status(404).json({ error: 'Artifact not found' });
        }

        const version = await ArtifactVersion.findOne({
            _id: req.params.versionId,
            artifactId: artifact._id,
            roomId: req.params.id,
        });
        if (!version) {
            return res.status(404).json({ error: 'Version not found' });
        }

        version.status = 'approved';
        await version.save();

        artifact.status = 'validated';
        artifact.currentVersionId = version._id;
        artifact.updatedAt = new Date();
        await artifact.save();

        room.lastActivityAt = new Date();
        await room.save();

        res.json({
            artifact: artifactSummary(artifact, version),
            version,
        });
    } catch (err) {
        console.error('[rooms] artifact version approve error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

router.post('/:id/artifacts/:artifactId/versions/:versionId/comment', async (req, res) => {
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

        const artifact = await RoomArtifact.findOne({
            _id: req.params.artifactId,
            roomId: req.params.id,
        });
        if (!artifact) {
            return res.status(404).json({ error: 'Artifact not found' });
        }

        const version = await ArtifactVersion.findOne({
            _id: req.params.versionId,
            artifactId: artifact._id,
            roomId: req.params.id,
        });
        if (!version) {
            return res.status(404).json({ error: 'Version not found' });
        }

        version.comments.push({
            authorId: req.userId,
            authorName: req.displayName,
            text: content,
            resolved: false,
        });
        await version.save();

        artifact.updatedAt = new Date();
        await artifact.save();

        room.lastActivityAt = new Date();
        await room.save();

        res.status(201).json({
            artifact: artifactSummary(artifact, version),
            version,
            comment: version.comments[version.comments.length - 1],
        });
    } catch (err) {
        console.error('[rooms] artifact version comment error:', err);
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

router.post('/:id/missions', validateBody(validateCreateMissionPayload), async (req, res, next) => {
    try {
        const { prompt, agentType } = req.validatedBody;

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        // Trigger mission asynchronously — WS events will report progress
        triggerRoomAutomation({
            room,
            roomId: req.params.id,
            triggeringMessage: {
                content: `/mission ${prompt}`,
                senderId: req.userId,
                senderName: req.displayName,
            },
            options: { agentType },
            actor: { userId: req.userId, displayName: req.displayName },
        }).catch((err) => console.error('[rooms] mission async error:', err));

        room.lastActivityAt = new Date();
        await room.save();

        res.status(202).json({ ok: true, message: 'Mission queued' });
    } catch (err) {
        console.error('[rooms] mission create error:', err);
        next(err);
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

router.post('/:id/memory', validateBody(validateCreateMemoryPayload), async (req, res, next) => {
    try {
        const { content, type, pinned } = req.validatedBody;

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
        next(err);
    }
});

router.delete('/:id/memory/:memoryId', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        // Only the owner OR the memory creator may delete a memory entry
        const memory = await RoomMemory.findOne({
            _id: req.params.memoryId,
            roomId: req.params.id,
        });
        if (!memory) {
            return res.status(404).json({ error: 'Memory not found' });
        }
        if (!isRoomOwner(room, req.userId) && String(memory.createdBy) !== req.userId) {
            return res.status(403).json({ error: 'Owner or creator role required' });
        }

        await memory.deleteOne();
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

// ── Integrations: Slack ────────────────────────────────────────────────────────

/**
 * GET /api/rooms/:id/integrations/slack
 * Returns Slack integration status (token is masked for safety).
 */
router.get('/:id/integrations/slack', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }
        const slack = room.integrations?.slack || {};
        res.json({
            enabled: Boolean(slack.enabled),
            connected: Boolean(slack.botToken),
            channelId: slack.channelId || '',
            connectedBy: slack.connectedBy || '',
            connectedAt: slack.connectedAt || null,
        });
    } catch (err) {
        console.error('[rooms/slack] status error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

/**
 * POST /api/rooms/:id/integrations/slack
 * Connect Slack: store botToken + channelId and enable integration.
 * Validates the token with a cheap Slack API call (auth.test).
 */
router.post('/:id/integrations/slack', async (req, res) => {
    try {
        const botToken = String(req.body?.botToken || '').trim();
        const channelId = String(req.body?.channelId || '').trim();

        if (!botToken) {
            return res.status(400).json({ error: 'botToken is required' });
        }
        if (!channelId) {
            return res.status(400).json({ error: 'channelId is required' });
        }
        if (!/^xoxb-/.test(botToken)) {
            return res.status(400).json({ error: 'botToken must be a Slack Bot token (starts with xoxb-)' });
        }
        if (!/^[CG][A-Z0-9]{6,}$/.test(channelId)) {
            return res.status(400).json({ error: 'channelId must be a Slack channel ID (e.g. C012AB3CD)' });
        }

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to connect integrations' });
        }

        // Validate the token against Slack by calling auth.test
        let { default: axios } = await import('axios').catch(() => ({ default: null }));
        if (!axios) {
            // axios is always available as a CJS dep — import only on this path
            const m = await import('axios');
            axios = m.default ?? m;
        }
        try {
            const auth = await axios.post(
                'https://slack.com/api/auth.test',
                {},
                {
                    headers: {
                        Authorization: `Bearer ${botToken}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: 8_000,
                }
            );
            if (!auth?.data?.ok) {
                const slackErr = auth?.data?.error || 'invalid_auth';
                return res.status(400).json({ error: `Slack rejected the token: ${slackErr}` });
            }
        } catch (err) {
            return res.status(502).json({ error: `Could not reach Slack to validate token: ${err?.message || err}` });
        }

        room.integrations = room.integrations ?? {};
        room.integrations.slack = {
            enabled: true,
            botToken,
            channelId,
            connectedBy: req.userId,
            connectedAt: new Date(),
        };
        await room.save();

        res.status(201).json({ ok: true, channelId, connectedBy: req.userId });
    } catch (err) {
        console.error('[rooms/slack] connect error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

/**
 * DELETE /api/rooms/:id/integrations/slack
 * Disconnect Slack: wipe token and disable integration.
 */
router.delete('/:id/integrations/slack', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to remove integrations' });
        }

        room.integrations = room.integrations ?? {};
        room.integrations.slack = {
            enabled: false,
            botToken: '',
            channelId: '',
            connectedBy: '',
            connectedAt: null,
        };
        await room.save();

        res.json({ ok: true });
    } catch (err) {
        console.error('[rooms/slack] disconnect error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

/**
 * POST /api/rooms/:id/share
 * Manual share endpoint: posts last artifact / summary to the connected Slack channel.
 * Accepts optional { note } in body.
 */
router.post('/:id/share', async (req, res) => {
    try {
        const note = String(req.body?.note || '').trim().slice(0, 300);
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const slack = room.integrations?.slack || {};
        if (!slack.enabled || !String(slack.botToken || '').trim()) {
            return res.status(409).json({ error: 'Slack not connected for this room. Connect via POST /integrations/slack first.' });
        }

        // Grab the most recent humanly-readable artifact or message
        const [lastArtifact, lastMsg] = await Promise.all([
            RoomArtifact.findOne({ roomId: req.params.id })
                .sort({ updatedAt: -1 })
                .lean(),
            RoomMessage.findOne({ roomId: req.params.id, isAI: false })
                .sort({ createdAt: -1 })
                .lean(),
        ]);

        // eslint-disable-next-line prefer-destructuring
        const rawContent = lastArtifact?.title
            ? `${lastArtifact.title}`
            : String(lastMsg?.content || room.purpose || 'Partage Hackit').slice(0, 500);
        const text = buildSlackShareText({ roomName: room.name, summary: rawContent, note });

        const sent = await postSlackMessage({
            botToken: slack.botToken,
            channelId: slack.channelId,
            text,
        });

        res.json({ ok: true, channel: sent.channel, ts: sent.ts });
    } catch (err) {
        console.error('[rooms/share] error:', err);
        if (!res.headersSent) {
            res.status(502).json({ error: err?.message || 'Share failed' });
        }
    }
});

// ── Integrations: Notion ──────────────────────────────────────────────────────

/**
 * GET /api/rooms/:id/integrations/notion
 * Returns Notion integration status (token masked).
 */
router.get('/:id/integrations/notion', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }
        const notion = room.integrations?.notion || {};
        res.json({
            enabled: Boolean(notion.enabled),
            connected: Boolean(notion.apiToken),
            parentPageId: notion.parentPageId || '',
            connectedBy: notion.connectedBy || '',
            connectedAt: notion.connectedAt || null,
        });
    } catch (err) {
        console.error('[rooms/notion] status error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

/**
 * POST /api/rooms/:id/integrations/notion
 * Connect Notion: store apiToken + parentPageId.
 * Validates the token with a Notion search call.
 */
router.post('/:id/integrations/notion', async (req, res) => {
    try {
        const apiToken = String(req.body?.apiToken || '').trim();
        const parentPageId = String(req.body?.parentPageId || '').trim();

        if (!apiToken) {
            return res.status(400).json({ error: 'apiToken is required' });
        }
        if (!parentPageId) {
            return res.status(400).json({ error: 'parentPageId is required' });
        }
        if (!/^(secret_|ntn_)/.test(apiToken)) {
            return res.status(400).json({
                error: 'apiToken must be a Notion integration token (starts with secret_ or ntn_)',
            });
        }

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to connect integrations' });
        }

        try {
            await validateNotionToken(apiToken);
        } catch (err) {
            return res.status(400).json({ error: `Notion rejected the token: ${err?.message || err}` });
        }

        room.integrations = room.integrations ?? {};
        room.integrations.notion = {
            enabled: true,
            apiToken,
            parentPageId,
            connectedBy: req.userId,
            connectedAt: new Date(),
        };
        await room.save();

        res.status(201).json({ ok: true, parentPageId, connectedBy: req.userId });
    } catch (err) {
        console.error('[rooms/notion] connect error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

/**
 * DELETE /api/rooms/:id/integrations/notion
 * Disconnect Notion: wipe token and disable integration.
 */
router.delete('/:id/integrations/notion', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to remove integrations' });
        }

        room.integrations = room.integrations ?? {};
        room.integrations.notion = {
            enabled: false,
            apiToken: '',
            parentPageId: '',
            connectedBy: '',
            connectedAt: null,
        };
        await room.save();

        res.json({ ok: true });
    } catch (err) {
        console.error('[rooms/notion] disconnect error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

export default router;
