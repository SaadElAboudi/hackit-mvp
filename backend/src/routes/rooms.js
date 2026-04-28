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
import RoomShareHistory from '../models/RoomShareHistory.js';
import WorkspaceBlock from '../models/WorkspaceBlock.js';
import WorkspaceComment from '../models/WorkspaceComment.js';
import WorkspaceDecision from '../models/WorkspaceDecision.js';
import WorkspaceMilestone from '../models/WorkspaceMilestone.js';
import WorkspacePage from '../models/WorkspacePage.js';
import WorkspaceTask from '../models/WorkspaceTask.js';
import {
    createRoomArtifact,
    parseRoomCommand,
    reviseRoomArtifact,
    suggestRoomBriefIfNeeded,
    triggerRoomAutomation,
    suggestRoomSynthesisIfNeeded,
} from '../services/roomOrchestrator.js';
import { generateWithGemini as generateWithGeminiShared } from '../services/gemini.js';
import { discoverNotionPages, validateNotionToken } from '../services/notion.js';
import { executeWithRetry, getExportConnector } from '../services/exportConnectors.js';
import {
    broadcastRoomChallenge,
    broadcastCommentCreated,
    broadcastCommentResolved,
    broadcastPageBlockUpdated,
    broadcastRoomDecisionCreated,
    broadcastRoomMessage,
    getOnlineUserIds,
} from '../services/roomWS.js';
import {
    validateAddMemberPayload,
    validateAiFeedbackPayload,
    validateArtifactCommentPayload,
    validateArtifactRejectPayload,
    validateArtifactStatusPayload,
    validateBody,
    validateChallengePayload,
    validateConnectNotionPayload,
    validateConnectSlackPayload,
    validateCreateArtifactPayload,
    validateCreateDocumentPayload,
    validateCreateMemoryPayload,
    validateCreateMilestonePayload,
    validateCreateMissionPayload,
    validateCreateRoomPayload,
    validateCreateWorkspaceBlockPayload,
    validateCreateWorkspaceCommentPayload,
    validateCreateWorkspaceDecisionPayload,
    validateCreateWorkspacePagePayload,
    validateCreateWorkspaceTaskPayload,
    validateConvertDecisionToTasksPayload,
    validateDirectivesPayload,
    validateDiscoverNotionPagesPayload,
    validateResolveCommentPayload,
    validateResolveWorkspaceCommentPayload,
    validateExtractWorkspaceDecisionsPayload,
    validateReorderWorkspaceBlocksPayload,
    validateReviseArtifactPayload,
    validateRoomSearchPayload,
    validateShareHistoryQuery,
    validateSharePayload,
    validateSendMessagePayload,
    validateUpdateWorkspaceBlockPayload,
    validateUpdateWorkspacePagePayload,
    validateUpdateWorkspaceTaskPayload,
} from '../middleware/validation.js';
import DOMAIN_TEMPLATES, { getTemplateById } from '../config/domainTemplates.js';

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

function workspacePageSummary(page) {
    const json = page?.toObject ? page.toObject() : page;
    return {
        ...json,
    };
}

function workspaceBlockSummary(block) {
    const json = block?.toObject ? block.toObject() : block;
    return {
        ...json,
    };
}

function workspaceCommentSummary(comment) {
    const json = comment?.toObject ? comment.toObject() : comment;
    return {
        ...json,
    };
}

function workspaceDecisionSummary(decision) {
    const json = decision?.toObject ? decision.toObject() : decision;
    return {
        ...json,
    };
}

function workspaceTaskSummary(task) {
    const json = task?.toObject ? task.toObject() : task;
    return {
        ...json,
    };
}

function workspaceMilestoneSummary(milestone) {
    const json = milestone?.toObject ? milestone.toObject() : milestone;
    return {
        ...json,
    };
}

function extractJsonObject(text) {
    const raw = String(text || '').trim();
    if (!raw) return null;
    try {
        return JSON.parse(raw);
    } catch (_) {
        // continue to fenced block extraction
    }

    const fenced = raw.match(/```json\s*([\s\S]*?)```/i) || raw.match(/```\s*([\s\S]*?)```/i);
    if (fenced?.[1]) {
        try {
            return JSON.parse(String(fenced[1]).trim());
        } catch (_) {
            // keep searching below
        }
    }

    const firstBrace = raw.indexOf('{');
    const lastBrace = raw.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
        const candidate = raw.slice(firstBrace, lastBrace + 1);
        try {
            return JSON.parse(candidate);
        } catch (_) {
            return null;
        }
    }

    return null;
}

function fallbackExtractDecisionsFromMessages(messages, maxDecisions = 5, maxTasksPerDecision = 4) {
    const lines = messages
        .map((msg) => String(msg?.content || '').trim())
        .filter(Boolean)
        .slice(0, 20);

    const seeds = lines.slice(0, Math.max(1, Math.min(maxDecisions, lines.length || 1)));
    return seeds.map((line, idx) => {
        const compact = line.replace(/\s+/g, ' ').slice(0, 180);
        return {
            title: `Decision ${idx + 1}: ${compact.slice(0, 80)}`,
            summary: `Decision derivee du contexte recent: ${compact}`.slice(0, 500),
            tasks: [
                { title: `Clarifier l'objectif pour: ${compact.slice(0, 60)}`.slice(0, 180), description: '' },
                { title: `Definir le proprietaire et la deadline`, description: '' },
                { title: `Valider en reunion d'equipe`, description: '' },
            ].slice(0, maxTasksPerDecision),
        };
    });
}

async function executeDecisionExtraction(req, res, next, { missionIdOverride = '' } = {}) {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { recentLimit, maxDecisions, maxTasksPerDecision, persist } = req.validatedBody;
        const missionId = String(missionIdOverride || req.validatedBody?.missionId || '').trim();

        const recentMessages = await RoomMessage.find({ roomId: req.params.id })
            .sort({ createdAt: -1 })
            .limit(recentLimit)
            .lean();

        const chronology = recentMessages
            .slice()
            .reverse()
            .map((msg) => {
                const sender = msg?.isAI ? 'AI' : String(msg?.senderName || 'Member').slice(0, 40);
                const content = String(msg?.content || '').replace(/\s+/g, ' ').trim().slice(0, 400);
                return `${sender}: ${content}`;
            })
            .filter((line) => line.length > 4)
            .slice(-recentLimit);

        let missionContext = null;
        if (missionId) {
            const mission = await RoomMission.findOne({
                _id: missionId,
                roomId: req.params.id,
            }).lean();

            if (!mission && missionIdOverride) {
                return res.status(404).json({ error: 'Mission not found' });
            }

            if (mission) {
                const resultMessage = mission.resultMessageId
                    ? await RoomMessage.findOne({
                        _id: mission.resultMessageId,
                        roomId: req.params.id,
                    }).lean()
                    : null;
                const missionPrompt = String(mission.prompt || '').replace(/\s+/g, ' ').trim().slice(0, 600);
                const missionResult = String(resultMessage?.content || '').replace(/\s+/g, ' ').trim().slice(0, 900);
                missionContext = {
                    missionId: String(mission._id),
                    prompt: missionPrompt,
                    result: missionResult,
                };
            }
        }

        const contextLines = [];
        if (missionContext?.prompt) {
            contextLines.push(`Mission prompt: ${missionContext.prompt}`);
        }
        if (missionContext?.result) {
            contextLines.push(`Mission result: ${missionContext.result}`);
        }
        const extractionLines = [...contextLines, ...chronology].slice(-Math.max(recentLimit, 10));

        let extracted = [];
        if (extractionLines.length) {
            const prompt = [
                'Tu es un facilitateur operationnel.',
                'A partir de la conversation suivante, extrais des decisions actionnables et des taches associees.',
                `Contraintes: max ${maxDecisions} decisions, max ${maxTasksPerDecision} taches par decision.`,
                'Reponds STRICTEMENT en JSON valide, sans texte hors JSON.',
                'Schema:',
                '{"decisions":[{"title":"...","summary":"...","tasks":[{"title":"...","description":"..."}]}]}',
                'La reponse doit etre en francais, concrete, sans formulations generiques.',
                '',
                'Conversation:',
                extractionLines.join('\n'),
            ].join('\n');

            try {
                const llmText = await generateWithGeminiShared(prompt, 1400, {
                    model: 'models/gemini-2.0-flash-lite',
                    preferModels: ['models/gemini-2.0-flash-lite', 'models/gemini-2.0-flash'],
                    timeoutMs: 25000,
                    temperature: 0.25,
                    maxAttemptsPerModel: 2,
                    allowQualityRepair: true,
                });
                const parsed = extractJsonObject(llmText);
                const list = Array.isArray(parsed?.decisions) ? parsed.decisions : [];
                extracted = list
                    .map((entry) => ({
                        title: String(entry?.title || '').trim().slice(0, 180),
                        summary: String(entry?.summary || '').trim().slice(0, 2000),
                        tasks: (Array.isArray(entry?.tasks) ? entry.tasks : [])
                            .map((task) => ({
                                title: String(task?.title || '').trim().slice(0, 180),
                                description: String(task?.description || '').trim().slice(0, 2000),
                            }))
                            .filter((task) => task.title)
                            .slice(0, maxTasksPerDecision),
                    }))
                    .filter((entry) => entry.title)
                    .slice(0, maxDecisions);
            } catch (extractErr) {
                console.warn('[rooms] decisions extract fallback:', extractErr?.message || extractErr);
            }
        }

        if (!extracted.length) {
            const fallbackSource = [
                ...(missionContext?.prompt ? [{ content: missionContext.prompt }] : []),
                ...(missionContext?.result ? [{ content: missionContext.result }] : []),
                ...recentMessages,
            ];
            extracted = fallbackExtractDecisionsFromMessages(fallbackSource, maxDecisions, maxTasksPerDecision)
                .slice(0, maxDecisions);
        }

        if (!persist) {
            return res.json({
                extracted,
                persisted: false,
                sourceMessageCount: extractionLines.length,
                missionContext: missionContext ? { missionId: missionContext.missionId } : null,
            });
        }

        const createdDecisions = [];
        const createdTasks = [];
        for (const item of extracted) {
            const decision = await WorkspaceDecision.create({
                roomId: req.params.id,
                sourceType: missionContext ? 'mission' : 'message',
                sourceId: missionContext?.missionId || '',
                title: item.title,
                summary: item.summary,
                createdBy: req.userId,
                createdByName: req.displayName,
            });
            createdDecisions.push(decision);

            if (item.tasks?.length) {
                const tasks = await WorkspaceTask.insertMany(
                    item.tasks.map((task) => ({
                        roomId: req.params.id,
                        decisionId: decision._id,
                        title: task.title,
                        description: task.description || '',
                        createdBy: req.userId,
                        createdByName: req.displayName,
                        lastUpdatedBy: req.userId,
                        lastUpdatedByName: req.displayName,
                    }))
                );
                createdTasks.push(...tasks);
            }

            decision.convertedAt = new Date();
            await decision.save();

            broadcastRoomDecisionCreated(req.params.id, {
                type: 'workspace_decision_extracted',
                data: {
                    decisionId: String(decision._id),
                    title: decision.title,
                    sourceType: decision.sourceType,
                },
                authorId: req.userId,
                authorName: req.displayName,
                createdAt: decision.createdAt,
            });
        }

        room.lastActivityAt = new Date();
        await room.save();

        return res.status(201).json({
            extracted,
            persisted: true,
            sourceMessageCount: extractionLines.length,
            missionContext: missionContext ? { missionId: missionContext.missionId } : null,
            decisions: createdDecisions.map((decision) => workspaceDecisionSummary(decision)),
            tasks: createdTasks.map((task) => workspaceTaskSummary(task)),
        });
    } catch (err) {
        return next(err);
    }
}

function tooManyRequestsError(message = 'Too many requests') {
    const err = new Error(message);
    err.status = 429;
    err.code = 'RATE_LIMITED';
    err.details = null;
    return err;
}

async function buildShareSummary(room, artifactId = '') {
    const roomId = String(room?._id || room?.id || '');
    const artifactFilter = artifactId ? { _id: artifactId, roomId } : { roomId };
    const [artifact, lastMsg] = await Promise.all([
        RoomArtifact.findOne(artifactFilter).sort({ updatedAt: -1 }).lean(),
        RoomMessage.findOne({ roomId, isAI: false }).sort({ createdAt: -1 }).lean(),
    ]);

    const summary = artifact?.title
        ? String(artifact.title)
        : String(lastMsg?.content || room?.purpose || 'Partage Hackit').slice(0, 500);

    return {
        summary,
        artifactId: artifact?._id || null,
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

/**
 * GET /api/rooms/templates
 * Returns the list of domain template packs (no auth required for the list).
 */
router.get('/templates', (_req, res) => {
    res.json({ templates: DOMAIN_TEMPLATES.map(({ id, version, name, emoji, description, purpose }) => ({ id, version, name, emoji, description, purpose })) });
});

function toPercent(part, total) {
    if (!total) return 0;
    return Math.round((part / total) * 1000) / 10;
}

function parseSinceDays(raw) {
    if (raw === undefined || raw === null || raw === '') return null;
    const value = Number.parseInt(String(raw), 10);
    if (!Number.isFinite(value) || value <= 0) return null;
    if (![7, 30, 90].includes(value)) return null;
    return value;
}

function parseGroupBy(raw) {
    const value = String(raw || 'template').trim().toLowerCase();
    if (!['template', 'version'].includes(value)) return null;
    return value;
}

function buildTemplateInsights(stats) {
    const active = stats.filter((s) => s.roomsCreated > 0);

    const byFeedback = [...active].sort((a, b) => {
        if (b.feedbackAverage !== a.feedbackAverage) {
            return b.feedbackAverage - a.feedbackAverage;
        }
        return b.roomsCreated - a.roomsCreated;
    });

    const byD7 = [...active].sort((a, b) => {
        if (b.d7RetentionRate !== a.d7RetentionRate) {
            return b.d7RetentionRate - a.d7RetentionRate;
        }
        return b.roomsCreated - a.roomsCreated;
    });

    const underperformingTemplates = [...active]
        .filter(
            (s) =>
                s.roomsCreated >= 2 &&
                (s.feedbackAverage < 0 || s.d7RetentionRate < 20)
        )
        .sort((a, b) => {
            if (a.feedbackAverage !== b.feedbackAverage) {
                return a.feedbackAverage - b.feedbackAverage;
            }
            return a.d7RetentionRate - b.d7RetentionRate;
        })
        .slice(0, 3);

    return {
        topByFeedback: byFeedback[0] || null,
        topByD7Retention: byD7[0] || null,
        underperformingTemplates,
    };
}

/**
 * GET /api/rooms/templates/stats
 * Returns usage and quality metrics by template.
 */
router.get('/templates/stats', async (req, res) => {
    try {
        const rawSinceDays = req.query?.sinceDays;
        const hasSinceDays =
            rawSinceDays !== undefined && rawSinceDays !== null && rawSinceDays !== '';
        const sinceDays = parseSinceDays(rawSinceDays);
        if (hasSinceDays && !sinceDays) {
            return res
                .status(400)
                .json({ error: 'sinceDays must be one of 7, 30, 90' });
        }

        const cutoffDate = sinceDays
            ? new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000)
            : null;

        const groupBy = parseGroupBy(req.query?.groupBy);
        if (!groupBy) {
            return res
                .status(400)
                .json({ error: 'groupBy must be either template or version' });
        }

        const templateIds = DOMAIN_TEMPLATES.map((t) => t.id);
        const templateById = new Map(DOMAIN_TEMPLATES.map((t) => [t.id, t]));
        const keyFor = (templateId, templateVersion) =>
            groupBy === 'version'
                ? `${String(templateId || '')}:${String(templateVersion || '')}`
                : String(templateId || '');

        const orderedKeys = [];
        const statsByTemplate = new Map(
            DOMAIN_TEMPLATES.map((t) => {
                const templateVersion = String(t.version || 'v1');
                const key = keyFor(t.id, templateVersion);
                orderedKeys.push(key);
                return [
                    key,
                    {
                        templateId: t.id,
                        templateVersion: groupBy === 'version' ? templateVersion : null,
                        name: t.name,
                        emoji: t.emoji,
                        description: t.description,
                        roomsCreated: 0,
                        messagesSent: 0,
                        feedbackUp: 0,
                        feedbackDown: 0,
                        feedbackAverage: 0,
                        d1RetainedRooms: 0,
                        d7RetainedRooms: 0,
                        d1RetentionRate: 0,
                        d7RetentionRate: 0,
                    },
                ];
            })
        );

        const roomQuery = {
            templateId: { $in: templateIds },
            ...(cutoffDate ? { createdAt: { $gte: cutoffDate } } : {}),
        };

        const rooms = await Room.find(roomQuery, {
            _id: 1,
            templateId: 1,
            templateVersion: 1,
            createdAt: 1,
        }).lean();

        const roomById = new Map();
        for (const room of rooms) {
            const roomId = String(room._id);
            const templateId = String(room.templateId || '');
            const defaultVersion = templateById.get(templateId)?.version || 'v1';
            const templateVersion = String(room.templateVersion || defaultVersion);
            const createdAt = new Date(room.createdAt || Date.now());
            const key = keyFor(templateId, templateVersion);

            if (!statsByTemplate.has(key)) {
                const templateMeta = templateById.get(templateId);
                statsByTemplate.set(key, {
                    templateId,
                    templateVersion: groupBy === 'version' ? templateVersion : null,
                    name: templateMeta?.name || templateId || 'Template',
                    emoji: templateMeta?.emoji || '🧩',
                    description: templateMeta?.description || '',
                    roomsCreated: 0,
                    messagesSent: 0,
                    feedbackUp: 0,
                    feedbackDown: 0,
                    feedbackAverage: 0,
                    d1RetainedRooms: 0,
                    d7RetainedRooms: 0,
                    d1RetentionRate: 0,
                    d7RetentionRate: 0,
                });
                orderedKeys.push(key);
            }
            roomById.set(roomId, { key, createdAt });
            statsByTemplate.get(key).roomsCreated += 1;
        }

        const roomIds = Array.from(roomById.keys());
        if (roomIds.length > 0) {
            const messageQuery = {
                roomId: { $in: roomIds },
                ...(cutoffDate ? { createdAt: { $gte: cutoffDate } } : {}),
            };
            const messages = await RoomMessage.find(messageQuery, {
                roomId: 1,
                createdAt: 1,
                feedback: 1,
            }).lean();

            const roomHasD1 = new Set();
            const roomHasD7 = new Set();

            for (const msg of messages) {
                const roomId = String(msg.roomId);
                const roomMeta = roomById.get(roomId);
                if (!roomMeta) continue;

                const templateStats = statsByTemplate.get(roomMeta.key);
                if (!templateStats) continue;

                templateStats.messagesSent += 1;

                const msgCreatedAt = new Date(msg.createdAt || Date.now());
                const ageMs = msgCreatedAt.getTime() - roomMeta.createdAt.getTime();
                if (ageMs >= 24 * 60 * 60 * 1000) roomHasD1.add(roomId);
                if (ageMs >= 7 * 24 * 60 * 60 * 1000) roomHasD7.add(roomId);

                for (const vote of Array.isArray(msg.feedback) ? msg.feedback : []) {
                    if (vote?.rating === 1) templateStats.feedbackUp += 1;
                    if (vote?.rating === -1) templateStats.feedbackDown += 1;
                }
            }

            for (const [roomId, roomMeta] of roomById.entries()) {
                const templateStats = statsByTemplate.get(roomMeta.key);
                if (!templateStats) continue;
                if (roomHasD1.has(roomId)) templateStats.d1RetainedRooms += 1;
                if (roomHasD7.has(roomId)) templateStats.d7RetainedRooms += 1;
            }
        }

        const stats = orderedKeys.map((key) => {
            const s = statsByTemplate.get(key);
            const totalFeedback = s.feedbackUp + s.feedbackDown;
            const feedbackAverage = totalFeedback
                ? Math.round(((s.feedbackUp - s.feedbackDown) / totalFeedback) * 100) / 100
                : 0;
            return {
                ...s,
                feedbackAverage,
                d1RetentionRate: toPercent(s.d1RetainedRooms, s.roomsCreated),
                d7RetentionRate: toPercent(s.d7RetainedRooms, s.roomsCreated),
            };
        });

        const insights = buildTemplateInsights(stats);
        res.json({
            stats,
            insights,
            sinceDays: sinceDays || null,
            groupBy,
            generatedAt: new Date().toISOString(),
        });
    } catch (err) {
        console.error('[rooms] template stats error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

router.post('/', validateBody(validateCreateRoomPayload), async (req, res, next) => {
    try {
        const { name, type, members, purpose, visibility, templateId } = req.validatedBody;

        // Apply domain template directives if a valid templateId was supplied
        const template = templateId ? getTemplateById(templateId) : null;
        const resolvedPurpose = (purpose || template?.purpose || '').slice(0, 240);
        const resolvedDirectives = template ? template.aiDirectives : '';

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
            purpose: resolvedPurpose,
            templateId: template?.id || '',
            templateVersion: template?.version || '',
            visibility,
            ownerId: req.userId,
            members: allMembers,
            lastActivityAt: new Date(),
            aiDirectives: resolvedDirectives,
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

router.get('/:id/pages', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const pages = await WorkspacePage.find({ roomId: req.params.id })
            .sort({ updatedAt: -1 })
            .limit(120)
            .lean();

        res.json({ pages: pages.map((page) => workspacePageSummary(page)) });
    } catch (err) {
        next(err);
    }
});

router.post('/:id/pages', validateBody(validateCreateWorkspacePagePayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { title, icon, coverUrl, summary } = req.validatedBody;
        const page = await WorkspacePage.create({
            roomId: req.params.id,
            title,
            icon,
            coverUrl,
            summary,
            createdBy: req.userId,
            createdByName: req.displayName,
            lastEditedBy: req.userId,
            lastEditedByName: req.displayName,
            revision: 1,
        });

        room.lastActivityAt = new Date();
        await room.save();

        res.status(201).json({ page: workspacePageSummary(page) });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/pages/:pageId', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const blocks = await WorkspaceBlock.find({
            pageId: page._id,
            roomId: req.params.id,
        })
            .sort({ order: 1 })
            .lean();

        res.json({
            page: workspacePageSummary(page),
            blocks: blocks.map((block) => workspaceBlockSummary(block)),
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/pages/:pageId/state', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const [blocks, comments] = await Promise.all([
            WorkspaceBlock.find({
                pageId: page._id,
                roomId: req.params.id,
            })
                .sort({ order: 1 })
                .lean(),
            WorkspaceComment.find({
                pageId: page._id,
                roomId: req.params.id,
            })
                .sort({ createdAt: -1 })
                .limit(300)
                .lean(),
        ]);

        const latestVersion = blocks.reduce(
            (max, block) => Math.max(max, Number(block?.version || 1)),
            1
        );
        const requestedLastVersion = Number(req.query?.lastVersion || 0);
        const stale = Number.isFinite(requestedLastVersion)
            ? requestedLastVersion > 0 && requestedLastVersion !== latestVersion
            : false;

        res.json({
            page: workspacePageSummary(page),
            blocks: blocks.map((block) => workspaceBlockSummary(block)),
            comments: comments.map((comment) => workspaceCommentSummary(comment)),
            lastVersion: latestVersion,
            stale,
        });
    } catch (err) {
        next(err);
    }
});

router.patch('/:id/pages/:pageId', validateBody(validateUpdateWorkspacePagePayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        Object.assign(page, req.validatedBody, {
            lastEditedBy: req.userId,
            lastEditedByName: req.displayName,
            revision: (Number(page.revision || 1) + 1),
        });
        await page.save();

        room.lastActivityAt = new Date();
        await room.save();

        res.json({ page: workspacePageSummary(page) });
    } catch (err) {
        next(err);
    }
});

router.delete('/:id/pages/:pageId', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const canDelete = isRoomOwner(room, req.userId) || String(page.createdBy) === String(req.userId);
        if (!canDelete) {
            return res.status(403).json({ error: 'Owner or page author required' });
        }

        await Promise.all([
            WorkspaceBlock.deleteMany({ pageId: page._id, roomId: req.params.id }),
            WorkspacePage.deleteOne({ _id: page._id }),
        ]);

        room.lastActivityAt = new Date();
        await room.save();

        res.json({ ok: true, pageId: String(page._id) });
    } catch (err) {
        next(err);
    }
});

router.post('/:id/pages/:pageId/blocks', validateBody(validateCreateWorkspaceBlockPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const last = await WorkspaceBlock.findOne({
            pageId: page._id,
            roomId: req.params.id,
        })
            .sort({ order: -1 })
            .lean();
        const order = Number(last?.order ?? -1) + 1;

        const { type, text, checked, attrs } = req.validatedBody;
        const block = await WorkspaceBlock.create({
            roomId: req.params.id,
            pageId: page._id,
            type,
            text,
            checked,
            attrs,
            order,
            version: 1,
            createdBy: req.userId,
            createdByName: req.displayName,
            updatedBy: req.userId,
            updatedByName: req.displayName,
        });

        page.lastEditedBy = req.userId;
        page.lastEditedByName = req.displayName;
        page.revision = Number(page.revision || 1) + 1;
        await page.save();

        room.lastActivityAt = new Date();
        await room.save();

        broadcastPageBlockUpdated(
            req.params.id,
            {
                action: 'created',
                pageId: String(page._id),
                block: workspaceBlockSummary(block),
                pageRevision: page.revision,
                lastVersion: Number(block.version || 1),
            },
            req.requestId || null
        );

        res.status(201).json({ block: workspaceBlockSummary(block), page: workspacePageSummary(page) });
    } catch (err) {
        next(err);
    }
});

router.patch('/:id/pages/:pageId/blocks/reorder', validateBody(validateReorderWorkspaceBlocksPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const { orders } = req.validatedBody;
        const blockIds = orders.map((entry) => entry.blockId);
        const uniqueBlockIds = new Set(blockIds);
        if (uniqueBlockIds.size !== blockIds.length) {
            return res.status(400).json({
                ok: false,
                code: 'BAD_REQUEST',
                message: 'orders contains duplicate blockId values',
                details: { field: 'orders' },
                requestId: req.requestId || null,
            });
        }
        const uniqueOrders = new Set(orders.map((entry) => entry.order));
        if (uniqueOrders.size !== orders.length) {
            return res.status(400).json({
                ok: false,
                code: 'BAD_REQUEST',
                message: 'orders contains duplicate order values',
                details: { field: 'orders' },
                requestId: req.requestId || null,
            });
        }

        const existing = await WorkspaceBlock.find({
            _id: { $in: blockIds },
            pageId: page._id,
            roomId: req.params.id,
        }).lean();
        if (existing.length !== blockIds.length) {
            return res.status(404).json({ error: 'One or more blocks were not found' });
        }

        await Promise.all(
            orders.map((entry) =>
                WorkspaceBlock.updateOne(
                    { _id: entry.blockId, pageId: page._id, roomId: req.params.id },
                    {
                        $set: {
                            order: entry.order,
                            updatedBy: req.userId,
                            updatedByName: req.displayName,
                        },
                        $inc: { version: 1 },
                    }
                )
            )
        );

        page.lastEditedBy = req.userId;
        page.lastEditedByName = req.displayName;
        page.revision = Number(page.revision || 1) + 1;
        await page.save();

        room.lastActivityAt = new Date();
        await room.save();

        const blocks = await WorkspaceBlock.find({
            pageId: page._id,
            roomId: req.params.id,
        })
            .sort({ order: 1 })
            .lean();
        const lastVersion = blocks.reduce(
            (max, block) => Math.max(max, Number(block?.version || 1)),
            1
        );

        broadcastPageBlockUpdated(
            req.params.id,
            {
                action: 'reordered',
                pageId: String(page._id),
                pageRevision: page.revision,
                lastVersion,
                blocks: blocks.map((block) => workspaceBlockSummary(block)),
            },
            req.requestId || null
        );

        res.json({
            blocks: blocks.map((block) => workspaceBlockSummary(block)),
            page: workspacePageSummary(page),
        });
    } catch (err) {
        next(err);
    }
});

router.patch('/:id/pages/:pageId/blocks/:blockId', validateBody(validateUpdateWorkspaceBlockPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const block = await WorkspaceBlock.findOne({
            _id: req.params.blockId,
            pageId: page._id,
            roomId: req.params.id,
        });
        if (!block) {
            return res.status(404).json({ error: 'Block not found' });
        }

        const { expectedVersion, ...nextValues } = req.validatedBody;

        if (
            Number.isInteger(expectedVersion)
            && Number(block.version || 1) !== expectedVersion
        ) {
            return res.status(409).json({
                ok: false,
                code: 'STALE_VERSION',
                message: 'Block has been updated by another client',
                details: {
                    expectedVersion,
                    currentVersion: Number(block.version || 1),
                    block: workspaceBlockSummary(block),
                },
                requestId: req.requestId || null,
            });
        }

        Object.assign(block, nextValues, {
            updatedBy: req.userId,
            updatedByName: req.displayName,
            version: Number(block.version || 1) + 1,
        });
        await block.save();

        page.lastEditedBy = req.userId;
        page.lastEditedByName = req.displayName;
        page.revision = Number(page.revision || 1) + 1;
        await page.save();

        room.lastActivityAt = new Date();
        await room.save();

        broadcastPageBlockUpdated(
            req.params.id,
            {
                action: 'updated',
                pageId: String(page._id),
                block: workspaceBlockSummary(block),
                pageRevision: page.revision,
                lastVersion: Number(block.version || 1),
            },
            req.requestId || null
        );

        res.json({ block: workspaceBlockSummary(block), page: workspacePageSummary(page) });
    } catch (err) {
        next(err);
    }
});

router.delete('/:id/pages/:pageId/blocks/:blockId', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const block = await WorkspaceBlock.findOne({
            _id: req.params.blockId,
            pageId: page._id,
            roomId: req.params.id,
        });
        if (!block) {
            return res.status(404).json({ error: 'Block not found' });
        }

        const removedOrder = block.order;
        await WorkspaceBlock.deleteOne({ _id: block._id });
        await WorkspaceBlock.updateMany(
            { pageId: page._id, roomId: req.params.id, order: { $gt: removedOrder } },
            { $inc: { order: -1 } }
        );

        page.lastEditedBy = req.userId;
        page.lastEditedByName = req.displayName;
        page.revision = Number(page.revision || 1) + 1;
        await page.save();

        room.lastActivityAt = new Date();
        await room.save();

        broadcastPageBlockUpdated(
            req.params.id,
            {
                action: 'deleted',
                pageId: String(page._id),
                blockId: String(block._id),
                pageRevision: page.revision,
            },
            req.requestId || null
        );

        res.json({ ok: true, blockId: String(block._id), page: workspacePageSummary(page) });
    } catch (err) {
        next(err);
    }
});

router.post('/:id/pages/:pageId/comments', validateBody(validateCreateWorkspaceCommentPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const { blockId, text } = req.validatedBody;
        const block = await WorkspaceBlock.findOne({
            _id: blockId,
            pageId: page._id,
            roomId: req.params.id,
        });
        if (!block) {
            return res.status(404).json({ error: 'Block not found' });
        }

        const comment = await WorkspaceComment.create({
            roomId: req.params.id,
            pageId: page._id,
            blockId: block._id,
            text,
            createdBy: req.userId,
            createdByName: req.displayName,
        });

        room.lastActivityAt = new Date();
        await room.save();

        broadcastCommentCreated(
            req.params.id,
            {
                pageId: String(page._id),
                blockId: String(block._id),
                comment: workspaceCommentSummary(comment),
            },
            req.requestId || null
        );

        res.status(201).json({ comment: workspaceCommentSummary(comment) });
    } catch (err) {
        next(err);
    }
});

router.patch('/:id/pages/:pageId/comments/:commentId', validateBody(validateResolveWorkspaceCommentPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const page = await WorkspacePage.findOne({
            _id: req.params.pageId,
            roomId: req.params.id,
        });
        if (!page) {
            return res.status(404).json({ error: 'Page not found' });
        }

        const comment = await WorkspaceComment.findOne({
            _id: req.params.commentId,
            pageId: page._id,
            roomId: req.params.id,
        });
        if (!comment) {
            return res.status(404).json({ error: 'Comment not found' });
        }

        const { resolved } = req.validatedBody;
        comment.resolved = resolved;
        if (resolved) {
            comment.resolvedAt = new Date();
            comment.resolvedBy = req.userId;
            comment.resolvedByName = req.displayName;
        } else {
            comment.resolvedAt = null;
            comment.resolvedBy = '';
            comment.resolvedByName = '';
        }
        await comment.save();

        room.lastActivityAt = new Date();
        await room.save();

        broadcastCommentResolved(
            req.params.id,
            {
                pageId: String(page._id),
                blockId: String(comment.blockId),
                comment: workspaceCommentSummary(comment),
            },
            req.requestId || null
        );

        res.json({ comment: workspaceCommentSummary(comment) });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/decisions', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const decisions = await WorkspaceDecision.find({ roomId: req.params.id })
            .sort({ createdAt: -1 })
            .limit(200)
            .lean();

        res.json({ decisions: decisions.map((decision) => workspaceDecisionSummary(decision)) });
    } catch (err) {
        next(err);
    }
});

router.post('/:id/decisions', validateBody(validateCreateWorkspaceDecisionPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { title, summary, sourceType, sourceId, pageId } = req.validatedBody;
        const decision = await WorkspaceDecision.create({
            roomId: req.params.id,
            pageId: pageId || null,
            sourceType,
            sourceId,
            title,
            summary,
            createdBy: req.userId,
            createdByName: req.displayName,
        });

        room.lastActivityAt = new Date();
        await room.save();

        broadcastRoomDecisionCreated(req.params.id, {
            type: 'workspace_decision',
            data: {
                decisionId: String(decision._id),
                title: decision.title,
                sourceType: decision.sourceType,
            },
            authorId: req.userId,
            authorName: req.displayName,
            createdAt: decision.createdAt,
        });

        res.status(201).json({ decision: workspaceDecisionSummary(decision) });
    } catch (err) {
        next(err);
    }
});

router.post('/:id/decisions/extract', validateBody(validateExtractWorkspaceDecisionsPayload), async (req, res, next) => {
    return executeDecisionExtraction(req, res, next);
});

router.post('/:id/decisions/:decisionId/convert', validateBody(validateConvertDecisionToTasksPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const decision = await WorkspaceDecision.findOne({
            _id: req.params.decisionId,
            roomId: req.params.id,
        });
        if (!decision) {
            return res.status(404).json({ error: 'Decision not found' });
        }

        const { tasks } = req.validatedBody;
        const createdTasks = await WorkspaceTask.insertMany(
            tasks.map((task) => ({
                roomId: req.params.id,
                decisionId: decision._id,
                title: task.title,
                description: task.description,
                ownerId: task.ownerId,
                ownerName: task.ownerName,
                dueDate: task.dueDate || null,
                createdBy: req.userId,
                createdByName: req.displayName,
                lastUpdatedBy: req.userId,
                lastUpdatedByName: req.displayName,
            }))
        );

        decision.convertedAt = new Date();
        await decision.save();

        room.lastActivityAt = new Date();
        await room.save();

        res.status(201).json({
            decision: workspaceDecisionSummary(decision),
            tasks: createdTasks.map((task) => workspaceTaskSummary(task)),
        });
    } catch (err) {
        next(err);
    }
});

router.post(
    '/:id/tasks',
    validateBody(validateCreateWorkspaceTaskPayload),
    async (req, res, next) => {
        try {
            const room = await loadRoomOr404(req.params.id, res);
            if (!room) return;
            if (!isRoomMember(room, req.userId)) {
                return res.status(403).json({ error: 'Not a member of this room' });
            }

            const task = await WorkspaceTask.create({
                roomId: req.params.id,
                decisionId: null,
                title: req.validatedBody.title,
                description: req.validatedBody.description,
                status: 'todo',
                ownerId: req.validatedBody.ownerId,
                ownerName: req.validatedBody.ownerName,
                dueDate: req.validatedBody.dueDate,
                createdBy: req.userId,
                createdByName: req.displayName,
                lastUpdatedBy: req.userId,
                lastUpdatedByName: req.displayName,
            });

            room.lastActivityAt = new Date();
            await room.save();

            res.status(201).json({ task: workspaceTaskSummary(task) });
        } catch (err) {
            next(err);
        }
    }
);

router.get('/:id/tasks', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const status = String(req.query?.status || '').trim();
        const ownerId = String(req.query?.ownerId || '').trim();
        const filter = { roomId: req.params.id };
        if (status) filter.status = status;
        if (ownerId) filter.ownerId = ownerId;

        const tasks = await WorkspaceTask.find(filter)
            .sort({ updatedAt: -1 })
            .limit(500)
            .lean();

        res.json({ tasks: tasks.map((task) => workspaceTaskSummary(task)) });
    } catch (err) {
        next(err);
    }
});

router.patch('/:id/tasks/:taskId', validateBody(validateUpdateWorkspaceTaskPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const task = await WorkspaceTask.findOne({
            _id: req.params.taskId,
            roomId: req.params.id,
        });
        if (!task) {
            return res.status(404).json({ error: 'Task not found' });
        }

        Object.assign(task, req.validatedBody, {
            lastUpdatedBy: req.userId,
            lastUpdatedByName: req.displayName,
        });
        await task.save();

        room.lastActivityAt = new Date();
        await room.save();

        res.json({ task: workspaceTaskSummary(task) });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/milestones', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const milestones = await WorkspaceMilestone.find({ roomId: req.params.id })
            .sort({ targetDate: 1, createdAt: 1 })
            .limit(200)
            .lean();

        res.json({ milestones: milestones.map((m) => workspaceMilestoneSummary(m)) });
    } catch (err) {
        next(err);
    }
});

router.post('/:id/milestones', validateBody(validateCreateMilestonePayload), async (req, res, next) => {
    try {
        const { title, description, targetDate } = req.validatedBody;
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const milestone = await WorkspaceMilestone.create({
            roomId: req.params.id,
            title,
            description,
            targetDate,
            createdBy: req.userId,
            createdByName: req.displayName,
        });

        room.lastActivityAt = new Date();
        await room.save();

        res.status(201).json({ milestone: workspaceMilestoneSummary(milestone) });
    } catch (err) {
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

router.post('/:id/messages/:msgId/challenge', validateBody(validateChallengePayload), async (req, res, next) => {
    try {
        const { content } = req.validatedBody;

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
        next(err);
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

/**
 * POST /api/rooms/:id/join
 * Join a room from an invite link.
 */
router.post('/:id/join', async (req, res) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        const alreadyMember = room.members.some((member) => member.userId === req.userId);
        if (!alreadyMember) {
            room.members.push({
                userId: req.userId,
                displayName: req.displayName || `User_${req.userId.slice(-6)}`,
                role: 'member',
            });
            room.lastActivityAt = new Date();
            await room.save();
        }

        res.json({ room: roomResponse(room), joined: !alreadyMember });
    } catch (err) {
        console.error('[rooms] join error:', err);
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

        const link = `${APP_BASE_URL}/#/invite/${req.params.id}`;
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

router.get('/:id/artifacts/:artifactId/versions', async (req, res, next) => {
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
        next(err);
    }
});

router.post(
    '/:id/artifacts/:artifactId/revise',
    validateBody(validateReviseArtifactPayload),
    async (req, res, next) => {
        try {
            const { instructions, changeSummary } = req.validatedBody;

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
                changeSummary,
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
            next(err);
        }
    }
);

router.post('/:id/artifacts/:artifactId/versions/:versionId/approve', async (req, res, next) => {
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
        next(err);
    }
});

router.post('/:id/artifacts/:artifactId/versions/:versionId/comment', validateBody(validateArtifactCommentPayload), async (req, res, next) => {
    try {
        const { content } = req.validatedBody;

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
        next(err);
    }
});

router.patch(
    '/:id/artifacts/:artifactId/status',
    validateBody(validateArtifactStatusPayload),
    async (req, res, next) => {
        try {
            const { status } = req.validatedBody;

            const room = await loadRoomOr404(req.params.id, res);
            if (!room) return;

            // Only owners can validate or archive; members can move to review
            if (['validated', 'archived'].includes(status) && !isRoomOwner(room, req.userId)) {
                return res.status(403).json({ error: 'Owner role required for this transition' });
            }
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

            artifact.status = status;
            artifact.updatedAt = new Date();
            await artifact.save();

            room.lastActivityAt = new Date();
            await room.save();

            res.json({ artifact: artifactSummary(artifact) });
        } catch (err) {
            next(err);
        }
    }
);

router.post(
    '/:id/artifacts/:artifactId/versions/:versionId/reject',
    validateBody(validateArtifactRejectPayload),
    async (req, res, next) => {
        try {
            const { reason } = req.validatedBody;

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

            version.status = 'rejected';
            if (reason) {
                version.comments.push({
                    authorId: req.userId,
                    authorName: req.displayName,
                    text: `[Rejet] ${reason}`,
                    resolved: false,
                });
            }
            await version.save();

            if (String(artifact.currentVersionId) === String(version._id)) {
                artifact.status = 'draft';
                artifact.updatedAt = new Date();
                await artifact.save();
            }

            room.lastActivityAt = new Date();
            await room.save();

            res.json({ artifact: artifactSummary(artifact, version), version });
        } catch (err) {
            next(err);
        }
    }
);

router.patch(
    '/:id/artifacts/:artifactId/versions/:versionId/comments/:commentId/resolve',
    validateBody(validateResolveCommentPayload),
    async (req, res, next) => {
        try {
            const { resolved } = req.validatedBody;

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

            const comment = version.comments.id(req.params.commentId);
            if (!comment) {
                return res.status(404).json({ error: 'Comment not found' });
            }

            // Only the comment author or an owner can resolve/unresolve
            if (comment.authorId !== req.userId && !isRoomOwner(room, req.userId)) {
                return res.status(403).json({ error: 'Not authorized to resolve this comment' });
            }

            comment.resolved = resolved;
            await version.save();

            res.json({ comment, version: { _id: version._id, number: version.number } });
        } catch (err) {
            next(err);
        }
    }
);



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

router.post('/:id/missions/:missionId/extract', validateBody(validateExtractWorkspaceDecisionsPayload), async (req, res, next) => {
    return executeDecisionExtraction(req, res, next, {
        missionIdOverride: req.params.missionId,
    });
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

router.post('/:id/search', validateBody(validateRoomSearchPayload), async (req, res, next) => {
    try {
        const { query } = req.validatedBody;

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
        next(err);
    }
});

router.post('/:id/documents', validateBody(validateCreateDocumentPayload), async (req, res, next) => {
    try {
        const { title, content } = req.validatedBody;

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
        next(err);
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
router.post('/:id/integrations/slack', validateBody(validateConnectSlackPayload), async (req, res, next) => {
    try {
        const { botToken, channelId } = req.validatedBody;

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to connect integrations' });
        }

        // Validate the token against Slack by calling auth.test
        let { default: axios } = await import('axios').catch(() => ({ default: null }));
        if (!axios) {
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
        next(err);
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
 * Manual share endpoint with connector abstraction, retries and idempotency.
 * Accepts optional { note, target, artifactId, idempotencyKey } in body.
 */
router.post('/:id/share', validateBody(validateSharePayload), async (req, res, next) => {
    try {
        const { note, target, artifactId, idempotencyKey } = req.validatedBody;
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const connector = getExportConnector(target);
        if (!connector) {
            return res.status(400).json({ error: 'Unsupported share target' });
        }
        if (!connector.isConfigured(room)) {
            return res.status(409).json({
                error: `${target} not connected for this room. Connect via /integrations/${target} first.`,
            });
        }

        if (idempotencyKey) {
            const existing = await RoomShareHistory.findOne({
                roomId: req.params.id,
                idempotencyKey,
            }).lean();
            if (existing) {
                return res.json({
                    ok: existing.status === 'success',
                    replayed: true,
                    status: existing.status,
                    target: existing.target,
                    externalId: existing.externalId || '',
                    externalUrl: existing.externalUrl || '',
                    historyId: String(existing._id),
                });
            }
        }

        const { summary, artifactId: matchedArtifactId } = await buildShareSummary(room, artifactId);

        let history;
        try {
            history = await RoomShareHistory.create({
                roomId: req.params.id,
                artifactId: matchedArtifactId,
                target,
                status: 'pending',
                idempotencyKey,
                actorId: req.userId,
                actorName: req.displayName,
                note,
                summary: String(summary).slice(0, 1000),
            });
        } catch (createErr) {
            if (createErr?.code === 11000 && idempotencyKey) {
                const existing = await RoomShareHistory.findOne({
                    roomId: req.params.id,
                    idempotencyKey,
                }).lean();
                if (existing) {
                    return res.json({
                        ok: existing.status === 'success',
                        replayed: true,
                        status: existing.status,
                        target: existing.target,
                        externalId: existing.externalId || '',
                        externalUrl: existing.externalUrl || '',
                        historyId: String(existing._id),
                    });
                }
            }
            throw createErr;
        }

        try {
            const { result, attempts } = await executeWithRetry(
                () => connector.send({ room, summary, note }),
                {
                    maxAttempts: 3,
                    baseDelayMs: 200,
                }
            );

            history.status = 'success';
            history.retries = Math.max(0, attempts - 1);
            history.externalId = String(result.externalId || '');
            history.externalUrl = String(result.externalUrl || '');
            history.metadata = result.metadata || null;
            history.errorCode = '';
            history.errorMessage = '';
            await history.save();

            res.json({
                ok: true,
                replayed: false,
                target,
                retries: history.retries,
                externalId: history.externalId,
                externalUrl: history.externalUrl,
                historyId: String(history._id),
            });
        } catch (err) {
            history.status = 'failed';
            history.retries = Number(err?.retries || 0);
            history.errorCode = String(err?.code || '').slice(0, 120);
            history.errorMessage = String(err?.message || 'Share failed').slice(0, 3000);
            await history.save();
            throw err;
        }
    } catch (err) {
        next(err);
    }
});

router.get('/:id/share/history', async (req, res, next) => {
    try {
        const filters = validateShareHistoryQuery(req.query || {});

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const query = { roomId: req.params.id };
        if (filters.target) query.target = filters.target;
        if (filters.status) query.status = filters.status;
        if (filters.artifactId) query.artifactId = filters.artifactId;

        const history = await RoomShareHistory.find(query)
            .sort({ createdAt: -1 })
            .limit(filters.limit)
            .lean();

        res.json({
            history: history.map((item) => ({
                ...item,
                requestId: req.requestId || null,
            })),
        });
    } catch (err) {
        next(err);
    }
});

// ── Integrations: Notion ──────────────────────────────────────────────────────

/**
 * POST /api/rooms/:id/integrations/notion/pages
 * Discover accessible Notion pages for a token (does not persist integration).
 */
router.post('/:id/integrations/notion/pages', validateBody(validateDiscoverNotionPagesPayload), async (req, res, next) => {
    try {
        const { apiToken, query, limit } = req.validatedBody;

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomOwner(room, req.userId)) {
            return res.status(403).json({ error: 'Owner role required to connect integrations' });
        }

        const pages = await discoverNotionPages({ apiToken, query, limit });
        res.json({ pages });
    } catch (err) {
        next(err);
    }
});

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
router.post('/:id/integrations/notion', validateBody(validateConnectNotionPayload), async (req, res, next) => {
    try {
        const { apiToken, parentPageId } = req.validatedBody;

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
        next(err);
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

/**
 * POST /api/rooms/:id/messages/:msgId/feedback
 * Record thumbs up (+1) or down (-1) on an AI message.
 * One vote per user; re-posting replaces the previous vote.
 */
router.post('/:id/messages/:msgId/feedback', validateBody(validateAiFeedbackPayload), async (req, res, next) => {
    try {
        const { rating } = req.validatedBody;

        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const message = await RoomMessage.findOne({
            _id: req.params.msgId,
            roomId: req.params.id,
        });
        if (!message) {
            return res.status(404).json({ error: 'Message not found' });
        }
        if (!message.isAI) {
            return res.status(400).json({
                ok: false,
                code: 'BAD_REQUEST',
                message: 'Feedback can only be given on AI messages',
                details: null,
                requestId: req.requestId || null,
            });
        }

        // Replace existing vote from this user, or push new one
        const existing = message.feedback.find((f) => f.userId === req.userId);
        if (existing) {
            existing.rating = rating;
        } else {
            message.feedback.push({ userId: req.userId, rating });
        }
        await message.save();

        const thumbsUp = message.feedback.filter((f) => f.rating === 1).length;
        const thumbsDown = message.feedback.filter((f) => f.rating === -1).length;

        res.json({ ok: true, messageId: String(message._id), thumbsUp, thumbsDown, userRating: rating });
    } catch (err) {
        next(err);
    }
});

export default router;
