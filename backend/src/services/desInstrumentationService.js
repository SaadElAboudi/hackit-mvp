/**
 * desInstrumentationService.js — E1-06: DES instrumentation baseline
 *
 * DES = Daily Execution Success
 * Tracks: my_day_opened, my_day_action_clicked, my_day_action_completed
 * Computes: users with >= 3 completed priority actions/day
 *
 * Event schema is versioned for backward compat.
 */

import mongoose from 'mongoose';

// Simple in-memory event store for MVP (future: persistent store)
const eventLog = [];
const EVENT_SCHEMA_VERSION = '1.0';

/**
 * Event schema for validation.
 */
const eventSchemas = {
    my_day_opened: {
        version: EVENT_SCHEMA_VERSION,
        fields: ['userId', 'roomId', 'timestamp', 'sessionId'],
    },
    my_day_action_clicked: {
        version: EVENT_SCHEMA_VERSION,
        fields: ['userId', 'roomId', 'actionType', 'timestamp', 'sessionId'],
    },
    my_day_action_completed: {
        version: EVENT_SCHEMA_VERSION,
        fields: ['userId', 'roomId', 'taskId', 'actionType', 'timestamp', 'sessionId'],
    },
    my_day_nudge_shown: {
        version: EVENT_SCHEMA_VERSION,
        fields: ['userId', 'roomId', 'nudgeType', 'taskId', 'timestamp'],
    },
    my_day_nudge_dismissed: {
        version: EVENT_SCHEMA_VERSION,
        fields: ['userId', 'roomId', 'nudgeId', 'reason', 'timestamp'],
    },
};

/**
 * Validate and log an event.
 * @param {string} eventType - Type of event
 * @param {object} payload - Event payload
 * @returns {boolean} - true if validated and logged
 */
export function logEvent(eventType, payload) {
    try {
        const schema = eventSchemas[eventType];
        if (!schema) {
            console.warn(`[desInstrumentation] Unknown event type: ${eventType}`);
            return false;
        }

        // Validate required fields
        const missing = schema.fields.filter((f) => !payload[f]);
        if (missing.length > 0) {
            console.warn(`[desInstrumentation] Missing fields for ${eventType}:`, missing);
            return false;
        }

        const event = {
            type: eventType,
            version: schema.version,
            payload,
            recordedAt: new Date().toISOString(),
        };

        eventLog.push(event);

        // Keep only last 10000 events in memory for MVP
        if (eventLog.length > 10000) {
            eventLog.shift();
        }

        return true;
    } catch (err) {
        console.error('[desInstrumentation] Event logging error:', err);
        return false;
    }
}

/**
 * Compute DES (Daily Execution Success) proxy.
 * DES = count of unique users who completed >= 3 priority actions today.
 *
 * @returns {Promise<object>} - { des, detailsByUser, date }
 */
export async function computeDESProxy() {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    try {
        // Filter events from today
        const todaysEvents = eventLog.filter((e) => {
            const eventTime = new Date(e.recordedAt);
            return eventTime >= todayStart;
        });

        // Count completed actions by user
        const userCompletions = {};
        todaysEvents.forEach((e) => {
            if (e.type === 'my_day_action_completed') {
                const userId = e.payload.userId;
                userCompletions[userId] = (userCompletions[userId] || 0) + 1;
            }
        });

        // Filter users with >= 3 completions
        const successfulUsers = Object.entries(userCompletions)
            .filter(([_, count]) => count >= 3)
            .map(([userId, count]) => ({ userId, completions: count }));

        const des = successfulUsers.length;

        return {
            ok: true,
            date: todayStart.toISOString().split('T')[0],
            des,
            successfulUsers,
            detailsByUser: userCompletions,
            todaysEventCount: todaysEvents.length,
        };
    } catch (err) {
        console.error('[desInstrumentation] DES computation error:', err);
        return { ok: false, error: err.message };
    }
}

/**
 * Generate daily snapshot report (markdown format).
 * @returns {string} - markdown report
 */
export function generateDailySnapshot() {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const dateStr = todayStart.toISOString().split('T')[0];

    try {
        const todaysEvents = eventLog.filter((e) => {
            const eventTime = new Date(e.recordedAt);
            return eventTime >= todayStart;
        });

        const eventCounts = {};
        todaysEvents.forEach((e) => {
            eventCounts[e.type] = (eventCounts[e.type] || 0) + 1;
        });

        // Group by user
        const byUser = {};
        todaysEvents.forEach((e) => {
            const userId = e.payload.userId;
            if (!byUser[userId]) {
                byUser[userId] = { opens: 0, clicks: 0, completions: 0, nudges: 0 };
            }
            if (e.type === 'my_day_opened') byUser[userId].opens++;
            if (e.type === 'my_day_action_clicked') byUser[userId].clicks++;
            if (e.type === 'my_day_action_completed') byUser[userId].completions++;
            if (e.type === 'my_day_nudge_shown') byUser[userId].nudges++;
        });

        let markdown = `# My Day Daily Snapshot — ${dateStr}\n\n`;
        markdown += `Generated: ${now.toISOString()}\n\n`;

        markdown += `## Summary\n`;
        markdown += `- Total Events: ${todaysEvents.length}\n`;
        markdown += `- Active Users: ${Object.keys(byUser).length}\n`;
        markdown += `- My Day Opens: ${eventCounts['my_day_opened'] || 0}\n`;
        markdown += `- Actions Clicked: ${eventCounts['my_day_action_clicked'] || 0}\n`;
        markdown += `- Actions Completed: ${eventCounts['my_day_action_completed'] || 0}\n`;
        markdown += `- Nudges Shown: ${eventCounts['my_day_nudge_shown'] || 0}\n\n`;

        markdown += `## DES Proxy\n`;
        const desData = computeDESProxy();
        markdown += `- Users with >=3 completions: ${desData.des}\n\n`;

        markdown += `## By User\n`;
        markdown += `| User | Opens | Clicks | Completions | Nudges |\n`;
        markdown += `|------|-------|--------|-------------|--------|\n`;
        Object.entries(byUser)
            .sort((a, b) => b[1].completions - a[1].completions)
            .forEach(([userId, stats]) => {
                markdown += `| ${userId.slice(-8)} | ${stats.opens} | ${stats.clicks} | ${stats.completions} | ${stats.nudges} |\n`;
            });

        markdown += `\n## Event Type Distribution\n`;
        Object.entries(eventCounts)
            .sort((a, b) => b[1] - a[1])
            .forEach(([type, count]) => {
                markdown += `- ${type}: ${count}\n`;
            });

        return markdown;
    } catch (err) {
        console.error('[desInstrumentation] Snapshot generation error:', err);
        return `# Error generating snapshot: ${err.message}`;
    }
}

/**
 * Get all events (for debugging).
 */
export function getAllEvents(limit = 100) {
    return eventLog.slice(-limit);
}

/**
 * Clear all events (for testing).
 */
export function clearEvents() {
    eventLog.length = 0;
}
