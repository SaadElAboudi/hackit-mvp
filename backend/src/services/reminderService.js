/**
 * reminderService.js — E1-07/E1-08 reminder rules + snooze
 *
 * Rules (MVP):
 * - overdue_owner: task assigned to user and due date is past
 * - due_soon_owner: task assigned to user and due within 2 hours
 * - blocked_owner: task assigned to user and blocked for >= 1 day
 *
 * Snooze is stored in-memory for MVP.
 */

import WorkspaceTask from '../models/WorkspaceTask.js';

const snoozeStore = new Map();

function getSnoozeKey(roomId, userId, reminderId) {
    return `${roomId}:${userId}:${reminderId}`;
}

function isSnoozed(roomId, userId, reminderId, now) {
    const key = getSnoozeKey(roomId, userId, reminderId);
    const until = snoozeStore.get(key);
    if (!until) return false;
    return new Date(until).getTime() > now.getTime();
}

function urgencyToSeverity(score) {
    if (score >= 90) return 'critical';
    if (score >= 70) return 'high';
    if (score >= 40) return 'medium';
    return 'low';
}

export async function generateReminderCards(roomId, userId) {
    const now = new Date();
    const nowMs = now.getTime();
    const oneHourMs = 60 * 60 * 1000;
    const oneDayMs = 24 * oneHourMs;

    const tasks = await WorkspaceTask.find({
        roomId,
        status: { $ne: 'done' },
    })
        .lean()
        .exec();

    const reminders = [];

    for (const task of tasks) {
        if (task.ownerId !== userId) continue;

        if (task.dueDate) {
            const dueMs = new Date(task.dueDate).getTime();
            const overdueMs = nowMs - dueMs;

            if (overdueMs > 0) {
                const overdueHours = Math.max(1, Math.floor(overdueMs / oneHourMs));
                const severity = urgencyToSeverity(70 + Math.min(30, Math.floor(overdueHours / 4)));
                const reminderId = `reminder-overdue-${task._id}`;
                if (!isSnoozed(roomId, userId, reminderId, now)) {
                    reminders.push({
                        id: reminderId,
                        taskId: task._id.toString(),
                        type: 'overdue_owner',
                        severity,
                        title: `Overdue reminder: ${task.title}`,
                        subtitle: `${overdueHours}h overdue`,
                        message: 'Please update status, defer, or complete this task.',
                        dueDate: task.dueDate,
                        snoozeOptionsMinutes: [60, 240],
                    });
                }
            } else {
                const diffMs = dueMs - nowMs;
                if (diffMs <= 2 * oneHourMs) {
                    const minsLeft = Math.max(1, Math.floor(diffMs / (60 * 1000)));
                    const severity = minsLeft <= 30 ? 'high' : 'medium';
                    const reminderId = `reminder-dueSoon-${task._id}`;
                    if (!isSnoozed(roomId, userId, reminderId, now)) {
                        reminders.push({
                            id: reminderId,
                            taskId: task._id.toString(),
                            type: 'due_soon_owner',
                            severity,
                            title: `Due soon reminder: ${task.title}`,
                            subtitle: `Due in ${minsLeft} min`,
                            message: 'This task is approaching its deadline.',
                            dueDate: task.dueDate,
                            snoozeOptionsMinutes: [30, 120],
                        });
                    }
                }
            }
        }

        if (task.status === 'blocked') {
            const updatedAtMs = new Date(task.updatedAt || task.createdAt).getTime();
            const blockedMs = nowMs - updatedAtMs;
            if (blockedMs >= oneDayMs) {
                const blockedDays = Math.max(1, Math.floor(blockedMs / oneDayMs));
                const severity = blockedDays >= 3 ? 'high' : 'medium';
                const reminderId = `reminder-blocked-${task._id}`;
                if (!isSnoozed(roomId, userId, reminderId, now)) {
                    reminders.push({
                        id: reminderId,
                        taskId: task._id.toString(),
                        type: 'blocked_owner',
                        severity,
                        title: `Blocked reminder: ${task.title}`,
                        subtitle: `Blocked for ${blockedDays} day${blockedDays > 1 ? 's' : ''}`,
                        message: 'Resolve blocker details or escalate to unblock.',
                        dueDate: task.dueDate || null,
                        snoozeOptionsMinutes: [60, 180],
                    });
                }
            }
        }
    }

    const rank = { critical: 4, high: 3, medium: 2, low: 1 };
    reminders.sort((a, b) => (rank[b.severity] || 0) - (rank[a.severity] || 0));

    return reminders.slice(0, 5);
}

export function snoozeReminder(roomId, userId, reminderId, snoozeMinutes = 60) {
    const minutes = Number(snoozeMinutes);
    const safeMinutes = Number.isFinite(minutes)
        ? Math.max(5, Math.min(24 * 60, Math.floor(minutes)))
        : 60;

    const snoozedUntil = new Date(Date.now() + safeMinutes * 60 * 1000).toISOString();
    const key = getSnoozeKey(roomId, userId, reminderId);
    snoozeStore.set(key, snoozedUntil);

    return {
        ok: true,
        reminderId,
        snoozedUntil,
        snoozeMinutes: safeMinutes,
    };
}
