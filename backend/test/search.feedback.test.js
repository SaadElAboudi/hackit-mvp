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

async function postJson({ host = '127.0.0.1', port, path, body, timeoutMs = 8000 }) {
  const payload = JSON.stringify(body || {});
  return await new Promise((resolve, reject) => {
    const req = http.request(
      {
        host,
        port,
        path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (res) => {
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (c) => {
          data += c;
        });
        res.on('end', () => resolve({ status: res.statusCode, data }));
      }
    );
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
    req.write(payload);
    req.end();
  });
}

await test('POST /api/search/feedback accepts useful feedback payload', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await postJson({
    port,
    path: '/api/search/feedback',
    body: {
      requestId: 'room-msg-abc123',
      clicked: true,
      completed: true,
      rating: 5,
    },
  });

  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, true);
});

await test('POST /api/search/feedback rejects invalid rating', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await postJson({
    port,
    path: '/api/search/feedback',
    body: {
      requestId: 'room-msg-abc123',
      clicked: false,
      completed: false,
      rating: 7,
    },
  });

  assert.equal(res.status, 400);
  const json = JSON.parse(res.data);
  assert.match(String(json.error || ''), /rating/i);
});
