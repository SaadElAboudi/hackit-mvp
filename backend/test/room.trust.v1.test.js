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
        Object.defineProperty(
            mongoose.connection,
            'readyState',
            originalReadyStateDescriptor
        );
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
    headers = {},
    timeoutMs = 8000,
}) {
    return await new Promise((resolve, reject) => {
        const req = http.request(
            {
                host,
                port,
                path,
                method,
                headers,
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
        req.end();
    });
}

await test('GET /api/rooms/:id/messages returns AI messages with trust explainability payload', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const originalRoomFindById = Room.findById;
    const originalMessageFind = RoomMessage.find;

    const roomId = '507f191e810c19729de860ea';

    Room.findById = async () => ({
        _id: roomId,
        members: [{ userId: 'user_trust_1', role: 'member' }],
        toObject() {
            return {
                _id: roomId,
                name: 'Trust Room',
                members: [{ userId: 'user_trust_1', role: 'member' }],
            };
        },
    });

    RoomMessage.find = () => ({
        sort: () => ({
            limit: () => ({
                lean: async () => [
                    {
                        _id: '507f191e810c19729de860eb',
                        roomId,
                        senderId: 'ai',
                        senderName: 'IA',
                        isAI: true,
                        type: 'ai',
                        content: 'Proposition de plan.',
                        data: {
                            trust: {
                                confidence: 'moyen',
                                whyThisPlan: 'Ce plan maximise impact x rapidite pour le sprint.',
                                assumptions: [
                                    'Le scope reste stable.',
                                    'Les dependances critiques sont disponibles.',
                                ],
                                limits: ['Validation metier finale necessaire.'],
                            },
                        },
                        createdAt: '2026-04-29T12:00:00.000Z',
                    },
                ],
            }),
        }),
    });

    t.after(() => {
        Room.findById = originalRoomFindById;
        RoomMessage.find = originalMessageFind;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: `/api/rooms/${roomId}/messages`,
        method: 'GET',
        headers: {
            'x-user-id': 'user_trust_1',
        },
    });

    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.ok(Array.isArray(json.messages));
    assert.equal(json.messages.length, 1);

    const trust = json.messages[0]?.data?.trust;
    assert.equal(typeof trust?.whyThisPlan, 'string');
    assert.equal(Array.isArray(trust?.assumptions), true);
    assert.equal(Array.isArray(trust?.limits), true);
    assert.match(String(trust?.confidence || ''), /faible|moyen|eleve/i);
});
