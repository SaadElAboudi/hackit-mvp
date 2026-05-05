/**
 * nudgeService.js — E1-05: In-app nudges MVP
 *
 * Generates nudge candidates for tasks that need attention:
 * - Overdue: task.dueDate < now
 * - Due soon: task.dueDate within 24h
 * - Waiting too long: task assigned to other, no update for N days
 *
 * Each nudge is non-intrusive (dismissable, snoozable) and tracked for analytics.
 */

import WorkspaceTask from '../models/WorkspaceTask.js';

/**
 * Generate nudge candidates for a user in a room.
 * @param {string} roomId - Room object ID
 * @param {string} userId - Target user ID
 * @param {object} options - { includeWaitingFor: boolean }
 * @returns {Promise<Array>} - array of nudges
 */
export async function generateNudgeCandidates(roomId, userId, options = {}) {
    const { includeWaitingFor = true } = options;
    const now = new Date();
    const nowMs = now.getTime();
    const oneDayMs = 86400000;

    try {
        const tasks = await WorkspaceTask.find({
            roomId: roomId,
            status: { $ne: 'done' },
        })
            .lean()
            .exec();

        const nudges = [];

        for (const task of tasks) {
            // Skip if already snoozed (stub: no snoozed_until field yet)
            // if (task.snoozed_until && task.snoozed_until > now) continue;

            // Type 1: Overdue tasks assigned to current user
            if (task.ownerId === userId && task.dueDate) {
                const dueDate = new Date(task.dueDate);
                if (dueDate < now) {
                    const daysOverdue = Math.ceil((now - dueDate) / oneDayMs);
                    nudges.push({
                        id: `nudge-overdue-${task._id}`,
                        taskId: task._id.toString(),
                        type: 'overdue',
                        urgency: daysOverdue > 7 ? 'critical' : daysOverdue > 3 ? 'high' : 'medium',
                        title: `Overdue: ${task.title}`,
                        subtitle: `Due ${daysOverdue} day${daysOverdue > 1 ? 's' : ''} ago`,
                        message: `This task is ${daysOverdue} day${daysOverdue > 1 ? 's' : ''} overdue. Update status or reassign.`,
                        action: 'open_task',
                        dismissible: true,
                        snoozeable: true,
                    });
                }
            }

            // Type 2: Tasks due within 24h assigned to current user
            if (task.ownerId === userId && task.dueDate && task.status !== 'done') {
                const dueDate = new Date(task.dueDate);
                const dueDateMs = dueDate.getTime();
                if (dueDateMs > nowMs && dueDateMs <= nowMs + oneDayMs) {
                    nudges.push({
                        id: `nudge-dueSoon-${task._id}`,
                        taskId: task._id.toString(),
                        type: 'due_soon',
                        urgency: 'high',
                        title: `Due Soon: ${task.title}`,
                        subtitle: 'Due within 24 hours',
                        message: 'This task is due soon. Mark done when complete.',
                        action: 'open_task',
                        dismissible: true,
                        snoozeable: true,
                    });
                }
            }

            // Type 3: Blocked tasks (assigned to current user)
            if (task.ownerId === userId && task.status === 'blocked') {
                const blockedSince = task.updatedAt ? new Date(task.updatedAt) : null;
                if (blockedSince) {
                    const blockDays = Math.ceil((now - blockedSince) / oneDayMs);
                    if (blockDays >= 1) {
                        nudges.push({
                            id: `nudge-blocked-${task._id}`,
                            taskId: task._id.toString(),
                            type: 'blocked',
                            urgency: blockDays > 3 ? 'high' : 'medium',
                            title: `Blocked: ${task.title}`,
                            subtitle: `Blocked for ${blockDays} day${blockDays > 1 ? 's' : ''}`,
                            message: 'This task is blocked. Update blocker status or reassign.',
                            action: 'open_task',
                            dismissible: true,
                            snoozeable: true,
                        });
                    }
                }
            }

            // Type 4: Waiting for (tasks assigned to others, only show top 3)
            if (includeWaitingFor && task.ownerId && task.ownerId !== userId && task.status !== 'done') {
                const lastUpdate = new Date(task.updatedAt || task.createdAt);
                const daysSinceUpdate = Math.ceil((now - lastUpdate) / oneDayMs);

                if (daysSinceUpdate >= 2) {
                    const ownerName = task.ownerName || 'teammate';
                    nudges.push({
                        id: `nudge-waitingFor-${task._id}`,
                        taskId: task._id.toString(),
                        type: 'waiting_for',
                        urgency: daysSinceUpdate > 7 ? 'high' : 'low',
                        title: `Waiting: ${task.title}`,
                        subtitle: `${daysSinceUpdate} day${daysSinceUpdate > 1 ? 's' : ''} no update from ${ownerName}`,
                        message: `You're waiting on ${ownerName}. Consider pinging them.`,
                        action: 'ping_owner',
                        dismissible: true,
                        snoozeable: false, // Can't snooze others' tasks
                    });
                }
            }
        }

        // Deduplicate and limit to 5 most urgent nudges
        const unique = Array.from(new Map(nudges.map((n) => [n.id, n])).values());
        const sorted = unique.sort((a, b) => {
            const urgencyScore = { critical: 3, high: 2, medium: 1, low: 0 };
            return (urgencyScore[b.urgency] || 0) - (urgencyScore[a.urgency] || 0);
        });

        return sorted.slice(0, 5);
    } catch (error) {
        console.error('[nudgeService] generateNudgeCandidates error:', error);
        return [];
    }
}

/**
 * Record a nudge interaction (dismiss, snooze).
 * @param {string} roomId - Room object ID
 * @param {string} userId - User ID
 * @param {string} nudgeId - Nudge ID
 * @param {string} action - 'dismiss' or 'snooze'
 * @param {object} metadata - { reason, snoozeUntil, ... }
 * @returns {Promise<object>} - interaction record
 */
export async function recordNudgeInteraction(roomId, userId, nudgeId, action, metadata = {}) {
    const interaction = {
        roomId,
        userId,
        nudgeId,
        action, // 'dismiss' or 'snooze'
        reason: metadata.reason || '',
        snoozedUntil: metadata.snoozedUntil || null,
        timestamp: new Date().toISOString(),
        sessionId: metadata.sessionId || '',
    };

    // Future: persist to database (NudgeInteraction model)
    // For MVP, just log and return
    console.log('[nudgeService] nudge interaction recorded:', {
        userId,
        nudgeId,
        action,
        reason: metadata.reason,
    });

    return interaction;
}

/**
 * Compute nudge effectiveness stats.
 * (Stub for future: query NudgeInteraction events)
 */
export async function getNudgeStats(_roomId) {
    return {
        totalGenerated: 0,
        totalDismissed: 0,
        totalSnoozed: 0,
        dismissRate: 0,
        topDismissalReasons: [],
    };
}
