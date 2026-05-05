import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const Room = (await import('../src/models/Room.js')).default;
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

async function requestJson({ port, path, headers = {} }) {
    return await new Promise((resolve, reject) => {
        const req = http.request(
            {
                host: '127.0.0.1',
                port,
                path,
                method: 'GET',
                headers,
            },
            (res) => {
                let data = '';
                res.setEncoding('utf8');
                res.on('data', (chunk) => {
                    data += chunk;
                });
                res.on('end', () => {
                    resolve({ status: res.statusCode, data });
                });
            }
        );
        req.on('error', reject);
        req.end();
    });
}

await test('GET execution-pulse returns critical execution signals', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const fakeRoomId = '507f191e810c19729de86111';
    const fakeUserId = 'user_exec_pulse_1';
    const now = new Date();
    const overdue = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const soon = new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000);
    const stale = new Date(now.getTime() - 5 * 24 * 60 * 60 * 1000);

    const restoreFindRoom = withStub(Room, 'findById', async () => ({
        _id: fakeRoomId,
        name: 'Ops',
        members: [{ userId: fakeUserId, role: 'owner' }],
    }));
    const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () =>
        buildChain([
            {
                _id: 'd1',
                roomId: fakeRoomId,
                title: 'Valider le runbook incident',
                status: 'review',
                ownerName: 'Alice',
                dueDate: overdue,
                updatedAt: stale,
            },
            {
                _id: 'd2',
                roomId: fakeRoomId,
                title: 'Arbitrer l astreinte',
                status: 'draft',
                ownerName: '',
                dueDate: soon,
                updatedAt: now,
            },
        ])
    );
    const restoreFindTasks = withStub(WorkspaceTask, 'find', () =>
        buildChain([
            {
                _id: 't1',
                roomId: fakeRoomId,
                title: 'Corriger le playbook',
                status: 'blocked',
                ownerName: 'Lina',
                dueDate: overdue,
            },
            {
                _id: 't2',
                roomId: fakeRoomId,
                title: 'Notifier le support',
                status: 'todo',
                ownerName: '',
                dueDate: soon,
            },
        ])
    );

    t.after(() => {
        restoreFindRoom();
        restoreFindDecisions();
        restoreFindTasks();
    });

    const app = createApp();
    const server = app.listen(0);
    t.after(() => server.close());
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/execution-pulse`,
        headers: { 'x-user-id': fakeUserId },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.pulse.status, 'critical');
    assert.equal(json.pulse.tasks.overdue, 1);
    assert.equal(json.pulse.tasks.blocked, 1);
    assert.equal(json.pulse.decisions.overdue, 1);
    assert.equal(json.pulse.decisions.withoutOwner, 1);
    assert.ok(json.pulse.score < 100);
    assert.ok(json.pulse.recommendations.some((item) => /bloquee/i.test(item)));
    assert.ok(
        json.pulse.focusItems.some(
            (item) => item.title === 'Valider le runbook incident'
        )
    );
});