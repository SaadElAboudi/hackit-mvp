import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';
import Room from '../src/models/Room.js';

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

function mockRoomFindById(t, roomDoc) {
    const original = Room.findById;
    Room.findById = async () => roomDoc;
    t.after(() => {
        Room.findById = original;
    });
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
    const requestHeaders = { ...headers };
    if (payload) {
        requestHeaders['Content-Type'] = 'application/json';
        requestHeaders['Content-Length'] = Buffer.byteLength(payload);
    }
    return new Promise((resolve, reject) => {
        const req = http.request(
            { host, port, path, method, headers: requestHeaders },
            (res) => {
                let data = '';
                res.setEncoding('utf8');
                res.on('data', (c) => (data += c));
                res.on('end', () =>
                    resolve({ status: res.statusCode, data, headers: res.headers })
                );
            }
        );
        req.on('error', reject);
        req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
        if (payload) req.write(payload);
        req.end();
    });
}

// ─── PATCH /api/rooms/:id/artifacts/:artifactId/status ────────────────────────

await test('PATCH artifact status — invalid status returns BAD_REQUEST envelope', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/status`,
        method: 'PATCH',
        body: { status: 'published' },
        headers: { 'x-user-id': 'user_wf_1' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.equal(json.code, 'BAD_REQUEST');
    assert.match(String(json.message || ''), /status/i);
    assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
    assert.ok(
        typeof res.headers['x-request-id'] === 'string' &&
            res.headers['x-request-id'].length > 0
    );
});

await test('PATCH artifact status — missing status returns BAD_REQUEST envelope', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/status`,
        method: 'PATCH',
        body: {},
        headers: { 'x-user-id': 'user_wf_2' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.equal(json.code, 'BAD_REQUEST');
    assert.match(String(json.message || ''), /status/i);
});

// ─── POST /api/rooms/:id/artifacts/:artifactId/revise ─────────────────────────

await test('POST artifact revise — missing instructions returns BAD_REQUEST envelope', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/revise`,
        body: { changeSummary: 'added intro' },
        headers: { 'x-user-id': 'user_wf_3' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.equal(json.code, 'BAD_REQUEST');
    assert.match(String(json.message || ''), /instructions/i);
    assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
});

await test('POST artifact revise — oversized instructions returns BAD_REQUEST', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/revise`,
        body: { instructions: 'x'.repeat(2001) },
        headers: { 'x-user-id': 'user_wf_4' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.equal(json.code, 'BAD_REQUEST');
    assert.match(String(json.message || ''), /2000/i);
});

// ─── POST /api/rooms/:id/artifacts/:artifactId/versions/:versionId/comment ────

await test('POST version comment — empty content returns BAD_REQUEST envelope', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';
    const fakeVersionId = '507f191e810c19729de860ec';

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/versions/${fakeVersionId}/comment`,
        body: { content: '' },
        headers: { 'x-user-id': 'user_wf_5' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.equal(json.code, 'BAD_REQUEST');
    assert.match(String(json.message || ''), /content/i);
    assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
});

await test('POST version comment — guest role is forbidden', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';
    const fakeVersionId = '507f191e810c19729de860ec';
    const userId = 'user_wf_guest_comment';

    mockRoomFindById(t, {
        _id: fakeRoomId,
        members: [{ userId, role: 'guest' }],
    });

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/versions/${fakeVersionId}/comment`,
        body: { content: 'Please update this section' },
        headers: { 'x-user-id': userId },
    });

    assert.equal(res.status, 403);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.match(String(json.code || ''), /(FORBIDDEN|BAD_REQUEST)/i);
    assert.match(String(json.message || ''), /owner or member role required/i);
});

await test('PATCH comment resolve — guest role is forbidden', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeArtifactId = '507f191e810c19729de860eb';
    const fakeVersionId = '507f191e810c19729de860ec';
    const fakeCommentId = '507f191e810c19729de860ed';
    const userId = 'user_wf_guest_resolve';

    mockRoomFindById(t, {
        _id: fakeRoomId,
        members: [{ userId, role: 'guest' }],
    });

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/artifacts/${fakeArtifactId}/versions/${fakeVersionId}/comments/${fakeCommentId}/resolve`,
        method: 'PATCH',
        body: { resolved: true },
        headers: { 'x-user-id': userId },
    });

    assert.equal(res.status, 403);
    const json = JSON.parse(res.data);
    assert.equal(json.ok, false);
    assert.match(String(json.code || ''), /(FORBIDDEN|BAD_REQUEST)/i);
    assert.match(String(json.message || ''), /owner or member role required/i);
});
