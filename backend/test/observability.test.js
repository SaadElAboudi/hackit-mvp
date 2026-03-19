import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

function startServer(app, port = 0) {
  return new Promise((resolve) => {
    const server = app.listen(port, () => {
      const address = server.address();
      resolve({ server, port: address.port });
    });
  });
}

function requestJson({ host = '127.0.0.1', port, path, method = 'GET', body }) {
  const payload = body ? JSON.stringify(body) : '';
  const headers = body
    ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(payload) }
    : {};

  return new Promise((resolve, reject) => {
    const req = http.request({ host, port, path, method, headers }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, data: data ? JSON.parse(data) : {} }));
    });
    req.on('error', reject);
    if (body) req.write(payload);
    req.end();
  });
}

await test('observability endpoints expose snapshot and accept quality/ttv events', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const feedbackRes = await requestJson({
    port,
    path: '/api/search/feedback',
    method: 'POST',
    body: { requestId: 'req1', clicked: true, completed: false, rating: 4 },
  });
  assert.equal(feedbackRes.status, 200);

  const ttvRes = await requestJson({
    port,
    path: '/api/analytics/ttv',
    method: 'POST',
    body: { requestId: 'req1', ttvMs: 1200 },
  });
  assert.equal(ttvRes.status, 200);

  const obsRes = await requestJson({ port, path: '/health/observability', method: 'GET' });
  assert.equal(obsRes.status, 200);
  assert.equal(obsRes.data.ok, true);
  assert.ok(obsRes.data.snapshot?.quality);
  assert.ok(obsRes.data.snapshot?.timeToValueMs);
  assert.ok(Array.isArray(obsRes.data.alerts));
});


await test('observability payload validation rejects invalid rating and ttv', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const badFeedback = await requestJson({
    port,
    path: '/api/search/feedback',
    method: 'POST',
    body: { requestId: 'req-invalid', rating: 9 },
  });
  assert.equal(badFeedback.status, 400);
  assert.equal(badFeedback.data.error, 'rating must be between 1 and 5');

  const badTtv = await requestJson({
    port,
    path: '/api/analytics/ttv',
    method: 'POST',
    body: { requestId: 'req-invalid', ttvMs: -1 },
  });
  assert.equal(badTtv.status, 400);
  assert.equal(badTtv.data.error, 'ttvMs is required and must be >= 0');
});


await test('GET /api/feature-flags exposes runtime flags', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({ port, path: '/api/feature-flags', method: 'GET' });
  assert.equal(res.status, 200);
  assert.equal(res.data.ok, true);
  assert.equal(typeof res.data.flags.multiLengthSummary, 'boolean');
});
