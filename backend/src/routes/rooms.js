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
import RoomFeedbackEvent from '../models/RoomFeedbackEvent.js';
import RoomDecisionPackEvent from '../models/RoomDecisionPackEvent.js';
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
import { getMyDay, getMyDayStats } from '../services/myDayService.js';
import {
    markTaskDone,
    deferTask,
    reassignTask,
    updateTaskPriority,
    addTaskNote,
} from '../services/taskActionService.js';
import { generateNudgeCandidates, recordNudgeInteraction } from '../services/nudgeService.js';
import { logEvent, computeDESProxy, generateDailySnapshot } from '../services/desInstrumentationService.js';
import { generateReminderCards, snoozeReminder } from '../services/reminderService.js';
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
    validateDecisionPackSharePayload,
    validateDirectivesPayload,
    validateDecisionPackAggregateQuery,
    validateDecisionPackEventPayload,
    validateDiscoverNotionPagesPayload,
    validateEmptyBody,
    validateFeedbackAggregateQuery,
    validateKpiDashboardQuery,
    validateResolveCommentPayload,
    validateResolveWorkspaceCommentPayload,
    validateExtractWorkspaceDecisionsPayload,
    validateReorderWorkspaceBlocksPayload,
    validateReviseArtifactPayload,
    validateRoomSearchPayload,
    validateShareHistoryQuery,
    validateSharePayload,
    validateSendMessagePayload,
    validateTaskActionPayload,
    validateReminderSnoozePayload,
    validateUpdateWorkspaceBlockPayload,
    validateUpdateWorkspacePagePayload,
    validateUpdateWorkspaceDecisionPayload,
    validateUpdateWorkspaceTaskPayload,
} from '../middleware/validation.js';
import DOMAIN_TEMPLATES, {
    getTemplateById,
    getTemplateVersions,
    resolveTemplateVariant,
} from '../config/domainTemplates.js';

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

function getRoomRole(room, userId) {
    const member = room.members.find((item) => item.userId === userId);
    return String(member?.role || '').trim().toLowerCase();
}

function canReviewArtifacts(room, userId) {
    const role = getRoomRole(room, userId);
    return role === 'owner' || role === 'member';
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

function computeSlaLabel(dueDate, createdAt) {
    if (!dueDate) return 'none';
    const now = new Date();
    const due = new Date(dueDate);
    if (Number.isNaN(due.getTime())) return 'none';

    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const tomorrow = new Date(today.getTime() + 24 * 60 * 60 * 1000);
    const dayAfterTomorrow = new Date(tomorrow.getTime() + 24 * 60 * 60 * 1000);

    if (due < now) return 'late';
    if (due >= today && due < tomorrow) return 'today';
    if (due >= tomorrow && due < dayAfterTomorrow) return 'tomorrow';

    const created = createdAt ? new Date(createdAt) : null;
    if (created && !Number.isNaN(created.getTime())) {
        const ageMs = now.getTime() - created.getTime();
        if (ageMs > 5 * 24 * 60 * 60 * 1000) {
            return 'soon';
        }
    }

    return 'later';
}

function slaRiskScore(label) {
    if (label === 'late') return 4;
    if (label === 'today') return 3;
    if (label === 'tomorrow') return 2;
    if (label === 'soon') return 1;
    return 0;
}

function buildInboxItem({ type, sourceId, title, description, channel, createdBy, createdByName, createdAt, dueDate, priority, ownerId, ownerName, status, sourceType }) {
    const sla = computeSlaLabel(dueDate, createdAt);
    return {
        id: `${type}-${sourceId}`,
        type,
        sourceId,
        sourceType: sourceType || '',
        title: String(title || '').trim() || 'Untitled',
        description: String(description || '').trim(),
        channel: String(channel || '').trim(),
        createdBy: String(createdBy || '').trim(),
        createdByName: String(createdByName || '').trim(),
        createdAt,
        dueDate,
        priority: String(priority || 'normal').trim(),
        sla,
        slaRisk: slaRiskScore(sla),
        ownerId: String(ownerId || '').trim(),
        ownerName: String(ownerName || '').trim(),
        status: String(status || '').trim(),
    };
}

function formatDecisionPackMarkdown({ room, decisions, tasks, generatedAt, mode = 'checklist' }) {
    const safeRoomName = String(room?.name || 'Channel').trim() || 'Channel';
    const lines = [];
    lines.push(`# Decision Pack — ${safeRoomName}`);
    lines.push('');
    lines.push(`Generated at: ${generatedAt.toISOString()}`);
    lines.push('');
    lines.push(mode === 'executive' ? '## Executive Decisions' : '## Decisions');
    lines.push('');

    if (!decisions.length) {
        lines.push('- No decisions available yet.');
    } else {
        decisions.forEach((decision, index) => {
            const decisionId = String(decision?._id || '').trim();
            const title = String(decision?.title || '').trim() || `Decision ${index + 1}`;
            const summary = String(decision?.summary || '').trim();
            lines.push(`### ${index + 1}. ${title}`);
            if (summary) lines.push(summary);
            const linkedTasks = tasks.filter(
                (task) => String(task?.decisionId || '') === decisionId
            );
            if (mode === 'executive') {
                const owners = linkedTasks
                    .map((task) => String(task?.ownerName || '').trim())
                    .filter(Boolean);
                if (owners.length) {
                    lines.push(`Owners: ${Array.from(new Set(owners)).join(', ')}`);
                }
            } else if (!linkedTasks.length) {
                lines.push('- Tasks: none linked yet.');
            } else {
                lines.push('- Tasks:');
                linkedTasks.forEach((task) => {
                    const taskTitle = String(task?.title || '').trim() || 'Untitled task';
                    const ownerName = String(task?.ownerName || '').trim();
                    const dueDate = task?.dueDate ? new Date(task.dueDate).toISOString().slice(0, 10) : '';
                    const suffix = [ownerName ? `owner: ${ownerName}` : '', dueDate ? `due: ${dueDate}` : '']
                        .filter(Boolean)
                        .join(', ');
                    lines.push(`  - ${taskTitle}${suffix ? ` (${suffix})` : ''}`);
                });
            }
            lines.push('');
        });
    }

    lines.push(mode === 'executive' ? '## Open Risks / Open Items' : '## Open Tasks (without decision link)');
    lines.push('');
    const unlinkedTasks = tasks.filter((task) => !task?.decisionId);
    if (!unlinkedTasks.length) {
        lines.push('- None.');
    } else {
        unlinkedTasks.forEach((task) => {
            lines.push(`- ${String(task?.title || 'Untitled task').trim()}`);
        });
    }
    lines.push('');
    lines.push('## Next Review');
    lines.push('');
    lines.push('- Validate owners and deadlines for all critical tasks.');
    lines.push('- Confirm decision status in the next channel review.');
    if (mode === 'executive') {
        lines.push('- Align on expected business impact and decision success criteria.');
    }
    return lines.join('\n');
}

function csvEscape(value) {
    const text = String(value ?? '').replace(/\r?\n/g, ' ').trim();
    return `"${text.replace(/"/g, '""')}"`;
}

function formatDecisionPackCsv({ room, decisions, tasks, generatedAt }) {
    const safeRoomName = String(room?.name || 'Channel').trim() || 'Channel';
    const decisionById = new Map(
        decisions.map((decision) => [String(decision?._id || ''), String(decision?.title || '').trim()])
    );

    const rows = [
        [
            'generated_at',
            'room_id',
            'room_name',
            'section',
            'decision_id',
            'decision_title',
            'task_id',
            'task_title',
            'task_status',
            'owner_name',
            'due_date',
            'source_type',
        ],
    ];

    decisions.forEach((decision) => {
        rows.push([
            generatedAt.toISOString(),
            String(room?._id || room?.id || ''),
            safeRoomName,
            'decision',
            String(decision?._id || ''),
            String(decision?.title || '').trim(),
            '',
            '',
            '',
            '',
            '',
            String(decision?.sourceType || '').trim(),
        ]);
    });

    tasks.forEach((task) => {
        const decisionId = String(task?.decisionId || '');
        rows.push([
            generatedAt.toISOString(),
            String(room?._id || room?.id || ''),
            safeRoomName,
            decisionId ? 'task_linked' : 'task_open',
            decisionId,
            decisionById.get(decisionId) || '',
            String(task?._id || ''),
            String(task?.title || '').trim(),
            String(task?.status || '').trim(),
            String(task?.ownerName || '').trim(),
            task?.dueDate ? new Date(task.dueDate).toISOString().slice(0, 10) : '',
            '',
        ]);
    });

    return rows
        .map((row) => row.map((cell) => csvEscape(cell)).join(','))
        .join('\n');
}

function evaluateDecisionPackReadiness({ decisions = [], tasks = [] }) {
    const totalTasks = tasks.length;
    const tasksWithOwners = tasks.filter((task) => String(task?.ownerName || task?.ownerId || '').trim()).length;
    const tasksWithDueDates = tasks.filter((task) => Boolean(task?.dueDate)).length;
    const linkedTaskCount = tasks.filter((task) => String(task?.decisionId || '').trim()).length;
    const ownerCoverage = totalTasks > 0 ? tasksWithOwners / totalTasks : 0;
    const dueDateCoverage = totalTasks > 0 ? tasksWithDueDates / totalTasks : 0;
    const linkedTaskCoverage = totalTasks > 0 ? linkedTaskCount / totalTasks : 0;
    const recommendations = [];

    if (!decisions.length) {
        recommendations.push('Add at least one explicit decision before sharing.');
    }
    if (totalTasks === 0) {
        recommendations.push('Create follow-up tasks so the Decision Pack has execution detail.');
    }
    if (totalTasks > 0 && ownerCoverage < 0.8) {
        recommendations.push('Assign owners to the remaining open tasks.');
    }
    if (totalTasks > 0 && dueDateCoverage < 0.6) {
        recommendations.push('Add due dates for the most important tasks.');
    }
    if (totalTasks > 0 && linkedTaskCoverage < 0.5) {
        recommendations.push('Link tasks back to decisions where possible.');
    }

    const score = Math.round(
        (
            (decisions.length > 0 ? 0.25 : 0) +
            (totalTasks > 0 ? 0.15 : 0) +
            (ownerCoverage * 0.3) +
            (dueDateCoverage * 0.2) +
            (linkedTaskCoverage * 0.1)
        ) * 100
    );

    return {
        ready: score >= 70 && recommendations.length <= 2,
        score,
        totalTasks,
        tasksWithOwners,
        tasksWithDueDates,
        linkedTaskCount,
        ownerCoverage,
        dueDateCoverage,
        linkedTaskCoverage,
        recommendations,
    };
}

function buildExecutionPulse({ decisions = [], tasks = [] }) {
    const now = new Date();
    const soon = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);
    const staleReviewCutoff = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000);

    const activeTasks = tasks.filter((task) => String(task?.status || 'todo') !== 'done');
    const activeDecisions = decisions.filter((decision) => String(decision?.status || 'draft') !== 'implemented');

    const overdueTasks = activeTasks.filter((task) => task?.dueDate && new Date(task.dueDate) < now);
    const dueSoonTasks = activeTasks.filter((task) => task?.dueDate && new Date(task.dueDate) >= now && new Date(task.dueDate) <= soon);
    const blockedTasks = activeTasks.filter((task) => String(task?.status || '') === 'blocked');
    const unassignedTasks = activeTasks.filter(
        (task) => !String(task?.ownerName || task?.ownerId || '').trim()
    );

    const overdueDecisions = activeDecisions.filter(
        (decision) => decision?.dueDate && new Date(decision.dueDate) < now
    );
    const dueSoonDecisions = activeDecisions.filter(
        (decision) => decision?.dueDate && new Date(decision.dueDate) >= now && new Date(decision.dueDate) <= soon
    );
    const decisionsWithoutOwner = activeDecisions.filter(
        (decision) => !String(decision?.ownerName || decision?.ownerId || '').trim()
    );
    const staleReviewDecisions = activeDecisions.filter(
        (decision) => String(decision?.status || '') === 'review' && decision?.updatedAt && new Date(decision.updatedAt) < staleReviewCutoff
    );

    const criticalCount =
        overdueTasks.length + overdueDecisions.length + blockedTasks.length + staleReviewDecisions.length;
    const warningCount =
        dueSoonTasks.length + dueSoonDecisions.length + unassignedTasks.length + decisionsWithoutOwner.length;

    const recommendations = [];
    if (overdueDecisions.length) {
        recommendations.push(
            `${overdueDecisions.length} decision${overdueDecisions.length > 1 ? 's' : ''} depasse${overdueDecisions.length > 1 ? 'nt' : ''} leur echeance.`
        );
    }
    if (blockedTasks.length) {
        recommendations.push(
            `${blockedTasks.length} tache${blockedTasks.length > 1 ? 's sont' : ' est'} bloquee${blockedTasks.length > 1 ? 's' : ''} et demande${blockedTasks.length > 1 ? 'nt' : ''} un debloquage.`
        );
    }
    if (decisionsWithoutOwner.length || unassignedTasks.length) {
        const totalWithoutOwner = decisionsWithoutOwner.length + unassignedTasks.length;
        recommendations.push(
            `${totalWithoutOwner} element${totalWithoutOwner > 1 ? 's n ont' : ' n a'} pas encore de responsable explicite.`
        );
    }
    if (dueSoonDecisions.length || dueSoonTasks.length) {
        const upcoming = dueSoonDecisions.length + dueSoonTasks.length;
        recommendations.push(
            `${upcoming} engagement${upcoming > 1 ? 's arrivent' : ' arrive'} a echeance dans les 3 prochains jours.`
        );
    }
    if (!recommendations.length) {
        recommendations.push('Execution saine: aucun signal critique ou attention immediate detecte.');
    }

    const status = criticalCount > 0 ? 'critical' : warningCount > 0 ? 'attention' : 'on_track';
    const score = Math.max(
        0,
        100 -
        overdueDecisions.length * 20 -
        overdueTasks.length * 14 -
        blockedTasks.length * 12 -
        staleReviewDecisions.length * 10 -
        dueSoonDecisions.length * 7 -
        dueSoonTasks.length * 5 -
        decisionsWithoutOwner.length * 6 -
        unassignedTasks.length * 4
    );

    const focusItems = [
        ...overdueDecisions.map((decision) => ({
            kind: 'decision',
            itemId: String(decision?._id || ''),
            severity: 'critical',
            title: String(decision?.title || 'Decision'),
            status: String(decision?.status || 'draft'),
            ownerName: String(decision?.ownerName || ''),
            dueDate: decision?.dueDate || null,
            subtitle: `Decision en retard${decision?.ownerName ? ` • ${decision.ownerName}` : ''}`,
        })),
        ...blockedTasks.map((task) => ({
            kind: 'task',
            itemId: String(task?._id || ''),
            severity: 'critical',
            title: String(task?.title || 'Task'),
            status: String(task?.status || 'blocked'),
            ownerName: String(task?.ownerName || ''),
            dueDate: task?.dueDate || null,
            subtitle: `Tache bloquee${task?.ownerName ? ` • ${task.ownerName}` : ''}`,
        })),
        ...overdueTasks.map((task) => ({
            kind: 'task',
            itemId: String(task?._id || ''),
            severity: 'critical',
            title: String(task?.title || 'Task'),
            status: String(task?.status || 'todo'),
            ownerName: String(task?.ownerName || ''),
            dueDate: task?.dueDate || null,
            subtitle: `Tache en retard${task?.ownerName ? ` • ${task.ownerName}` : ''}`,
        })),
        ...dueSoonDecisions.map((decision) => ({
            kind: 'decision',
            itemId: String(decision?._id || ''),
            severity: 'warning',
            title: String(decision?.title || 'Decision'),
            status: String(decision?.status || 'draft'),
            ownerName: String(decision?.ownerName || ''),
            dueDate: decision?.dueDate || null,
            subtitle: `Decision a suivre sous 3 jours${decision?.ownerName ? ` • ${decision.ownerName}` : ''}`,
        })),
        ...dueSoonTasks.map((task) => ({
            kind: 'task',
            itemId: String(task?._id || ''),
            severity: 'warning',
            title: String(task?.title || 'Task'),
            status: String(task?.status || 'todo'),
            ownerName: String(task?.ownerName || ''),
            dueDate: task?.dueDate || null,
            subtitle: `Tache a suivre sous 3 jours${task?.ownerName ? ` • ${task.ownerName}` : ''}`,
        })),
    ]
        .sort((left, right) => {
            const severityWeight = { critical: 0, warning: 1 };
            const leftSeverity = severityWeight[left.severity] ?? 10;
            const rightSeverity = severityWeight[right.severity] ?? 10;
            if (leftSeverity !== rightSeverity) return leftSeverity - rightSeverity;

            const leftDue = left.dueDate ? new Date(left.dueDate).getTime() : Number.MAX_SAFE_INTEGER;
            const rightDue = right.dueDate ? new Date(right.dueDate).getTime() : Number.MAX_SAFE_INTEGER;
            return leftDue - rightDue;
        })
        .slice(0, 5);

    return {
        generatedAt: now,
        status,
        score,
        criticalCount,
        warningCount,
        tasks: {
            overdue: overdueTasks.length,
            dueSoon: dueSoonTasks.length,
            blocked: blockedTasks.length,
            unassigned: unassignedTasks.length,
        },
        decisions: {
            overdue: overdueDecisions.length,
            dueSoon: dueSoonDecisions.length,
            withoutOwner: decisionsWithoutOwner.length,
            staleReview: staleReviewDecisions.length,
        },
        recommendations,
        focusItems,
    };
}

async function loadDecisionPackData(roomId, { limit = 10, includeOpenTasks = true } = {}) {
    const decisions = await WorkspaceDecision.find({ roomId })
        .sort({ createdAt: -1 })
        .limit(limit)
        .lean();
    const decisionIds = decisions.map((decision) => decision._id);

    const taskFilter = includeOpenTasks
        ? {
            roomId,
            $or: [
                { decisionId: { $in: decisionIds } },
                { decisionId: null },
            ],
        }
        : {
            roomId,
            decisionId: { $in: decisionIds },
        };

    const tasks = await WorkspaceTask.find(taskFilter)
        .sort({ createdAt: -1 })
        .limit(limit * 5)
        .lean();

    return { decisions, tasks };
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
            }, req.requestId || null);
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

function tooManyRequestsError(message = 'Too many requests', retryAfterSec = 60) {
    const err = new Error(message);
    err.status = 429;
    err.code = 'RATE_LIMITED';
    err.retryAfterSec = Math.max(1, Number.parseInt(String(retryAfterSec || 60), 10) || 60);
    err.details = { retryAfterSec: err.retryAfterSec };
    return err;
}

async function enforceRouteRateLimit(req, key, maxPerMinute, message) {
    const checkLimit = req.app?.locals?.checkRateLimit;
    if (typeof checkLimit === 'function') {
        const result = await checkLimit(key, maxPerMinute);
        if (!result?.allowed) {
            throw tooManyRequestsError(message, result?.retryAfterSec || 60);
        }
        return;
    }

    const legacyLimiter = req.app?.locals?.simpleRateLimit;
    if (typeof legacyLimiter === 'function') {
        const allowed = await legacyLimiter(key, maxPerMinute);
        if (!allowed) {
            throw tooManyRequestsError(message, 60);
        }
    }
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
    res.json({
        templates: DOMAIN_TEMPLATES.map(
            ({ id, version, versionWeights, name, emoji, description, purpose, starterPrompts }) => ({
                id,
                version,
                versionWeights,
                name,
                emoji,
                description,
                purpose,
                starterPrompts: Array.isArray(starterPrompts) ? starterPrompts : [],
            })
        ),
    });
});

function toPercent(part, total) {
    if (!total) return 0;
    return Math.round((part / total) * 1000) / 10;
}

const LOW_SAMPLE_ROOMS_THRESHOLD = 10;

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
    const FEEDBACK_DELTA_THRESHOLD = 0.2; // Only declare winner if |delta| > 0.2
    const D7_DELTA_THRESHOLD = 5; // Only declare winner if delta > 5%

    const active = stats.filter((s) => s.roomsCreated > 0);

    const byConfidenceThen = (left, right, metricCmp) => {
        // Prefer non-low-sample rows when ranking winners.
        if (left.isLowSample !== right.isLowSample) {
            return left.isLowSample ? 1 : -1;
        }
        return metricCmp(left, right);
    };

    const byFeedback = [...active].sort((a, b) => byConfidenceThen(a, b, (x, y) => {
        if (y.feedbackAverage !== x.feedbackAverage) {
            return y.feedbackAverage - x.feedbackAverage;
        }
        return y.roomsCreated - x.roomsCreated;
    }));

    const byD7 = [...active].sort((a, b) => byConfidenceThen(a, b, (x, y) => {
        if (y.d7RetentionRate !== x.d7RetentionRate) {
            return y.d7RetentionRate - x.d7RetentionRate;
        }
        return y.roomsCreated - x.roomsCreated;
    }));

    // Determine winner by feedback score (conservative: high sample + strong delta)
    let feedbackWinner = null;
    if (byFeedback.length >= 2) {
        const top = byFeedback[0];
        const second = byFeedback[1];
        const delta = Math.abs(top.feedbackAverage - second.feedbackAverage);
        if (!top.isLowSample && delta > FEEDBACK_DELTA_THRESHOLD) {
            feedbackWinner = top;
        }
    } else if (byFeedback.length === 1 && !byFeedback[0].isLowSample) {
        feedbackWinner = byFeedback[0];
    }

    // Determine winner by D7 retention (conservative: high sample + strong delta)
    let d7Winner = null;
    if (byD7.length >= 2) {
        const top = byD7[0];
        const second = byD7[1];
        const delta = top.d7RetentionRate - second.d7RetentionRate;
        if (!top.isLowSample && delta > D7_DELTA_THRESHOLD) {
            d7Winner = top;
        }
    } else if (byD7.length === 1 && !byD7[0].isLowSample) {
        d7Winner = byD7[0];
    }

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
        feedbackWinner,
        d7Winner,
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
        const statsByTemplate = new Map();
        for (const t of DOMAIN_TEMPLATES) {
            const versions =
                groupBy === 'version'
                    ? getTemplateVersions(t)
                    : [String(t.version || 'v1')];
            for (const templateVersion of versions) {
                const key = keyFor(t.id, templateVersion);
                if (statsByTemplate.has(key)) continue;
                orderedKeys.push(key);
                statsByTemplate.set(key, {
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
                });
            }
        }

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
                isLowSample: s.roomsCreated < LOW_SAMPLE_ROOMS_THRESHOLD,
                d1RetentionRate: toPercent(s.d1RetainedRooms, s.roomsCreated),
                d7RetentionRate: toPercent(s.d7RetainedRooms, s.roomsCreated),
            };
        });

        const insights = buildTemplateInsights(stats);

        // Enrich stats with winner info
        const statsWithWinners = stats.map((s) => ({
            ...s,
            winner:
                (insights?.feedbackWinner &&
                    insights.feedbackWinner.templateId === s.templateId &&
                    insights.feedbackWinner.templateVersion === s.templateVersion) ||
                    (insights?.d7Winner &&
                        insights.d7Winner.templateId === s.templateId &&
                        insights.d7Winner.templateVersion === s.templateVersion)
                    ? true
                    : false,
        }));

        res.json({
            stats: statsWithWinners,
            insights,
            sinceDays: sinceDays || null,
            groupBy,
            lowSampleThreshold: LOW_SAMPLE_ROOMS_THRESHOLD,
            generatedAt: new Date().toISOString(),
        });
    } catch (err) {
        console.error('[rooms] template stats error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

/**
 * GET /api/rooms/kpi/dashboard
 * Returns product KPI dashboard metrics for rooms visible to the current user.
 */
router.get('/kpi/dashboard', async (req, res, next) => {
    try {
        const { sinceDays } = validateKpiDashboardQuery(req.query || {});
        const since = new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000);

        const visibleRooms = await Room.find(
            { 'members.userId': req.userId },
            { _id: 1 }
        ).lean();
        const roomIds = visibleRooms
            .map((room) => room?._id)
            .filter(Boolean);

        if (!roomIds.length) {
            return res.json({
                dashboard: {
                    sinceDays,
                    since: since.toISOString(),
                    totals: {
                        roomsTotal: 0,
                        roomsActive: 0,
                        aiMessages: 0,
                        feedbackEvents: 0,
                        decisionPackEvents: 0,
                    },
                    metrics: {
                        activationRate: 0,
                        usefulAnswerRate: 0,
                        feedbackScore: 0,
                        regenerateRate: 0,
                        exportRate: 0,
                        ttvMedianMs: null,
                    },
                    feedback: {
                        pertinent: 0,
                        moyen: 0,
                        hors_sujet: 0,
                        total: 0,
                    },
                    decisionPack: {
                        viewed: 0,
                        shared: 0,
                        share_failed: 0,
                    },
                    notes: {
                        regenerateRate:
                            'Proxy based on feedback labels (moyen + hors_sujet) / total feedback.',
                        ttvMedianMs:
                            'Not available yet: requires dedicated TTV event instrumentation.',
                    },
                },
            });
        }

        const roomFilter = { roomId: { $in: roomIds }, createdAt: { $gte: since } };

        const [activeRoomsRaw, aiMessages, feedbackEvents, decisionStats] = await Promise.all([
            RoomMessage.aggregate([
                {
                    $match: roomFilter,
                },
                {
                    $group: {
                        _id: '$roomId',
                    },
                },
            ]),
            RoomMessage.countDocuments({ ...roomFilter, isAI: true }),
            RoomFeedbackEvent.find(roomFilter, { ratingLabel: 1 }).lean(),
            RoomDecisionPackEvent.aggregate([
                {
                    $match: roomFilter,
                },
                {
                    $group: {
                        _id: '$eventType',
                        count: { $sum: 1 },
                    },
                },
            ]),
        ]);

        const activeRooms = activeRoomsRaw.length;

        const feedback = {
            pertinent: 0,
            moyen: 0,
            hors_sujet: 0,
            total: 0,
        };
        feedbackEvents.forEach((event) => {
            const label = String(event?.ratingLabel || '').trim();
            if (Object.hasOwn(feedback, label)) {
                feedback[label] += 1;
                feedback.total += 1;
            }
        });

        const decisionPack = {
            viewed: 0,
            shared: 0,
            share_failed: 0,
        };
        decisionStats.forEach((item) => {
            if (item?._id && Object.hasOwn(decisionPack, item._id)) {
                decisionPack[item._id] = Number(item.count || 0);
            }
        });

        const feedbackScore = feedback.total
            ? Math.round(((feedback.pertinent - feedback.hors_sujet) / feedback.total) * 100) / 100
            : 0;
        const regenerateRate = feedback.total
            ? toPercent(feedback.moyen + feedback.hors_sujet, feedback.total)
            : 0;
        const exportRate = decisionPack.viewed
            ? toPercent(decisionPack.shared, decisionPack.viewed)
            : 0;

        return res.json({
            dashboard: {
                sinceDays,
                since: since.toISOString(),
                totals: {
                    roomsTotal: roomIds.length,
                    roomsActive: activeRooms,
                    aiMessages,
                    feedbackEvents: feedback.total,
                    decisionPackEvents:
                        decisionPack.viewed + decisionPack.shared + decisionPack.share_failed,
                },
                metrics: {
                    activationRate: toPercent(activeRooms, roomIds.length),
                    usefulAnswerRate: toPercent(feedback.pertinent, feedback.total),
                    feedbackScore,
                    regenerateRate,
                    exportRate,
                    ttvMedianMs: null,
                },
                feedback,
                decisionPack,
                notes: {
                    regenerateRate:
                        'Proxy based on feedback labels (moyen + hors_sujet) / total feedback.',
                    ttvMedianMs:
                        'Not available yet: requires dedicated TTV event instrumentation.',
                },
            },
        });
    } catch (err) {
        return next(err);
    }
});

router.post('/', validateBody(validateCreateRoomPayload), async (req, res, next) => {
    try {
        const {
            name,
            type,
            members,
            purpose,
            visibility,
            templateId,
            templateVersion,
        } = req.validatedBody;

        // Apply domain template directives if a valid templateId was supplied
        const template = templateId ? getTemplateById(templateId) : null;
        const selectedTemplate = template
            ? resolveTemplateVariant(template, templateVersion)
            : null;
        if (template && templateVersion && !selectedTemplate) {
            return res
                .status(400)
                .json({ error: 'templateVersion is invalid for this template' });
        }
        const resolvedPurpose = (purpose || template?.purpose || '').slice(0, 240);
        const resolvedDirectives = selectedTemplate?.aiDirectives || '';

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
            templateVersion: selectedTemplate?.version || '',
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
        await enforceRouteRateLimit(
            req,
            `room-msg:${req.userId}:${req.params.id}`,
            40,
            'Rate limit exceeded for room messages'
        );

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
            status: 'draft',
            ownerId: req.userId,
            ownerName: req.displayName,
            createdBy: req.userId,
            createdByName: req.displayName,
            lastUpdatedBy: req.userId,
            lastUpdatedByName: req.displayName,
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
        }, req.requestId || null);

        res.status(201).json({ decision: workspaceDecisionSummary(decision) });
    } catch (err) {
        next(err);
    }
});

router.patch('/:id/decisions/:decisionId', validateBody(validateUpdateWorkspaceDecisionPayload), async (req, res, next) => {
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

        const patch = req.validatedBody;
        if (patch.title !== undefined) decision.title = patch.title;
        if (patch.summary !== undefined) decision.summary = patch.summary;
        if (patch.status !== undefined) {
            decision.status = patch.status;
            if (patch.status === 'approved') {
                decision.approvedAt = new Date();
                decision.approvedBy = req.userId;
                decision.approvedByName = req.displayName;
            } else {
                decision.approvedAt = null;
                decision.approvedBy = '';
                decision.approvedByName = '';
            }
        }
        if (patch.ownerId !== undefined) decision.ownerId = patch.ownerId;
        if (patch.ownerName !== undefined) decision.ownerName = patch.ownerName;
        if (patch.dueDate !== undefined) decision.dueDate = patch.dueDate;
        decision.lastUpdatedBy = req.userId;
        decision.lastUpdatedByName = req.displayName;
        await decision.save();

        room.lastActivityAt = new Date();
        await room.save();

        res.json({ decision: workspaceDecisionSummary(decision) });
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

router.get('/:id/decision-pack', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const limit = Math.max(1, Math.min(50, Number.parseInt(String(req.query?.limit || '10'), 10) || 10));
        const mode = String(req.query?.mode || 'checklist').trim().toLowerCase();
        if (mode !== 'checklist' && mode !== 'executive') {
            return res.status(400).json({ error: 'Invalid mode. Use checklist or executive.' });
        }
        const includeOpenTasks = String(req.query?.includeOpenTasks || 'true')
            .trim()
            .toLowerCase() !== 'false';
        const { decisions, tasks } = await loadDecisionPackData(req.params.id, {
            limit,
            includeOpenTasks,
        });

        const generatedAt = new Date();
        const markdown = formatDecisionPackMarkdown({
            room,
            decisions,
            tasks,
            generatedAt,
            mode,
        });

        res.json({
            pack: {
                generatedAt,
                roomId: req.params.id,
                roomName: room.name,
                decisionCount: decisions.length,
                taskCount: tasks.length,
                mode,
                includeOpenTasks,
                markdown,
            },
            decisions: decisions.map((decision) => workspaceDecisionSummary(decision)),
            tasks: tasks.map((task) => workspaceTaskSummary(task)),
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/decision-pack/readiness', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { decisions, tasks } = await loadDecisionPackData(req.params.id, {
            limit: 10,
            includeOpenTasks: true,
        });

        res.json({
            readiness: evaluateDecisionPackReadiness({ decisions, tasks }),
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/execution-pulse', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const [decisions, tasks] = await Promise.all([
            WorkspaceDecision.find({ roomId: req.params.id })
                .sort({ createdAt: -1 })
                .limit(200)
                .lean(),
            WorkspaceTask.find({ roomId: req.params.id })
                .sort({ updatedAt: -1 })
                .limit(500)
                .lean(),
        ]);

        return res.json({
            pulse: buildExecutionPulse({ decisions, tasks }),
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/feedback-digest', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const feedbackEvents = await RoomFeedbackEvent.find({ roomId: req.params.id })
            .sort({ createdAt: -1 })
            .limit(500)
            .lean();

        const now = new Date();
        const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        const recentEvents = feedbackEvents.filter(
            (e) => new Date(e.createdAt) >= sevenDaysAgo
        );

        const totalFeedback = recentEvents.length;
        const totalPertinent = recentEvents.filter((e) => e.rating === 'pertinent').length;
        const totalMoyen = recentEvents.filter((e) => e.rating === 'moyen').length;
        const totalHorsSujet = recentEvents.filter((e) => e.rating === 'hors_sujet').length;

        const pertinentRate = totalFeedback > 0 ? totalPertinent / totalFeedback : 0;
        const moyenRate = totalFeedback > 0 ? totalMoyen / totalFeedback : 0;
        const horsSujetRate = totalFeedback > 0 ? totalHorsSujet / totalFeedback : 0;

        const reasonCounts = {};
        recentEvents
            .filter((e) => e.reason && String(e.reason).trim())
            .forEach((e) => {
                const reason = String(e.reason || '').trim().toLowerCase();
                reasonCounts[reason] = (reasonCounts[reason] || 0) + 1;
            });

        const topFrictionPatterns = Object.entries(reasonCounts)
            .filter(([_, count]) => count >= 2)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(([reason]) => reason);

        const topWinPatterns = recentEvents
            .filter((e) => e.rating === 'pertinent' && e.reason)
            .slice(0, 3)
            .map((e) => String(e.reason || 'Good feedback'))
            .filter((r) => r.trim());

        return res.json({
            digest: {
                pertinentRate: Math.round(pertinentRate * 100) / 100,
                moyenRate: Math.round(moyenRate * 100) / 100,
                horsSujetRate: Math.round(horsSujetRate * 100) / 100,
                totalFeedback,
                totalPertinent,
                totalMoyen,
                totalHorsSujet,
                topFrictionPatterns,
                topWinPatterns,
                generatedAt: now,
            },
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/inbox', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const limit = Math.max(1, Math.min(200, Number.parseInt(String(req.query?.limit || '50'), 10) || 50));
        const filter = String(req.query?.filter || 'all').trim().toLowerCase();
        const q = String(req.query?.q || '').trim().toLowerCase();
        const before = String(req.query?.before || '').trim();
        const beforeDate = before ? new Date(before) : null;

        const baseDateQuery = beforeDate && !Number.isNaN(beforeDate.getTime())
            ? { $lt: beforeDate }
            : undefined;

        const [tasks, decisions, messages] = await Promise.all([
            WorkspaceTask.find({
                roomId: req.params.id,
                status: { $ne: 'done' },
                ...(baseDateQuery ? { createdAt: baseDateQuery } : {}),
            })
                .sort({ createdAt: -1 })
                .limit(300)
                .lean(),
            WorkspaceDecision.find({
                roomId: req.params.id,
                status: { $nin: ['implemented'] },
                ...(baseDateQuery ? { createdAt: baseDateQuery } : {}),
            })
                .sort({ createdAt: -1 })
                .limit(300)
                .lean(),
            RoomMessage.find({
                roomId: req.params.id,
                senderId: { $ne: 'ai' },
                type: { $in: ['text', 'artifact', 'decision', 'research'] },
                ...(baseDateQuery ? { createdAt: baseDateQuery } : {}),
            })
                .sort({ createdAt: -1 })
                .limit(300)
                .lean(),
        ]);

        let items = [
            ...tasks.map((task) => buildInboxItem({
                type: 'task',
                sourceId: task._id,
                title: task.title,
                description: task.description,
                channel: room.name,
                createdBy: task.createdBy,
                createdByName: task.createdByName,
                createdAt: task.createdAt,
                dueDate: task.dueDate,
                priority: task.status === 'blocked' ? 'high' : 'normal',
                ownerId: task.ownerId,
                ownerName: task.ownerName,
                status: task.status,
                sourceType: 'workspace_task',
            })),
            ...decisions.map((decision) => buildInboxItem({
                type: 'decision',
                sourceId: decision._id,
                title: decision.title,
                description: decision.summary,
                channel: room.name,
                createdBy: decision.createdBy,
                createdByName: decision.createdByName,
                createdAt: decision.createdAt,
                dueDate: decision.dueDate,
                priority: decision.status === 'review' ? 'high' : 'normal',
                ownerId: decision.ownerId,
                ownerName: decision.ownerName,
                status: decision.status,
                sourceType: 'workspace_decision',
            })),
            ...messages.map((message) => buildInboxItem({
                type: 'message',
                sourceId: message._id,
                title: String(message.content || '').slice(0, 120),
                description: `Message from ${message.senderName || 'Unknown'}`,
                channel: room.name,
                createdBy: message.senderId,
                createdByName: message.senderName,
                createdAt: message.createdAt,
                dueDate: null,
                priority: 'normal',
                ownerId: '',
                ownerName: '',
                status: 'new',
                sourceType: 'room_message',
            })),
        ];

        if (filter === 'mine') {
            items = items.filter((item) => item.ownerId === req.userId);
        } else if (filter === 'team') {
            items = items.filter((item) => item.ownerId && item.ownerId !== req.userId);
        } else if (filter === 'unassigned') {
            items = items.filter((item) => !item.ownerId);
        } else if (filter === 'overdue') {
            items = items.filter((item) => item.sla === 'late');
        }

        if (q) {
            items = items.filter((item) =>
                item.title.toLowerCase().includes(q) ||
                item.description.toLowerCase().includes(q) ||
                item.channel.toLowerCase().includes(q)
            );
        }

        items.sort((a, b) => {
            if (b.slaRisk !== a.slaRisk) return b.slaRisk - a.slaRisk;
            const aTime = new Date(a.createdAt || 0).getTime();
            const bTime = new Date(b.createdAt || 0).getTime();
            return bTime - aTime;
        });

        const paged = items.slice(0, limit);
        const nextCursor = paged.length === limit
            ? new Date(paged[paged.length - 1].createdAt || Date.now()).toISOString()
            : null;

        res.json({
            ok: true,
            items: paged,
            count: paged.length,
            nextCursor,
            requestId: `inbox-${Date.now()}`,
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/my-day', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const myDay = await getMyDay(req.params.id, req.userId);

        logEvent('my_day_opened', {
            userId: req.userId,
            roomId: req.params.id,
            timestamp: new Date().toISOString(),
            sessionId: req.userId,
        });

        // Ensure all sections are arrays even if empty
        const response = {
            ok: myDay.ok !== false,
            top3: myDay.top3 || [],
            blocked: myDay.blocked || [],
            dueToday: myDay.dueToday || [],
            waitingFor: myDay.waitingFor || [],
            requestId: myDay.requestId,
            computedAt: myDay.computedAt,
        };

        // Set cache header: 1 minute (cache is good enough for daily cockpit)
        res.set('Cache-Control', 'private, max-age=60');
        res.json(response);
    } catch (err) {
        console.error('[rooms] my-day error:', err);
        next(err);
    }
});

router.post('/:id/tasks/:taskId/action', validateBody(validateTaskActionPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { taskId } = req.params;
        const action = req.validatedBody;

        logEvent('my_day_action_clicked', {
            userId: req.userId,
            roomId: req.params.id,
            actionType: action.type,
            timestamp: new Date().toISOString(),
            sessionId: req.userId,
        });

        let result;
        switch (action.type) {
            case 'mark_done':
                result = await markTaskDone(req.params.id, taskId, req.userId);
                break;

            case 'defer':
                result = await deferTask(req.params.id, taskId, action.deferUntil, req.userId);
                break;

            case 'reassign':
                result = await reassignTask(
                    req.params.id,
                    taskId,
                    action.newOwnerId,
                    action.newOwnerName,
                    req.userId
                );
                break;

            case 'update_priority':
                result = await updateTaskPriority(req.params.id, taskId, action.priority, req.userId);
                break;

            case 'add_note':
                result = await addTaskNote(
                    req.params.id,
                    taskId,
                    action.note,
                    req.userId,
                    req.displayName
                );
                break;

            default:
                return res.status(400).json({ error: `Unknown action type: ${action.type}` });
        }

        res.json({
            ok: true,
            action: action.type,
            taskId,
            result,
            requestId: `task-action-${Date.now()}`,
        });

        logEvent('my_day_action_completed', {
            userId: req.userId,
            roomId: req.params.id,
            taskId,
            actionType: action.type,
            timestamp: new Date().toISOString(),
            sessionId: req.userId,
        });
    } catch (err) {
        console.error('[rooms] task action error:', err);
        next(err);
    }
});

router.get('/:id/nudges', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        // E1-05: Generate nudge candidates for current user
        const nudges = await generateNudgeCandidates(req.params.id, req.userId, {
            includeWaitingFor: true,
        });

        // Log one event per nudge so schema fields remain consistent.
        for (const nudge of nudges) {
            logEvent('my_day_nudge_shown', {
                userId: req.userId,
                roomId: req.params.id,
                nudgeType: nudge.type,
                taskId: nudge.taskId,
                timestamp: new Date().toISOString(),
            });
        }

        res.json({
            ok: true,
            nudges,
            count: nudges.length,
            requestId: `nudges-${Date.now()}`,
        });
    } catch (err) {
        console.error('[rooms] nudges error:', err);
        next(err);
    }
});

router.get('/:id/reminders', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const reminders = await generateReminderCards(req.params.id, req.userId);

        for (const reminder of reminders) {
            logEvent('my_day_reminder_shown', {
                userId: req.userId,
                roomId: req.params.id,
                reminderType: reminder.type,
                taskId: reminder.taskId,
                timestamp: new Date().toISOString(),
            });
        }

        res.json({
            ok: true,
            reminders,
            count: reminders.length,
            requestId: `reminders-${Date.now()}`,
        });
    } catch (err) {
        console.error('[rooms] reminders error:', err);
        next(err);
    }
});

router.post('/:id/reminders/:reminderId/snooze', validateBody(validateReminderSnoozePayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const result = snoozeReminder(
            req.params.id,
            req.userId,
            req.params.reminderId,
            req.validatedBody.snoozeMinutes
        );

        logEvent('my_day_reminder_snoozed', {
            userId: req.userId,
            roomId: req.params.id,
            reminderId: req.params.reminderId,
            snoozeMinutes: req.validatedBody.snoozeMinutes,
            timestamp: new Date().toISOString(),
        });

        res.json({ ok: true, ...result });
    } catch (err) {
        console.error('[rooms] reminder snooze error:', err);
        next(err);
    }
});

router.post('/:id/nudges/:nudgeId/dismiss', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { reason = '' } = req.body || {};

        // Record interaction for analytics
        const interaction = await recordNudgeInteraction(
            req.params.id,
            req.userId,
            req.params.nudgeId,
            'dismiss',
            { reason }
        );

        // Log event
        logEvent('my_day_nudge_dismissed', {
            userId: req.userId,
            roomId: req.params.id,
            nudgeId: req.params.nudgeId,
            reason,
            timestamp: new Date().toISOString(),
        });

        res.json({ ok: true, interaction });
    } catch (err) {
        console.error('[rooms] nudge dismiss error:', err);
        next(err);
    }
});

router.get('/:id/instrumentation/des', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        // Ops hub only (stub: check authorization)
        // For MVP, allow all members
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        // E1-06: Compute DES proxy
        const desData = await computeDESProxy();

        res.json({
            ok: true,
            des: desData.des,
            date: desData.date,
            successfulUsers: desData.successfulUsers,
            requestId: `des-${Date.now()}`,
        });
    } catch (err) {
        console.error('[rooms] instrumentation des error:', err);
        next(err);
    }
});

router.get('/:id/instrumentation/daily-snapshot', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;

        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        // E1-06: Generate daily snapshot
        const snapshot = generateDailySnapshot();

        // Return as markdown or JSON
        const format = req.query.format === 'json' ? 'json' : 'markdown';
        if (format === 'markdown') {
            res.set('Content-Type', 'text/markdown');
            res.send(snapshot);
        } else {
            res.json({
                ok: true,
                markdown: snapshot,
                requestId: `snapshot-${Date.now()}`,
            });
        }
    } catch (err) {
        console.error('[rooms] instrumentation snapshot error:', err);
        next(err);
    }
});

router.post('/:id/decision-pack/share', validateBody(validateDecisionPackSharePayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { target, mode, note, idempotencyKey } = req.validatedBody;
        const connector = target === 'csv' ? null : getExportConnector(target);
        if (target !== 'csv') {
            if (!connector) {
                return res.status(400).json({ error: 'Unsupported target' });
            }
            if (!connector.isConfigured(room)) {
                return res.status(412).json({ error: `${connector.target} integration is not configured` });
            }
        }

        const { decisions, tasks } = await loadDecisionPackData(req.params.id, {
            limit: 10,
            includeOpenTasks: mode === 'checklist',
        });
        const readiness = evaluateDecisionPackReadiness({ decisions, tasks });
        const generatedAt = new Date();
        const summary = formatDecisionPackMarkdown({ room, decisions, tasks, generatedAt, mode });
        const csvContent = formatDecisionPackCsv({
            room,
            decisions,
            tasks,
            generatedAt,
        });
        const csvFileName = `decision-pack-${String(room._id || req.params.id)}-${generatedAt
            .toISOString()
            .slice(0, 10)}.csv`;

        const history = await RoomShareHistory.create({
            roomId: room._id,
            artifactId: null,
            target: target === 'csv' ? 'csv' : connector.target,
            status: 'pending',
            idempotencyKey: idempotencyKey || '',
            actorId: req.userId,
            actorName: req.displayName,
            note: note || 'Decision Pack export',
            summary: summary.slice(0, 1000),
        });

        if (target === 'csv') {
            history.status = 'success';
            history.metadata = {
                format: 'csv',
                fileName: csvFileName,
                rowCount: Math.max(0, decisions.length + tasks.length),
            };
            await history.save();
            return res.status(201).json({
                share: {
                    id: String(history._id),
                    target: history.target,
                    status: history.status,
                    externalUrl: history.externalUrl,
                    mode,
                },
                csv: {
                    fileName: csvFileName,
                    content: csvContent,
                },
                readiness,
            });
        }

        try {
            const outcome = await executeWithRetry(
                () => connector.send({ room, summary, note: note || 'Decision Pack export' }),
                { maxAttempts: 3, baseDelayMs: 200 }
            );
            history.status = 'success';
            history.retries = Math.max(0, Number(outcome.attempts || 1) - 1);
            history.externalId = outcome.result?.externalId || '';
            history.externalUrl = outcome.result?.externalUrl || '';
            history.metadata = outcome.result?.metadata || null;
            await history.save();
            return res.status(201).json({
                share: {
                    id: String(history._id),
                    target: history.target,
                    status: history.status,
                    externalUrl: history.externalUrl,
                    mode,
                },
                readiness,
            });
        } catch (err) {
            history.status = 'failed';
            history.retries = Number(err?.retries || 0);
            history.errorCode = String(err?.code || err?.status || 'export_failed').slice(0, 120);
            history.errorMessage = String(err?.message || 'Export failed').slice(0, 3000);
            await history.save();
            return res.status(502).json({ error: 'Decision Pack export failed', code: history.errorCode, readiness });
        }
    } catch (err) {
        next(err);
    }
});

router.post('/:id/decision-pack/events', validateBody(validateDecisionPackEventPayload), async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const event = await RoomDecisionPackEvent.create({
            roomId: req.params.id,
            userId: req.userId,
            eventType: req.validatedBody.eventType,
            mode: req.validatedBody.mode,
            target: req.validatedBody.target || '',
            metadata: req.validatedBody.metadata || null,
        });

        return res.status(201).json({
            event: {
                id: String(event._id),
                eventType: event.eventType,
                mode: event.mode,
                target: event.target,
                createdAt: event.createdAt,
            },
        });
    } catch (err) {
        next(err);
    }
});

router.get('/:id/decision-pack/aggregate', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { sinceDays } = validateDecisionPackAggregateQuery(req.query || {});
        const since = new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000);
        const stats = await RoomDecisionPackEvent.aggregate([
            { $match: { roomId: room._id, createdAt: { $gte: since } } },
            {
                $group: {
                    _id: '$eventType',
                    count: { $sum: 1 },
                },
            },
        ]);

        const byType = {
            viewed: 0,
            shared: 0,
            share_failed: 0,
        };
        stats.forEach((item) => {
            if (item?._id && Object.hasOwn(byType, item._id)) {
                byType[item._id] = Number(item.count || 0);
            }
        });

        return res.json({
            aggregate: {
                sinceDays,
                since: since.toISOString(),
                events: byType,
            },
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
            savedChallenge.toObject(),
            req.requestId || null
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
router.post('/:id/join', validateBody(validateEmptyBody), async (req, res) => {
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

router.post('/:id/artifacts/:artifactId/versions/:versionId/approve', validateBody(validateEmptyBody), async (req, res, next) => {
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
        if (!canReviewArtifacts(room, req.userId)) {
            return res.status(403).json({ error: 'Owner or member role required for artifact comments' });
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
            const { status: targetStatus } = req.validatedBody;

            const room = await loadRoomOr404(req.params.id, res);
            if (!room) return;

            // Only members and owners can update artifact status (guests excluded)
            if (!canReviewArtifacts(room, req.userId)) {
                return res.status(403).json({ error: 'Owner role required for this transition' });
            }

            // Check owner-only transitions before artifact lookup
            const isOwner = isRoomOwner(room, req.userId);
            if ((targetStatus === 'validated' || targetStatus === 'archived') && !isOwner) {
                return res.status(403).json({
                    error: 'Owner role required for this transition',
                    code: 'FORBIDDEN'
                });
            }

            const artifact = await RoomArtifact.findOne({
                _id: req.params.artifactId,
                roomId: req.params.id,
            });
            if (!artifact) {
                return res.status(404).json({ error: 'Artifact not found' });
            }

            // Validate state machine transitions
            const currentStatus = artifact.status || 'draft';
            const validTransitions = {
                draft: ['review', 'archived'],
                review: ['validated', 'archived'],
                validated: ['archived'],
                archived: [],
            };

            if (targetStatus === currentStatus) {
                return res.status(400).json({
                    error: `Status is already "${currentStatus}"`,
                    code: 'INVALID_TRANSITION'
                });
            }

            if (!(validTransitions[currentStatus]?.includes(targetStatus))) {
                return res.status(400).json({
                    error: `Cannot transition from "${currentStatus}" to "${targetStatus}"`,
                    code: 'INVALID_TRANSITION'
                });
            }

            artifact.status = targetStatus;
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
            if (!canReviewArtifacts(room, req.userId)) {
                return res.status(403).json({ error: 'Owner or member role required for artifact comments' });
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
        await enforceRouteRateLimit(
            req,
            `room-mission:${req.userId}:${req.params.id}`,
            12,
            'Rate limit exceeded for room missions'
        );

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
        await enforceRouteRateLimit(
            req,
            `room-search:${req.userId}:${req.params.id}`,
            20,
            'Rate limit exceeded for room search'
        );

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
        await enforceRouteRateLimit(
            req,
            `room-share:${req.userId}:${req.params.id}`,
            12,
            'Rate limit exceeded for room share'
        );
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
        const { rating, ratingLabel, reason, metadata } = req.validatedBody;

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
            existing.ratingLabel = ratingLabel;
            existing.reason = reason;
            existing.metadata = metadata;
        } else {
            message.feedback.push({ userId: req.userId, rating, ratingLabel, reason, metadata });
        }
        await message.save();

        await RoomFeedbackEvent.findOneAndUpdate(
            {
                roomId: req.params.id,
                messageId: req.params.msgId,
                userId: req.userId,
            },
            {
                $set: {
                    rating,
                    ratingLabel,
                    reason,
                    metadata,
                },
            },
            {
                upsert: true,
                new: true,
                setDefaultsOnInsert: true,
            }
        );

        const thumbsUp = message.feedback.filter((f) => f.rating === 1).length;
        const mixed = message.feedback.filter((f) => f.rating === 0).length;
        const thumbsDown = message.feedback.filter((f) => f.rating === -1).length;

        res.json({
            ok: true,
            messageId: String(message._id),
            thumbsUp,
            mixed,
            thumbsDown,
            userRating: rating,
            userRatingLabel: ratingLabel,
            userReason: reason,
        });
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/rooms/:id/feedback/aggregate
 * Return basic rating aggregates for product analytics seed.
 */
router.get('/:id/feedback/aggregate', async (req, res, next) => {
    try {
        const room = await loadRoomOr404(req.params.id, res);
        if (!room) return;
        if (!isRoomMember(room, req.userId)) {
            return res.status(403).json({ error: 'Not a member of this room' });
        }

        const { from, to, rating, ratingLabel } = validateFeedbackAggregateQuery(req.query || {});
        const match = {
            roomId: req.params.id,
            createdAt: {
                $gte: from,
                $lte: to,
            },
        };
        if (Number.isFinite(rating)) {
            match.rating = rating;
        }

        const events = await RoomFeedbackEvent.find(match).sort({ createdAt: 1 }).lean();

        const byRating = {
            pertinent: 0,
            moyen: 0,
            hors_sujet: 0,
        };
        const byDayMap = new Map();

        for (const event of events) {
            const label = String(event?.ratingLabel || '').trim();
            if (byRating[label] !== undefined) {
                byRating[label] += 1;
            }

            const day = new Date(event.createdAt).toISOString().slice(0, 10);
            if (!byDayMap.has(day)) {
                byDayMap.set(day, {
                    day,
                    pertinent: 0,
                    moyen: 0,
                    hors_sujet: 0,
                });
            }
            const slot = byDayMap.get(day);
            if (slot[label] !== undefined) {
                slot[label] += 1;
            }
        }

        const byDay = [...byDayMap.values()];
        const filteredByRating = ratingLabel
            ? { [ratingLabel]: byRating[ratingLabel] || 0 }
            : byRating;

        return res.json({
            ok: true,
            roomId: String(req.params.id),
            from: from.toISOString(),
            to: to.toISOString(),
            total: events.length,
            byRating: filteredByRating,
            byDay,
        });
    } catch (err) {
        next(err);
    }
});

export default router;
