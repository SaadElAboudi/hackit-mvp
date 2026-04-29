import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');
const { SLO_LATENCY_P95_MS, SLO_ERROR_RATE, SLO_PROVIDER, evaluateAlerts, buildObservabilitySnapshot } = await import('../src/utils/observability.js');

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
  assert.ok(obsRes.data.snapshot?.wsFanout);
  assert.equal(typeof obsRes.data.snapshot.wsFanout.failureRate, 'number');
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

await test('GET /health/integrations exposes readiness payload', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({ port, path: '/health/integrations', method: 'GET' });
  assert.equal(res.status, 200);
  assert.equal(res.data.ok, true);
  assert.ok(res.data.providers?.slack);
  assert.ok(res.data.providers?.notion);
  assert.equal(typeof res.data.providers.slack.ready, 'boolean');
  assert.equal(typeof res.data.providers.notion.ready, 'boolean');
});

await test('SLO exports have correct shape', async () => {
  assert.ok(SLO_LATENCY_P95_MS['POST /api/rooms/:id/messages'] > 0, 'room messages p95 budget set');
  assert.ok(SLO_LATENCY_P95_MS['POST /api/search'] > 0, 'search p95 budget set');
  assert.ok(SLO_LATENCY_P95_MS.default > 0, 'default p95 budget set');
  assert.ok(SLO_ERROR_RATE['POST /api/search'] > 0, 'search error-rate SLO set');
  assert.ok(SLO_ERROR_RATE['POST /api/rooms/:id/messages'] > 0, 'room messages error-rate SLO set');
  assert.ok(SLO_PROVIDER.geminiTimeoutRate > 0, 'gemini timeout SLO set');
  assert.ok(SLO_PROVIDER.youtubeErrorRate > 0, 'youtube error SLO set');
  assert.ok(SLO_PROVIDER.wsFanoutFailureRate > 0, 'ws fanout SLO set');
});

await test('evaluateAlerts fires slo_latency_breach when p95 exceeds budget', async () => {
  const routeKey = 'POST /api/rooms/:id/messages';
  const budget = SLO_LATENCY_P95_MS[routeKey];
  const snapshot = buildObservabilitySnapshot();
  snapshot.endpoints[routeKey] = {
    requests: 15,
    errorRate5xx: 0,
    latencyMs: { p50: 1200, p95: budget + 500 },
  };
  const alerts = evaluateAlerts(snapshot);
  const breach = alerts.find((a) => a.code === 'slo_latency_breach');
  assert.ok(breach, 'expected slo_latency_breach alert');
  assert.equal(breach.severity, 'medium');
});

await test('evaluateAlerts does NOT fire slo_latency_breach with fewer than 10 requests', async () => {
  const routeKey = 'POST /api/rooms/:id/messages';
  const budget = SLO_LATENCY_P95_MS[routeKey];
  const snapshot = buildObservabilitySnapshot();
  snapshot.endpoints[routeKey] = {
    requests: 5,
    errorRate5xx: 0,
    latencyMs: { p50: 1000, p95: budget + 9999 },
  };
  const alerts = evaluateAlerts(snapshot);
  const breach = alerts.find((a) => a.code === 'slo_latency_breach');
  assert.equal(breach, undefined, 'should not alert with < 10 requests');
});

await test('evaluateAlerts fires room_message_5xx_spike when error rate exceeds SLO', async () => {
  const routeKey = 'POST /api/rooms/:id/messages';
  const budget = SLO_ERROR_RATE[routeKey];
  const snapshot = buildObservabilitySnapshot();
  snapshot.endpoints[routeKey] = {
    requests: 20,
    errorRate5xx: budget + 0.05,
    latencyMs: { p50: 100, p95: 200 },
  };
  const alerts = evaluateAlerts(snapshot);
  const spike = alerts.find((a) => a.code === 'room_message_5xx_spike');
  assert.ok(spike, 'expected room_message_5xx_spike alert');
  assert.equal(spike.severity, 'high');
});
