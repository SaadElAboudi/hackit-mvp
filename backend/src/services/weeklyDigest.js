import cron from 'node-cron';

import RoomWeeklyDigest from '../models/roomWeeklyDigest.js';
import Room from '../models/Room.js';
import WorkspaceTask from '../models/WorkspaceTask.js';
import WorkspaceDecision from '../models/WorkspaceDecision.js';
import RoomFeedbackEvent from '../models/RoomFeedbackEvent.js';

/**
 * buildWeeklyDigestTemplate: Generates email-friendly digest HTML.
 * Includes metrics, patterns, recommendations.
 */
function buildWeeklyDigestTemplate(digestData) {
    const { roomName, period, metrics, patterns, recommendations } = digestData;

    const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 24px; text-align: center; }
        .header h1 { margin: 0; font-size: 24px; }
        .header p { margin: 8px 0 0; opacity: 0.9; }
        .section { padding: 20px; border-bottom: 1px solid #eee; }
        .section:last-child { border-bottom: none; }
        .section h2 { margin: 0 0 12px; font-size: 16px; color: #333; }
        .metric { display: inline-block; background: #f0f4ff; padding: 12px 16px; border-radius: 6px; margin-right: 12px; margin-bottom: 8px; }
        .metric-label { font-size: 11px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
        .metric-value { font-size: 18px; font-weight: 700; color: #667eea; }
        .pattern { background: #fafafa; padding: 12px; border-radius: 6px; margin-bottom: 8px; border-left: 3px solid #667eea; }
        .pattern-type { font-size: 11px; color: #999; text-transform: uppercase; }
        .pattern-text { font-size: 13px; color: #333; font-weight: 500; }
        .cta { background: #667eea; color: white; padding: 12px 20px; border-radius: 6px; text-decoration: none; display: inline-block; margin-top: 12px; }
        .footer { background: #f9f9f9; padding: 16px 20px; font-size: 11px; color: #999; text-align: center; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Weekly Digest</h1>
          <p>${roomName} • ${period}</p>
        </div>
        
        <div class="section">
          <h2>📊 Metrics</h2>
          ${metrics.map(m => `
            <div class="metric">
              <div class="metric-label">${m.label}</div>
              <div class="metric-value">${m.value}</div>
            </div>
          `).join('')}
        </div>
        
        <div class="section">
          <h2>🔍 Key Patterns</h2>
          ${patterns.map(p => `
            <div class="pattern">
              <div class="pattern-type">${p.type}</div>
              <div class="pattern-text">${p.text}</div>
            </div>
          `).join('')}
        </div>
        
        <div class="section">
          <h2>💡 Recommendations</h2>
          <p style="margin: 0; font-size: 13px; line-height: 1.6; color: #333;">
            ${recommendations.join('<br>')}
          </p>
          <a href="https://hackit.app/rooms/${digestData.roomId}/board" class="cta">View Full Board →</a>
        </div>
        
        <div class="footer">
          <p style="margin: 0;">Hackit MVP • Weekly Digest</p>
          <p style="margin: 4px 0 0;"><a href="#unsubscribe" style="color: #667eea; text-decoration: none;">Manage preferences</a></p>
        </div>
      </div>
    </body>
    </html>
  `;

    return html;
}

/**
 * scheduleWeeklyDigest: Run every Monday at 9am
 */
function scheduleWeeklyDigest() {
    // Cron: "0 9 * * 1" = Monday, 9:00 AM
    cron.schedule('0 9 * * 1', async () => {
        console.log('[WeeklyDigest] Starting scheduled digest generation...');

        try {
            // 1. Get all active rooms
            const rooms = await Room
                .find({ active: true })
                .exec();

            for (const room of rooms) {
                await generateAndSendDigest(room);
            }

            console.log(`[WeeklyDigest] Completed for ${rooms.length} rooms`);
        } catch (err) {
            console.error('[WeeklyDigest] Error:', err);
        }
    });

    console.log('[WeeklyDigest] Scheduler initialized (Monday 9am)');
}

/**
 * generateAndSendDigest: Build digest for room, send email
 */
async function generateAndSendDigest(room) {
    try {
        const { sendEmail } = require('../services/emailService');
        const now = new Date();
        const weekStart = new Date(now);
        weekStart.setDate(now.getDate() - 7);

        // Metrics: count tasks done, decisions approved, feedback items
        const tasksCompleted = await WorkspaceTask
            .countDocuments({
                roomId: room._id,
                status: 'done',
                updatedAt: { $gte: weekStart },
            });

        const decisionsApproved = await WorkspaceDecision
            .countDocuments({
                roomId: room._id,
                status: 'approved',
                updatedAt: { $gte: weekStart },
            });

        const feedbackItems = await RoomFeedbackEvent
            .countDocuments({
                roomId: room._id,
                createdAt: { $gte: weekStart },
            });

        // Patterns (from feedback)
        const feedbackEvents = await RoomFeedbackEvent
            .find({
                roomId: room._id,
                createdAt: { $gte: weekStart },
            })
            .limit(100);

        const patterns = extractPatterns(feedbackEvents);

        // Build digest
        const digestData = {
            roomId: room._id,
            roomName: room.displayName,
            period: `${weekStart.toLocaleDateString()} - ${now.toLocaleDateString()}`,
            metrics: [
                { label: 'Tasks Completed', value: tasksCompleted },
                { label: 'Decisions Approved', value: decisionsApproved },
                { label: 'Feedback Points', value: feedbackItems },
            ],
            patterns: patterns.slice(0, 5),
            recommendations: buildRecommendations({
                tasksCompleted,
                decisionsApproved,
                feedbackItems,
                patterns,
            }),
        };

        // Save digest record
        const digest = new RoomWeeklyDigest({
            roomId: room._id,
            period: weekStart,
            content: digestData,
            emailSent: false,
        });
        await digest.save();

        // Send email to room members
        const emailHtml = buildWeeklyDigestTemplate(digestData);

        for (const member of room.members || []) {
            await sendEmail({
                to: member.email,
                subject: `📊 Weekly Digest: ${room.displayName}`,
                html: emailHtml,
            });
        }

        digest.emailSent = true;
        await digest.save();

        console.log(`[WeeklyDigest] Sent digest for room: ${room.displayName}`);
    } catch (err) {
        console.error(`[WeeklyDigest] Error for room ${room._id}:`, err);
    }
}

/**
 * extractPatterns: Analyze feedback to identify friction/wins
 */
function extractPatterns(feedbackEvents) {
    const patterns = [];

    // Top concerns/wins
    const concerns = {};
    const wins = {};

    for (const f of feedbackEvents) {
        const category = f.category || 'general';
        if (f.relevance === 'pertinent') {
            wins[category] = (wins[category] || 0) + 1;
        } else if (f.relevance === 'moyen') {
            concerns[category] = (concerns[category] || 0) + 1;
        }
    }

    // Add top patterns
    Object.entries(concerns)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 3)
        .forEach(([cat, count]) => {
            patterns.push({
                type: 'FRICTION',
                text: `${count} friction point(s) in ${cat}`,
            });
        });

    Object.entries(wins)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 2)
        .forEach(([cat, count]) => {
            patterns.push({
                type: 'WIN',
                text: `${count} positive feedback from ${cat}`,
            });
        });

    return patterns;
}

/**
 * buildRecommendations: Suggest actions based on metrics
 */
function buildRecommendations({ tasksCompleted, decisionsApproved, feedbackItems, patterns }) {
    const recs = [];

    if (tasksCompleted < 3) {
        recs.push('💪 Increase task velocity: schedule daily 15-min checkins to unblock stuck items');
    }

    if (decisionsApproved < 2) {
        recs.push('⚡ Speed up decisions: use decision templates & require 48-hr feedback windows');
    }

    if (feedbackItems > 20) {
        recs.push('👂 Review friction patterns in upcoming sprint planning');
    }

    if (patterns.length === 0) {
        recs.push('📝 Encourage feedback: post discussion prompts in #feedback channel');
    }

    return recs.length > 0
        ? recs
        : ['✨ Team is in good rhythm! Maintain current cadence.'];
}

export {
    buildWeeklyDigestTemplate,
    scheduleWeeklyDigest,
    generateAndSendDigest,
    extractPatterns,
    buildRecommendations,
};
