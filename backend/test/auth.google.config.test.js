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
        let parsed = {};
        if (data) {
          try {
            parsed = JSON.parse(data);
          } catch (_) {
            parsed = {};
          }
        }
        resolve({ status: res.statusCode, data: parsed, headers: res.headers });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

await test('GET /auth/google/status exposes guest-only compatibility mode', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await request({ port, path: '/auth/google/status' });
  assert.equal(res.status, 200);
  assert.equal(res.data.enabled, false);
  assert.equal(res.data.mode, 'guest-only');
});

await test('GET /auth/google redirects to auth-success guest flow', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await request({ port, path: '/auth/google' });
  assert.equal(res.status, 302);
  assert.match(String(res.headers.location || ''), /\/auth-success\?userId=.+&mode=guest/);
});

await test('GET /api/me returns no-auth status', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await request({ port, path: '/api/me' });
  assert.equal(res.status, 200);
  assert.equal(res.data.ok, true);
  assert.equal(res.data.auth, 'disabled');
});
