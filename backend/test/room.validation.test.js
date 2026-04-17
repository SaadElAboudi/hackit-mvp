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

async function requestJson({ host = '127.0.0.1', port, path, method = 'POST', body, headers = {}, timeoutMs = 8000 }) {
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

await test('POST /api/rooms returns structured validation envelope and requestId', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/rooms',
    body: { type: 'invalid-type' },
    headers: { 'x-user-id': 'user_test_1' },
  });

  assert.equal(res.status, 400);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, false);
  assert.equal(json.code, 'BAD_REQUEST');
  assert.match(String(json.message || ''), /type/i);
  assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
  assert.ok(typeof res.headers['x-request-id'] === 'string' && res.headers['x-request-id'].length > 0);
});

await test('POST /api/rooms/:id/messages enforces route rate limit envelope', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const app = createApp();
  app.locals.simpleRateLimit = async () => false;

  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/rooms/507f191e810c19729de860ea/messages',
    body: { content: 'Message to trigger limiter' },
    headers: { 'x-user-id': 'user_test_2' },
  });

  assert.equal(res.status, 429);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, false);
  assert.equal(json.code, 'RATE_LIMITED');
  assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
});

await test('POST /api/rooms/:id/messages invalid body returns BAD_REQUEST envelope', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/rooms/507f191e810c19729de860ea/messages',
    body: { content: '   ' },
    headers: { 'x-user-id': 'user_test_3' },
  });

  assert.equal(res.status, 400);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, false);
  assert.equal(json.code, 'BAD_REQUEST');
  assert.match(String(json.message || ''), /content/i);
  assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
});
