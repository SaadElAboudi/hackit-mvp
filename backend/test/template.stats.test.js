import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

import Room from '../src/models/Room.js';
import RoomMessage from '../src/models/RoomMessage.js';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

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
        Object.defineProperty(mongoose.connection, 'readyState', originalReadyStateDescriptor);
    }
}

function startServer(app, port = 0) {
    return new Promise((resolve) => {
        const server = app.listen(port, () => {
            const address = server.address();
            resolve({ server, port: address.port });
        });
    });
}

async function requestJson({
    host = '127.0.0.1',
    port,
    path,
    method = 'GET',
    body,
    headers = {},
    timeoutMs = 8000,
}) {
    const payload = body === undefined ? '' : JSON.stringify(body);
    const requestHeaders = {
        ...headers,
    };
    if (payload) {
        requestHeaders['Content-Type'] = 'application/json';
        requestHeaders['Content-Length'] = Buffer.byteLength(payload);
    }

    return await new Promise((resolve, reject) => {
        const req = http.request(
            {
                host,
                port,
                path,
                method,
                headers: requestHeaders,
            },
            (res) => {
                let data = '';
                res.setEncoding('utf8');
                res.on('data', (c) => {
                    data += c;
                });
                res.on('end', () => {
                    resolve({ status: res.statusCode, data, headers: res.headers });
                });
            }
        );

        req.on('error', reject);
        req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
        if (payload) req.write(payload);
        req.end();
    });
}

await test('POST /api/rooms persists templateId and applies directives', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const originalCreate = Room.create;
    const captured = { payload: null };

    Room.create = async (payload) => {
        captured.payload = payload;
        return {
            ...payload,
            _id: '507f191e810c19729de860f1',
            updatedAt: new Date('2026-01-01T00:00:00.000Z'),
            lastActivityAt: new Date('2026-01-01T00:00:00.000Z'),
            toObject() {
                return this;
            },
        };
    };

    t.after(() => {
        Room.create = originalCreate;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/rooms',
        method: 'POST',
        headers: {
            'x-user-id': 'user_template_create',
            'x-display-name': 'Template Owner',
        },
        body: {
            name: 'Canal marketing',
            templateId: 'marketing',
        },
    });

    assert.equal(res.status, 201);
    assert.equal(captured.payload.templateId, 'marketing');
    assert.ok(String(captured.payload.aiDirectives || '').length > 0);
});

await test('GET /api/rooms/templates/stats aggregates usage and retention metrics', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const originalRoomFind = Room.find;
    const originalMessageFind = RoomMessage.find;

    Room.find = () => ({
        lean: async () => [
            {
                _id: '507f191e810c19729de860f1',
                templateId: 'marketing',
                createdAt: '2026-01-01T00:00:00.000Z',
            },
            {
                _id: '507f191e810c19729de860f2',
                templateId: 'marketing',
                createdAt: '2026-01-10T00:00:00.000Z',
            },
            {
                _id: '507f191e810c19729de860f3',
                templateId: 'product',
                createdAt: '2026-01-01T00:00:00.000Z',
            },
        ],
    });

    RoomMessage.find = () => ({
        lean: async () => [
            {
                roomId: '507f191e810c19729de860f1',
                createdAt: '2026-01-03T00:00:00.000Z',
                feedback: [{ rating: 1 }, { rating: -1 }, { rating: 1 }],
            },
            {
                roomId: '507f191e810c19729de860f1',
                createdAt: '2026-01-09T00:00:00.000Z',
                feedback: [],
            },
            {
                roomId: '507f191e810c19729de860f2',
                createdAt: '2026-01-10T12:00:00.000Z',
                feedback: [{ rating: -1 }],
            },
            {
                roomId: '507f191e810c19729de860f3',
                createdAt: '2026-01-10T00:00:00.000Z',
                feedback: [{ rating: 1 }],
            },
        ],
    });

    t.after(() => {
        Room.find = originalRoomFind;
        RoomMessage.find = originalMessageFind;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/rooms/templates/stats',
        method: 'GET',
        headers: {
            'x-user-id': 'user_template_stats',
            'x-display-name': 'Analyst',
        },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.ok(Array.isArray(json.stats));
    assert.ok(typeof json.generatedAt === 'string' && json.generatedAt.length > 0);
    assert.equal(json.sinceDays, null);

    const marketing = json.stats.find((s) => s.templateId === 'marketing');
    assert.ok(marketing);
    assert.equal(marketing.roomsCreated, 2);
    assert.equal(marketing.messagesSent, 3);
    assert.equal(marketing.feedbackUp, 2);
    assert.equal(marketing.feedbackDown, 2);
    assert.equal(marketing.feedbackAverage, 0);
    assert.equal(marketing.d1RetainedRooms, 1);
    assert.equal(marketing.d7RetainedRooms, 1);
    assert.equal(marketing.d1RetentionRate, 50);
    assert.equal(marketing.d7RetentionRate, 50);

    const product = json.stats.find((s) => s.templateId === 'product');
    assert.ok(product);
    assert.equal(product.roomsCreated, 1);
    assert.equal(product.messagesSent, 1);
    assert.equal(product.feedbackUp, 1);
    assert.equal(product.feedbackDown, 0);
    assert.equal(product.feedbackAverage, 1);
    assert.equal(product.d1RetentionRate, 100);
    assert.equal(product.d7RetentionRate, 100);

    assert.ok(json.insights);
    assert.equal(json.insights.topByFeedback?.templateId, 'product');
    assert.equal(json.insights.topByD7Retention?.templateId, 'product');
    assert.ok(Array.isArray(json.insights.underperformingTemplates));
});

await test('GET /api/rooms/templates/stats rejects invalid sinceDays', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/rooms/templates/stats?sinceDays=15',
        method: 'GET',
        headers: {
            'x-user-id': 'user_template_stats_invalid',
            'x-display-name': 'Analyst',
        },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.error, 'sinceDays must be one of 7, 30, 90');
});

await test('GET /api/rooms/templates/stats forwards sinceDays window to queries', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const originalRoomFind = Room.find;
    const originalMessageFind = RoomMessage.find;

    const captured = {
        roomQuery: null,
        messageQuery: null,
    };

    Room.find = (query) => {
        captured.roomQuery = query;
        return {
            lean: async () => [
                {
                    _id: '507f191e810c19729de860f9',
                    templateId: 'marketing',
                    createdAt: new Date(),
                },
            ],
        };
    };

    RoomMessage.find = (query) => {
        captured.messageQuery = query;
        return {
            lean: async () => [
                {
                    roomId: '507f191e810c19729de860f9',
                    createdAt: new Date(),
                    feedback: [{ rating: 1 }],
                },
            ],
        };
    };

    t.after(() => {
        Room.find = originalRoomFind;
        RoomMessage.find = originalMessageFind;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/rooms/templates/stats?sinceDays=7',
        method: 'GET',
        headers: {
            'x-user-id': 'user_template_stats_window',
            'x-display-name': 'Analyst',
        },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.sinceDays, 7);
    assert.ok(captured.roomQuery?.createdAt?.$gte instanceof Date);
    assert.ok(captured.messageQuery?.createdAt?.$gte instanceof Date);
});
