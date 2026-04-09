/**
 * rooms.js — REST API for Salons (rooms).
 *
 * All routes require the x-user-id header.
 * x-display-name is optional — defaults to "User_<last4>".
 *
 * Routes:
 *   GET    /api/rooms                              – list rooms the caller belongs to
 *   POST   /api/rooms                              – create a room (dm or group)
 *   GET    /api/rooms/:id/messages                 – get last 100 messages
 *   POST   /api/rooms/:id/messages                 – send a message (auto-triggers AI if @ia)
 *   PATCH  /api/rooms/:id/directives               – update AI directives for the room
 *   POST   /api/rooms/:id/messages/:msgId/challenge – add a challenge to a document message
 *   GET    /api/rooms/:id/members                  – list members (with online presence)
 *   POST   /api/rooms/:id/members                  – add a member to the room
 *   DELETE /api/rooms/:id/members/:userId          – remove a member from the room
 *   GET    /api/rooms/:id/invite                   – get shareable invite link
 *   POST   /api/rooms/:id/documents                – attach a document to the room
 */

import express from 'express';
import mongoose from 'mongoose';
import Room from '../models/Room.js';
import RoomMessage from '../models/RoomMessage.js';
import { triggerRoomAI } from '../services/roomGemini.js';
import { broadcastRoomMessage, broadcastRoomChallenge, getOnlineUserIds } from '../services/roomWS.js';

const router = express.Router();

// ── Middleware ───────────────────────────────────────────────────────────────

router.use((req, res, next) => {
    if (mongoose.connection.readyState !== 1) {
        return res.status(503).json({ error: 'Database not available. Set MONGODB_URI on the server.' });
    }
    const userId = req.headers['x-user-id'];
    if (!userId) return res.status(401).json({ error: 'x-user-id header required' });
    req.userId = userId;
    req.displayName = req.headers['x-display-name'] || `User_${userId.slice(-6)}`;
    next();
});

// ── GET /api/rooms ───────────────────────────────────────────────────────────

router.get('/', async (req, res) => {
    try {
        const rooms = await Room.find({ 'members.userId': req.userId })
            .sort({ updatedAt: -1 })
            .lean();
        res.json({ rooms });
    } catch (err) {
        console.error('[rooms] list error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── POST /api/rooms ──────────────────────────────────────────────────────────

router.post('/', async (req, res) => {
    try {
        const { name, type = 'group', members = [] } = req.body;

        if (!['dm', 'group'].includes(type)) {
            return res.status(400).json({ error: 'type must be "dm" or "group"' });
        }

        // Always include the creator; deduplicate if creator is listed in members too
        const allMembers = [
            { userId: req.userId, displayName: req.displayName },
            ...members.filter(
                (m) => m.userId && m.userId !== req.userId
            ),
        ];

        const room = await Room.create({
            name: name?.trim() || (type === 'group' ? 'Nouveau salon' : undefined),
            type,
            members: allMembers,
        });

        res.status(201).json({ room });
    } catch (err) {
        console.error('[rooms] create error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── GET /api/rooms/:id/messages ──────────────────────────────────────────────

router.get('/:id/messages', async (req, res) => {
    try {
        const room = await Room.findById(req.params.id).lean();
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        const messages = await RoomMessage.find({ roomId: req.params.id })
            .sort({ createdAt: 1 })
            .limit(100)
            .lean();

        res.json({ messages, room });
    } catch (err) {
        console.error('[rooms] messages error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── POST /api/rooms/:id/messages ─────────────────────────────────────────────

router.post('/:id/messages', async (req, res) => {
    try {
        const { content } = req.body;
        if (!content?.trim()) {
            return res.status(400).json({ error: 'content is required' });
        }

        const room = await Room.findById(req.params.id);
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        // Persist the human message
        const msg = await RoomMessage.create({
            roomId: room._id,
            senderId: req.userId,
            senderName: req.displayName,
            isAI: false,
            content: content.trim(),
            type: 'text',
        });

        // Broadcast to all WS subscribers in this room
        broadcastRoomMessage(req.params.id, msg.toObject());

        console.log(`[rooms] message saved id=${msg._id} room=${req.params.id} sender=${req.userId}`);

        // Update room timestamp so list sorts correctly
        room.updatedAt = new Date();
        await room.save();

        // Respond immediately so the sender doesn't wait for AI
        res.status(201).json({ message: msg });

        // If the user mentioned @ia (any case), trigger the AI colleague asynchronously
        if (/@ia\b/i.test(content)) {
            console.log(`[rooms] @ia detected — loading history for room=${req.params.id}`);
            const recent = await RoomMessage.find({ roomId: room._id })
                .sort({ createdAt: -1 })
                .limit(MAX_HISTORY_FOR_AI)
                .lean();
            console.log(`[rooms] @ia trigger — ${recent.length} messages in history, calling triggerRoomAI`);
            triggerRoomAI(room.toObject(), recent.reverse(), req.params.id).catch(
                (e) => console.error('[rooms] AI trigger error:', e)
            );
        }
    } catch (err) {
        console.error('[rooms] send message error:', err);
        if (!res.headersSent) res.status(500).json({ error: 'Internal server error' });
    }
});

const MAX_HISTORY_FOR_AI = 20;

// ── PATCH /api/rooms/:id/directives ─────────────────────────────────────────

router.patch('/:id/directives', async (req, res) => {
    try {
        const { directives } = req.body;
        if (typeof directives !== 'string') {
            return res.status(400).json({ error: 'directives must be a string' });
        }

        const room = await Room.findById(req.params.id);
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        room.aiDirectives = directives.slice(0, 2000);
        await room.save();

        res.json({ room });
    } catch (err) {
        console.error('[rooms] directives error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── POST /api/rooms/:id/messages/:msgId/challenge ────────────────────────────

router.post('/:id/messages/:msgId/challenge', async (req, res) => {
    try {
        const { content } = req.body;
        if (!content?.trim()) {
            return res.status(400).json({ error: 'content is required' });
        }

        const room = await Room.findById(req.params.id).lean();
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        const roomMsg = await RoomMessage.findById(req.params.msgId);
        if (!roomMsg || roomMsg.roomId.toString() !== req.params.id) {
            return res.status(404).json({ error: 'Message not found' });
        }

        roomMsg.challenges.push({
            userId: req.userId,
            userName: req.displayName,
            content: content.trim(),
        });
        await roomMsg.save();

        const savedChallenge = roomMsg.challenges[roomMsg.challenges.length - 1];
        broadcastRoomChallenge(req.params.id, req.params.msgId, savedChallenge.toObject());

        res.status(201).json({ challenge: savedChallenge });
    } catch (err) {
        console.error('[rooms] challenge error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── GET /api/rooms/:id/members ───────────────────────────────────────────────

router.get('/:id/members', async (req, res) => {
    try {
        const room = await Room.findById(req.params.id).lean();
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        const onlineIds = getOnlineUserIds(req.params.id);
        const members = room.members.map((m) => ({
            ...m,
            online: onlineIds.includes(m.userId),
        }));

        res.json({ members, onlineCount: onlineIds.length });
    } catch (err) {
        console.error('[rooms] members error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── POST /api/rooms/:id/members ──────────────────────────────────────────────

router.post('/:id/members', async (req, res) => {
    try {
        const { userId, displayName } = req.body;
        if (!userId?.trim()) {
            return res.status(400).json({ error: 'userId is required' });
        }

        const room = await Room.findById(req.params.id);
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isCallerMember = room.members.some((m) => m.userId === req.userId);
        if (!isCallerMember) return res.status(403).json({ error: 'Not a member of this room' });

        const alreadyMember = room.members.some((m) => m.userId === userId.trim());
        if (alreadyMember) {
            return res.status(409).json({ error: 'User is already a member' });
        }

        room.members.push({
            userId: userId.trim(),
            displayName: displayName?.trim() || `User_${userId.trim().slice(-6)}`,
        });
        await room.save();

        res.status(201).json({ room });
    } catch (err) {
        console.error('[rooms] add member error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── DELETE /api/rooms/:id/members/:uid ───────────────────────────────────────

router.delete('/:id/members/:uid', async (req, res) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isCallerMember = room.members.some((m) => m.userId === req.userId);
        if (!isCallerMember) return res.status(403).json({ error: 'Not a member of this room' });

        // Prevent removing the last member
        if (room.members.length <= 1) {
            return res.status(400).json({ error: 'Cannot remove the last member' });
        }

        room.members = room.members.filter((m) => m.userId !== req.params.uid);
        await room.save();

        res.json({ room });
    } catch (err) {
        console.error('[rooms] remove member error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── GET /api/rooms/:id/invite ────────────────────────────────────────────────

const APP_BASE_URL = process.env.APP_BASE_URL || 'https://saadelaboudi.github.io/hackit-mvp';

router.get('/:id/invite', async (req, res) => {
    try {
        const room = await Room.findById(req.params.id).lean();
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        const link = `${APP_BASE_URL}/#/salon/${req.params.id}`;
        res.json({ link, roomName: room.name });
    } catch (err) {
        console.error('[rooms] invite error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── POST /api/rooms/:id/documents ────────────────────────────────────────────

router.post('/:id/documents', async (req, res) => {
    try {
        const { title, content } = req.body;
        if (!content?.trim()) {
            return res.status(400).json({ error: 'content is required' });
        }

        const room = await Room.findById(req.params.id);
        if (!room) return res.status(404).json({ error: 'Room not found' });

        const isMember = room.members.some((m) => m.userId === req.userId);
        if (!isMember) return res.status(403).json({ error: 'Not a member of this room' });

        const msg = await RoomMessage.create({
            roomId: room._id,
            senderId: req.userId,
            senderName: req.displayName,
            isAI: false,
            content: content.trim(),
            type: 'document',
            documentTitle: title?.trim() || 'Document partagé',
        });

        broadcastRoomMessage(req.params.id, msg.toObject());

        room.updatedAt = new Date();
        await room.save();

        res.status(201).json({ message: msg });
    } catch (err) {
        console.error('[rooms] document error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

export default router;
