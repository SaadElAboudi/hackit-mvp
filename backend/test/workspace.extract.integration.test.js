import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const Room = (await import('../src/models/Room.js')).default;
const RoomMessage = (await import('../src/models/RoomMessage.js')).default;
const RoomMission = (await import('../src/models/RoomMission.js')).default;
const WorkspaceDecision = (await import('../src/models/WorkspaceDecision.js')).default;
const WorkspaceTask = (await import('../src/models/WorkspaceTask.js')).default;

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

async function requestJson({ host = '127.0.0.1', port, path, method = 'POST', body, headers = {}, timeoutMs = 8000 }) {
    const payload = body === undefined ? '' : JSON.stringify(body);
    const requestHeaders = { ...headers };
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

function withStub(object, key, impl) {
    const previous = object[key];
    object[key] = impl;
    return () => {
        object[key] = previous;
    };
}

function buildChain(items) {
    return {
        sort() {
            return this;
        },
        limit() {
            return this;
        },
        lean: async () => items,
    };
}

await test('POST decisions extract returns fallback suggestions without persistence', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeUserId = 'user_extract_1';

    const restoreFindRoom = withStub(Room, 'findById', async () => ({
        _id: fakeRoomId,
        members: [{ userId: fakeUserId, role: 'owner' }],
        save: async () => { },
    }));
    const restoreFindMessages = withStub(RoomMessage, 'find', () => buildChain([
        {
            _id: '507f191e810c19729de860f1',
            senderName: 'Sophie',
            isAI: false,
            content: 'On valide le lancement pilote mardi et Karim prend le suivi KPI.',
        },
    ]));

    t.after(() => {
        restoreFindRoom();
        restoreFindMessages();
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/decisions/extract`,
        method: 'POST',
        body: { persist: false, recentLimit: 20 },
        headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Sophie' },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.persisted, false);
    assert.ok(Array.isArray(json.extracted));
    assert.ok(json.extracted.length >= 1);
    assert.ok(String(json.extracted[0]?.title || '').length > 0);
});

await test('POST decisions extract persists mission-linked decisions and tasks', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeUserId = 'user_extract_2';
    const fakeMissionId = '507f191e810c19729de860f2';

    const restoreFindRoom = withStub(Room, 'findById', async () => ({
        _id: fakeRoomId,
        members: [{ userId: fakeUserId, role: 'owner' }],
        save: async () => { },
    }));
    const restoreFindMission = withStub(RoomMission, 'findOne', () => ({
        lean: async () => ({
            _id: fakeMissionId,
            roomId: fakeRoomId,
            prompt: 'Definir un plan GTM B2B pour le prochain trimestre.',
            resultMessageId: null,
        }),
    }));
    const restoreFindMessages = withStub(RoomMessage, 'find', () => buildChain([
        {
            _id: '507f191e810c19729de860f3',
            senderName: 'Lead',
            isAI: false,
            content: 'On doit prioriser le segment agences et lancer 2 experiments paid.',
        },
    ]));

    let createdDecisionPayloads = [];
    const restoreCreateDecision = withStub(WorkspaceDecision, 'create', async (payload) => {
        createdDecisionPayloads.push(payload);
        return {
            _id: `decision_${createdDecisionPayloads.length}`,
            createdAt: new Date(),
            ...payload,
            async save() {
                return this;
            },
            toObject() {
                return { _id: this._id, ...payload };
            },
        };
    });

    const restoreInsertTasks = withStub(WorkspaceTask, 'insertMany', async (items) => {
        return items.map((item, idx) => ({ _id: `task_${idx + 1}`, ...item }));
    });

    t.after(() => {
        restoreFindRoom();
        restoreFindMission();
        restoreFindMessages();
        restoreCreateDecision();
        restoreInsertTasks();
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/decisions/extract`,
        method: 'POST',
        body: { persist: true, missionId: fakeMissionId, recentLimit: 20 },
        headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Lead' },
    });

    assert.equal(res.status, 201);
    const json = JSON.parse(res.data);
    assert.equal(json.persisted, true);
    assert.ok(Array.isArray(json.decisions));
    assert.ok(Array.isArray(json.tasks));
    assert.ok(json.decisions.length >= 1);
    assert.equal(json.missionContext?.missionId, fakeMissionId);

    assert.ok(createdDecisionPayloads.length >= 1);
    assert.equal(createdDecisionPayloads[0].sourceType, 'mission');
    assert.equal(createdDecisionPayloads[0].sourceId, fakeMissionId);
});

await test('POST mission extract endpoint persists decisions without missionId in body', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeUserId = 'user_extract_3';
    const fakeMissionId = '507f191e810c19729de860f4';

    const restoreFindRoom = withStub(Room, 'findById', async () => ({
        _id: fakeRoomId,
        members: [{ userId: fakeUserId, role: 'owner' }],
        save: async () => { },
    }));
    const restoreFindMission = withStub(RoomMission, 'findOne', () => ({
        lean: async () => ({
            _id: fakeMissionId,
            roomId: fakeRoomId,
            prompt: 'Generer un plan d\'execution commercial Q3.',
            resultMessageId: null,
        }),
    }));
    const restoreFindMessages = withStub(RoomMessage, 'find', () => buildChain([
        {
            _id: '507f191e810c19729de860f5',
            senderName: 'Ops',
            isAI: false,
            content: 'On formalise le plan GTM et les owners par segment.',
        },
    ]));

    let createdDecisionPayloads = [];
    const restoreCreateDecision = withStub(WorkspaceDecision, 'create', async (payload) => {
        createdDecisionPayloads.push(payload);
        return {
            _id: `decision_endpoint_${createdDecisionPayloads.length}`,
            createdAt: new Date(),
            ...payload,
            async save() {
                return this;
            },
            toObject() {
                return { _id: this._id, ...payload };
            },
        };
    });
    const restoreInsertTasks = withStub(WorkspaceTask, 'insertMany', async (items) => {
        return items.map((item, idx) => ({ _id: `task_endpoint_${idx + 1}`, ...item }));
    });

    t.after(() => {
        restoreFindRoom();
        restoreFindMission();
        restoreFindMessages();
        restoreCreateDecision();
        restoreInsertTasks();
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/missions/${fakeMissionId}/extract`,
        method: 'POST',
        body: { persist: true, recentLimit: 20 },
        headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Ops' },
    });

    assert.equal(res.status, 201);
    const json = JSON.parse(res.data);
    assert.equal(json.persisted, true);
    assert.equal(json.missionContext?.missionId, fakeMissionId);
    assert.ok(createdDecisionPayloads.length >= 1);
    assert.equal(createdDecisionPayloads[0].sourceType, 'mission');
    assert.equal(createdDecisionPayloads[0].sourceId, fakeMissionId);
});

await test('POST mission extract endpoint returns 404 when mission does not exist', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const fakeRoomId = '507f191e810c19729de860ea';
    const fakeUserId = 'user_extract_4';
    const fakeMissionId = '507f191e810c19729de860f6';

    const restoreFindRoom = withStub(Room, 'findById', async () => ({
        _id: fakeRoomId,
        members: [{ userId: fakeUserId, role: 'owner' }],
        save: async () => { },
    }));
    const restoreFindMission = withStub(RoomMission, 'findOne', () => ({
        lean: async () => null,
    }));
    const restoreFindMessages = withStub(RoomMessage, 'find', () => buildChain([]));

    t.after(() => {
        restoreFindRoom();
        restoreFindMission();
        restoreFindMessages();
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/missions/${fakeMissionId}/extract`,
        method: 'POST',
        body: { persist: true },
        headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Ops' },
    });

    assert.equal(res.status, 404);
    const json = JSON.parse(res.data);
    assert.equal(json.error, 'Mission not found');
});
