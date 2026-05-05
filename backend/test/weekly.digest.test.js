import test from 'node:test';
import assert from 'node:assert/strict';

const {
    buildWeeklyDigestTemplate,
    extractPatterns,
    buildRecommendations,
} = await import('../src/services/weeklyDigest.js');

await test('Weekly Digest: template generation', async (_t) => {
    const digestData = {
        roomId: 'room-123',
        roomName: 'Engineering Team',
        period: '2026-05-05 - 2026-05-12',
        metrics: [
            { label: 'Tasks Completed', value: 5 },
            { label: 'Decisions Approved', value: 2 },
        ],
        patterns: [
            { type: 'FRICTION', text: '3 friction in deployment' },
        ],
        recommendations: [
            '💪 Increase task velocity',
        ],
    };

    const html = buildWeeklyDigestTemplate(digestData);
    assert.ok(html.includes('<!DOCTYPE html>'));
    assert.ok(html.includes('Engineering Team'));
    assert.ok(html.includes('5'));
});

await test('Weekly Digest: extract patterns', async (_t) => {
    const events = [
        { _id: '1', category: 'deploy', relevance: 'moyen' },
        { _id: '2', category: 'review', relevance: 'pertinent' },
    ];
    const patterns = extractPatterns(events);
    assert.ok(Array.isArray(patterns));
});

await test('Weekly Digest: build recommendations', async (_t) => {
    const recs = buildRecommendations({
        tasksCompleted: 5,
        decisionsApproved: 3,
        feedbackItems: 10,
        patterns: [{ type: 'WIN', text: 'Good' }],
    });
    assert.ok(Array.isArray(recs));
    assert.ok(recs.length > 0);
});
