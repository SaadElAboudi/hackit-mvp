/**
 * myDayService.js — My Day aggregation logic.
 *
 * Computes daily execution context: top 3 priorities, blockers, due-today, waiting-for.
 * Used by E1-01 (My Day API endpoint) and E1-02 (prioritization service).
 */

import WorkspaceTask from '../models/WorkspaceTask.js';

/**
 * Compute risk score for a task.
 * Higher = more urgent.
 * Factors: overdue, blocked, age, dependencies (stub).
 */
function computeRiskScore(task, now = new Date()) {
    let score = 0;

    // Overdue = +50 points
    if (task.dueDate && new Date(task.dueDate) < now) {
        const daysOverdue = Math.ceil((now - new Date(task.dueDate)) / (1000 * 60 * 60 * 24));
        score += 50 + daysOverdue * 5; // extra points per day overdue
    }

    // Blocked = +40 points
    if (task.status === 'blocked') {
        score += 40;
    }

    // Due within 24h = +30 points
    if (
        task.dueDate &&
        new Date(task.dueDate) > now &&
        new Date(task.dueDate) <= new Date(now.getTime() + 86400000)
    ) {
        score += 30;
    }

    // Age (older tasks = +2 per week) = +2 points per week
    if (task.createdAt) {
        const weeksOld = Math.floor((now - new Date(task.createdAt)) / (1000 * 60 * 60 * 24 * 7));
        score += Math.min(weeksOld * 2, 15); // cap at 15 points for age
    }

    return score;
}

/**
 * Aggregate My Day sections for a user in a room.
 *
 * @param roomId - Room object ID
 * @param userId - Current user ID
 * @returns { top3, blocked, dueToday, waitingFor }
 */
export async function getMyDay(roomId, userId) {
    try {
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const todayEnd = new Date(todayStart.getTime() + 86400000);

        // Get all open tasks for this room (exclude completed)
        const tasks = await WorkspaceTask.find({
            roomId: roomId,
            status: { $ne: 'done' },
            createdAt: { $exists: true },
        })
            .lean()
            .exec();

        if (!tasks || tasks.length === 0) {
            return {
                top3: [],
                blocked: [],
                dueToday: [],
                waitingFor: [],
                requestId: `my-day-${Date.now()}`,
            };
        }

        // Compute risk score for each task
        const scoredTasks = tasks.map((task) => ({
            ...task,
            riskScore: computeRiskScore(task, now),
        }));

        // Section 1: Top 3 (highest risk score, not assigned to others waiting on us)
        const top3 = scoredTasks
            .filter((t) => t.ownerId === userId || !t.ownerId) // tasks assigned to current user or unassigned
            .sort((a, b) => b.riskScore - a.riskScore)
            .slice(0, 3)
            .map((task) => formatTaskItem(task, 'top3'));

        // Section 2: Blocked (any task with status blocked)
        const blocked = scoredTasks
            .filter((t) => t.status === 'blocked')
            .sort((a, b) => b.riskScore - a.riskScore)
            .map((task) => formatTaskItem(task, 'blocked'));

        // Section 3: Due Today (dueDate is today, not yet done)
        const dueToday = scoredTasks
            .filter((t) => t.dueDate && new Date(t.dueDate) >= todayStart && new Date(t.dueDate) < todayEnd)
            .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate))
            .map((task) => formatTaskItem(task, 'dueToday'));

        // Section 4: Waiting For (assigned to other users, current user is not owner)
        const waitingFor = scoredTasks
            .filter((t) => t.ownerId && t.ownerId !== userId && t.status !== 'done')
            .sort((a, b) => b.riskScore - a.riskScore)
            .slice(0, 5) // limit to 5 most urgent
            .map((task) => formatTaskItem(task, 'waitingFor'));

        return {
            ok: true,
            top3,
            blocked,
            dueToday,
            waitingFor,
            requestId: `my-day-${Date.now()}`,
            computedAt: now.toISOString(),
        };
    } catch (error) {
        console.error('[myDayService] getMyDay error:', error);
        return {
            ok: false,
            error: error.message,
            top3: [],
            blocked: [],
            dueToday: [],
            waitingFor: [],
        };
    }
}

/**
 * Format a task for My Day response.
 * Includes risk metadata and whyRanked explanation.
 */
function formatTaskItem(task, section) {
    return {
        id: task._id.toString(),
        kind: 'task',
        title: task.title,
        description: task.description ? task.description.slice(0, 150) : '',
        ownerName: task.ownerName || 'Unassigned',
        dueDate: task.dueDate ? new Date(task.dueDate).toISOString() : null,
        priority: getPriorityLabel(task.riskScore),
        status: task.status,
        sourceUrl: `/task/${task._id}`,
        whyRanked: generateWhyRanked(task, section),
        riskScore: task.riskScore,
        createdAt: task.createdAt.toISOString(),
    };
}

/**
 * Simple priority label based on risk score.
 */
function getPriorityLabel(riskScore) {
    if (riskScore >= 50) return 'urgent';
    if (riskScore >= 30) return 'high';
    if (riskScore >= 10) return 'medium';
    return 'low';
}

/**
 * Generate short explanation for why task was ranked.
 */
function generateWhyRanked(task, section) {
    if (section === 'top3') {
        if (task.status === 'blocked') return 'Blocked and needs attention';
        if (task.dueDate) {
            const daysUntilDue = Math.ceil((new Date(task.dueDate) - new Date()) / (1000 * 60 * 60 * 24));
            if (daysUntilDue < 0) return `Overdue by ${Math.abs(daysUntilDue)} day(s)`;
            if (daysUntilDue === 0) return 'Due today';
            return `Due in ${daysUntilDue} day(s)`;
        }
        return 'High priority based on age and status';
    }

    if (section === 'blocked') return 'Task is blocked; needs unblocking';
    if (section === 'dueToday') return 'Due today; prioritize first';
    if (section === 'waitingFor') return 'Waiting on this task to progress';

    return '';
}

/**
 * Compute total summary stats for My Day (used by dashboard).
 */
export async function getMyDayStats(roomId, userId) {
    const myDay = await getMyDay(roomId, userId);
    return {
        totalTop3: myDay.top3.length,
        totalBlocked: myDay.blocked.length,
        totalDueToday: myDay.dueToday.length,
        totalWaitingFor: myDay.waitingFor.length,
        urgentCount: [...myDay.top3, ...myDay.blocked].filter((t) => t.priority === 'urgent').length,
    };
}
