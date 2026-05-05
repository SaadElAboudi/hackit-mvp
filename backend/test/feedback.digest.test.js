import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const Room = (await import('../src/models/Room.js')).default;
const RoomFeedbackEvent = (await import('../src/models/RoomFeedbackEvent.js')).default;

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

await test('GET feedback-digest returns pertinence rates and patterns', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const fakeRoomId = '507f191e810c19729de86112';
    const fakeUserId = 'user_feedback_1';
    const now = new Date();

    const restoreFindRoom = withStub(Room, 'findById', async () => ({
        _id: fakeRoomId,
        name: 'Product',
        members: [{ userId: fakeUserId, role: 'owner' }],
    }));

    const restoreFindFeedback = withStub(RoomFeedbackEvent, 'find', () => ({
        sort() {
            return this;
        },
        limit() {
            return this;
        },
        lean: async () => [
            {
                _id: 'fe1',
                roomId: fakeRoomId,
                rating: 'pertinent',
                reason: 'Very clear breakdown',
                createdAt: new Date(now.getTime() - 2 * 24 * 60 * 60 * 1000),
            },
            {
                _id: 'fe2',
                roomId: fakeRoomId,
                rating: 'pertinent',
                reason: 'Great structure',
                createdAt: new Date(now.getTime() - 1 * 24 * 60 * 60 * 1000),
            },
            {
                _id: 'fe3',
                roomId: fakeRoomId,
                rating: 'moyen',
                reason: 'Missing details',
                createdAt: now,
            },
            {
                _id: 'fe4',
                roomId: fakeRoomId,
                rating: 'hors_sujet',
                reason: 'Missing details',
                createdAt: now,
            },
            {
                _id: 'fe5',
                roomId: fakeRoomId,
                rating: 'moyen',
                reason: 'Missing details',
                createdAt: now,
            },
        ],
    }));

    t.after(() => {
        restoreFindRoom();
        restoreFindFeedback();
    });

    const app = createApp();
    const server = app.listen(0);
    t.after(() => server.close());
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    const res = await requestJson({
        port,
        path: `/api/rooms/${fakeRoomId}/feedback-digest`,
        headers: { 'x-user-id': fakeUserId },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.ok(json.digest);
    assert.equal(json.digest.totalFeedback, 5);
    assert.equal(json.digest.totalPertinent, 2);
    assert.equal(json.digest.totalMoyen, 2);
    assert.equal(json.digest.totalHorsSujet, 1);
    assert.ok(json.digest.pertinentRate > 0);
    assert.ok(Array.isArray(json.digest.topFrictionPatterns));
    assert.ok(
        json.digest.topFrictionPatterns.includes('missing details'),
        'topFrictionPatterns should include "missing details" pattern'
    );
    assert.ok(
        json.digest.topWinPatterns.some(
            (p) => p.includes('clear') || p.includes('Great')
        ),
        'topWinPatterns should include win patterns'
    );
});
