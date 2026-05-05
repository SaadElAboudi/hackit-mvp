import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const Room = (await import('../src/models/Room.js')).default;
const RoomMessage = (await import('../src/models/RoomMessage.js')).default;
const RoomFeedbackEvent = (await import('../src/models/RoomFeedbackEvent.js')).default;
const RoomDecisionPackEvent = (await import('../src/models/RoomDecisionPackEvent.js')).default;

const originalReadyStateDescriptor = Object.getOwnPropertyDescriptor(
    mongoose.connection,
    'readyState'
);

function forceMongoReady() {
    Object.defineProperty(mongoose.connection, 'readyState', {
        configurable: true,
        enumerable: true,
        get: () => 1,
    });
}

function restoreMongoReady() {
    if (originalReadyStateDescriptor) {
        Object.defineProperty(
            mongoose.connection,
            'readyState',
            originalReadyStateDescriptor
        );
    }
}

function withStub(object, key, impl) {
    const previous = object[key];
    object[key] = impl;
    return () => {
        object[key] = previous;
    };
}

function leanChain(items) {
    return {
        lean: async () => items,
    };
}

async function requestJson({ port, path, method = 'GET', headers = {} }) {
    return await new Promise((resolve, reject) => {
        const req = http.request(
            {
                host: '127.0.0.1',
                port,
                path,
                method,
                headers,
            },
            (res) => {
                let data = '';
                res.setEncoding('utf8');
                res.on('data', (chunk) => {
                    data += chunk;
                });
                res.on('end', () => resolve({ status: res.statusCode, data }));
            }
        );
        req.on('error', reject);
        req.end();
    });
}

await test('GET /api/rooms/kpi/dashboard returns aggregated KPI metrics', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const restoreFindRooms = withStub(Room, 'find', () =>
        leanChain([{ _id: 'r1' }, { _id: 'r2' }])
    );
    const restoreMessageAggregate = withStub(RoomMessage, 'aggregate', async () => [
        { _id: 'r1' },
    ]);
    const restoreCountAi = withStub(RoomMessage, 'countDocuments', async () => 10);
    const restoreFeedbackFind = withStub(RoomFeedbackEvent, 'find', () =>
        leanChain([
            { ratingLabel: 'pertinent' },
            { ratingLabel: 'pertinent' },
            { ratingLabel: 'moyen' },
            { ratingLabel: 'hors_sujet' },
        ])
    );
    const restoreDecisionAggregate = withStub(
        RoomDecisionPackEvent,
        'aggregate',
        async () => [
            { _id: 'viewed', count: 5 },
            { _id: 'shared', count: 2 },
            { _id: 'share_failed', count: 1 },
        ]
    );

    t.after(() => {
        restoreFindRooms();
        restoreMessageAggregate();
        restoreCountAi();
        restoreFeedbackFind();
        restoreDecisionAggregate();
    });

    const app = createApp();
    const server = app.listen(0);
    t.after(() => server.close());
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    const res = await requestJson({
        port,
        path: '/api/rooms/kpi/dashboard?sinceDays=7',
        headers: { 'x-user-id': 'user_kpi_1' },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.dashboard.sinceDays, 7);
    assert.equal(json.dashboard.totals.roomsTotal, 2);
    assert.equal(json.dashboard.totals.roomsActive, 1);
    assert.equal(json.dashboard.feedback.total, 4);
    assert.equal(json.dashboard.metrics.activationRate, 50);
    assert.equal(json.dashboard.metrics.usefulAnswerRate, 50);
    assert.equal(json.dashboard.metrics.feedbackScore, 0.25);
    assert.equal(json.dashboard.metrics.regenerateRate, 50);
    assert.equal(json.dashboard.metrics.exportRate, 40);
    assert.equal(json.dashboard.metrics.ttvMedianMs, null);
});

await test('GET /api/rooms/kpi/dashboard rejects invalid sinceDays', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const server = app.listen(0);
    t.after(() => server.close());
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    const res = await requestJson({
        port,
        path: '/api/rooms/kpi/dashboard?sinceDays=15',
        headers: { 'x-user-id': 'user_kpi_2' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.equal(json.code, 'BAD_REQUEST');
    assert.match(String(json.message || ''), /sinceDays/i);
});
