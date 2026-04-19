import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

import Room from '../src/models/Room.js';
import RoomShareHistory from '../src/models/RoomShareHistory.js';

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
    method = 'POST',
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

await test('POST /api/rooms/:id/share returns replayed response on idempotency hit', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const originalFindById = Room.findById;
    const originalFindOne = RoomShareHistory.findOne;

    Room.findById = async () => ({
        _id: '507f191e810c19729de860ea',
        name: 'Room Test',
        members: [{ userId: 'user_phase7_i1', role: 'owner' }],
        integrations: {
            slack: {
                enabled: true,
                botToken: 'xoxb-token',
                channelId: 'C123ABC99',
            },
        },
    });

    RoomShareHistory.findOne = () => ({
        lean: async () => ({
            _id: 'history123',
            status: 'success',
            target: 'slack',
            externalId: '1712000.1234',
            externalUrl: '',
        }),
    });

    t.after(() => {
        Room.findById = originalFindById;
        RoomShareHistory.findOne = originalFindOne;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/rooms/507f191e810c19729de860ea/share',
        method: 'POST',
        body: {
            target: 'slack',
            note: 'sync please',
            idempotencyKey: 'share-key-1',
        },
        headers: {
            'x-user-id': 'user_phase7_i1',
            'x-display-name': 'Owner',
        },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.replayed, true);
    assert.equal(json.target, 'slack');
    assert.equal(json.status, 'success');
    assert.equal(json.externalId, '1712000.1234');
    assert.equal(json.historyId, 'history123');
});

await test('GET /api/rooms/:id/share/history applies target/status/limit filters', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const originalFindById = Room.findById;
    const originalFind = RoomShareHistory.find;

    const captured = { query: null, limit: null, sort: null };

    Room.findById = async () => ({
        _id: '507f191e810c19729de860ea',
        name: 'Room Test',
        members: [{ userId: 'user_phase7_i2', role: 'member' }],
    });

    RoomShareHistory.find = (query) => {
        captured.query = query;
        return {
            sort(sortArg) {
                captured.sort = sortArg;
                return {
                    limit(limitArg) {
                        captured.limit = limitArg;
                        return {
                            lean: async () => [
                                {
                                    _id: 'h1',
                                    roomId: '507f191e810c19729de860ea',
                                    target: 'slack',
                                    status: 'success',
                                    summary: 'Shared summary',
                                },
                            ],
                        };
                    },
                };
            },
        };
    };

    t.after(() => {
        Room.findById = originalFindById;
        RoomShareHistory.find = originalFind;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/rooms/507f191e810c19729de860ea/share/history?target=slack&status=success&limit=1',
        method: 'GET',
        headers: {
            'x-user-id': 'user_phase7_i2',
            'x-display-name': 'Member',
        },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.ok(Array.isArray(json.history));
    assert.equal(json.history.length, 1);
    assert.equal(json.history[0].target, 'slack');
    assert.equal(json.history[0].status, 'success');
    assert.ok(typeof json.history[0].requestId === 'string' && json.history[0].requestId.length > 0);

    assert.deepEqual(captured.query, {
        roomId: '507f191e810c19729de860ea',
        target: 'slack',
        status: 'success',
    });
    assert.deepEqual(captured.sort, { createdAt: -1 });
    assert.equal(captured.limit, 1);
});
