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

function request({ host = '127.0.0.1', port, path, method = 'GET' }) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host, port, path, method }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        resolve({ status: res.statusCode, data: data ? JSON.parse(data) : {} });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

await test('GET /auth/google/status returns OAuth config status', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await request({ port, path: '/auth/google/status' });
  assert.equal(res.status, 200);
  assert.equal(typeof res.data.enabled, 'boolean');
  assert.equal(typeof res.data.hasClientId, 'boolean');
  assert.equal(typeof res.data.hasCallbackUrl, 'boolean');
});

await test('GET /auth/google returns 503 when OAuth config is missing', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await request({ port, path: '/auth/google' });
  assert.equal(res.status, 503);
  assert.equal(res.data.error, 'Google OAuth is not configured');
});
