import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { EventEmitter } from 'node:events';

import mongoose from 'mongoose';

import { broadcastRoomDecisionCreated, handleRoomConnection } from '../src/services/roomWS.js';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const originalReadyStateDescriptor = Object.getOwnPropertyDescriptor(mongoose.connection, 'readyState');

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

async function requestJson({ host = '127.0.0.1', port, path, method = 'GET', body, headers = {}, timeoutMs = 8000 }) {
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

class FakeSocket extends EventEmitter {
    constructor() {
        super();
        this.readyState = 1;
        this.frames = [];
    }

    send(raw) {
        this.frames.push(JSON.parse(String(raw)));
    }

    close() {
        this.readyState = 3;
        this.emit('close');
    }
}

await test('requestId header is propagated to response header and error envelope', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const providedRequestId = 'req-client-abc123';
    const res = await requestJson({
        port,
        path: '/api/search',
        method: 'POST',
        body: { query: '' },
        headers: {
            'x-user-id': 'reqid_user_1',
            'x-request-id': providedRequestId,
        },
    });

    assert.equal(res.status, 400);
    assert.equal(res.headers['x-request-id'], providedRequestId);

    const json = JSON.parse(res.data);
    assert.equal(json.requestId, providedRequestId);
    assert.equal(json.error, json.message);
});

await test('WS decision_created event includes propagated requestId', async () => {
    const roomId = '507f191e810c19729de860ea';
    const ws = new FakeSocket();
    handleRoomConnection(ws, { url: `/ws/rooms/${roomId}` });

    ws.emit(
        'message',
        Buffer.from(
            JSON.stringify({
                type: 'join',
                roomId,
                userId: 'reqid-user-ws',
                displayName: 'ReqId User',
            })
        )
    );

    const requestId = 'req-ws-999';
    broadcastRoomDecisionCreated(
        roomId,
        {
            type: 'workspace_decision',
            data: { decisionId: 'd1', title: 'Decision title', sourceType: 'manual' },
        },
        requestId
    );

    const decisionFrame = ws.frames.find((f) => f.type === 'decision_created');
    assert.ok(decisionFrame, 'decision_created frame should be emitted');
    assert.equal(decisionFrame.requestId, requestId);

    ws.close();
});
