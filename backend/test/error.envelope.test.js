import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

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

function assertEnvelope(json) {
    assert.equal(json.ok, false);
    assert.ok(typeof json.code === 'string' && json.code.length > 0);
    assert.ok(typeof json.message === 'string' && json.message.length > 0);
    assert.ok(Object.prototype.hasOwnProperty.call(json, 'details'));
    assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
    assert.equal(json.error, json.message);
}

await test('error envelope is normalized for 400 validation errors', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/search',
        method: 'POST',
        body: { query: '' },
        headers: { 'x-user-id': 'env_400' },
    });

    assert.equal(res.status, 400);
    const json = JSON.parse(res.data);
    assertEnvelope(json);
    assert.equal(json.code, 'BAD_REQUEST');
});

await test('error envelope is normalized for 404 routes', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/route-that-does-not-exist',
        headers: { 'x-user-id': 'env_404' },
    });

    assert.equal(res.status, 404);
    const json = JSON.parse(res.data);
    assertEnvelope(json);
    assert.equal(json.code, 'BAD_REQUEST');
});

await test('error envelope is normalized for 5xx service errors', async (t) => {
    forceMongoReady();
    t.after(() => restoreMongoReady());

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await requestJson({
        port,
        path: '/api/ai/chat',
        method: 'POST',
        body: { message: 'hello' },
        headers: { 'x-user-id': 'env_500' },
    });

    assert.equal(res.status, 500);
    const json = JSON.parse(res.data);
    assertEnvelope(json);
    assert.equal(json.code, 'INTERNAL_ERROR');
});
