import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import jwt from 'jsonwebtoken';

process.env.NODE_ENV = 'test';

const { createApp } = await import('../src/index.js');
const Lesson = (await import('../src/models/lesson.js')).default;

function startServer(app, port = 0) {
  return new Promise((resolve) => {
    const server = app.listen(port, () => {
      const address = server.address();
      resolve({ server, port: address.port });
    });
  });
}

function authHeaders(userId = '123456') {
  const token = jwt.sign({ userId, email: 'test@example.com' }, process.env.JWT_SECRET || 'dev_jwt_secret', { expiresIn: '1h' });
  return {
    authorization: `Bearer ${token}`,
    'x-user-id': userId,
  };
}

function requestJson({ host = '127.0.0.1', port, path, method = 'GET', body, headers = {}, timeoutMs = 8000 }) {
  const payload = body ? JSON.stringify(body) : '';
  const requestHeaders = {
    ...headers,
  };

  if (body) {
    requestHeaders['content-type'] = 'application/json';
    requestHeaders['content-length'] = Buffer.byteLength(payload);
  }

  return new Promise((resolve, reject) => {
    const req = http.request({ host, port, path, method, headers: requestHeaders }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        const parsed = data ? JSON.parse(data) : {};
        resolve({ status: res.statusCode, data: parsed });
      });
    });

    req.on('error', reject);
    req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
    if (body) req.write(payload);
    req.end();
  });
}

await test('DELETE /api/lessons/:id returns 400 for invalid id', async (t) => {
  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/lessons/not-an-objectid',
    method: 'DELETE',
    headers: authHeaders(),
  });

  assert.equal(res.status, 400);
  assert.equal(res.data.error, 'Invalid lesson id');
});

await test('DELETE /api/lessons/:id returns 404 when lesson is not found', async (t) => {
  const originalDeleteOne = Lesson.deleteOne;
  Lesson.deleteOne = async () => ({ deletedCount: 0 });
  t.after(() => {
    Lesson.deleteOne = originalDeleteOne;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/lessons/507f1f77bcf86cd799439011',
    method: 'DELETE',
    headers: authHeaders(),
  });

  assert.equal(res.status, 404);
  assert.equal(res.data.error, 'Lesson not found');
});

await test('PATCH /api/lessons/:id/favorite updates lesson favorite', async (t) => {
  const originalFindOneAndUpdate = Lesson.findOneAndUpdate;
  Lesson.findOneAndUpdate = async () => ({
    _id: '507f1f77bcf86cd799439011',
    userId: '123456',
    title: 'Demo',
    summary: '',
    steps: ['Step 1'],
    videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    favorite: true,
    views: 0,
    createdAt: new Date('2024-01-01T00:00:00.000Z'),
    updatedAt: new Date('2024-01-02T00:00:00.000Z'),
  });
  t.after(() => {
    Lesson.findOneAndUpdate = originalFindOneAndUpdate;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/lessons/507f1f77bcf86cd799439011/favorite',
    method: 'PATCH',
    headers: authHeaders(),
    body: { favorite: true },
  });

  assert.equal(res.status, 200);
  assert.equal(res.data.ok, true);
  assert.equal(res.data.lesson.favorite, true);
});

await test('POST /api/lessons/:id/view increments view and returns lesson', async (t) => {
  const originalFindOneAndUpdate = Lesson.findOneAndUpdate;
  Lesson.findOneAndUpdate = async () => ({
    _id: '507f1f77bcf86cd799439011',
    userId: '123456',
    title: 'Demo',
    summary: '',
    steps: ['Step 1'],
    videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    favorite: false,
    views: 3,
    createdAt: new Date('2024-01-01T00:00:00.000Z'),
    updatedAt: new Date('2024-01-02T00:00:00.000Z'),
  });
  t.after(() => {
    Lesson.findOneAndUpdate = originalFindOneAndUpdate;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/lessons/507f1f77bcf86cd799439011/view',
    method: 'POST',
    headers: authHeaders(),
  });

  assert.equal(res.status, 200);
  assert.equal(res.data.views, 3);
});

await test('GET /api/lessons supports pagination and sorting', async (t) => {
  const originalFind = Lesson.find;
  Lesson.find = () => ({
    sort: () => ({
      skip: () => ({
        limit: () => ({
          lean: async () => ([
            {
              _id: '507f1f77bcf86cd799439011',
              userId: '123456',
              title: 'Newest',
              summary: 'S',
              steps: ['A'],
              videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              favorite: true,
              views: 10,
              createdAt: new Date('2024-01-03T00:00:00.000Z'),
              updatedAt: new Date('2024-01-03T00:00:00.000Z'),
            },
          ]),
        }),
      }),
    }),
  });
  t.after(() => {
    Lesson.find = originalFind;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: '/api/lessons?favorite=true&sort=views&order=desc&limit=1&offset=0',
    method: 'GET',
    headers: authHeaders(),
  });

  assert.equal(res.status, 200);
  assert.equal(res.data.total, 1);
  assert.equal(res.data.items[0].title, 'Newest');
  assert.equal(res.data.items[0].favorite, true);
});
