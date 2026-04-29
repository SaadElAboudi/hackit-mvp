import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import mongoose from 'mongoose';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const Room = (await import('../src/models/Room.js')).default;
const WorkspaceDecision = (await import('../src/models/WorkspaceDecision.js')).default;
const WorkspaceTask = (await import('../src/models/WorkspaceTask.js')).default;

const originalReadyStateDescriptor = Object.getOwnPropertyDescriptor(mongoose.connection, 'readyState');

function forceMongoReady() {
  Object.defineProperty(mongoose.connection, 'readyState', { configurable: true, enumerable: true, get: () => 1 });
}

function restoreMongoReady() {
  if (originalReadyStateDescriptor) {
    Object.defineProperty(mongoose.connection, 'readyState', originalReadyStateDescriptor);
  }
}

function withStub(object, key, impl) {
  const previous = object[key];
  object[key] = impl;
  return () => {
    object[key] = previous;
  };
}

function buildChain(items) {
  return {
    sort() { return this; },
    limit() { return this; },
    lean: async () => items,
  };
}

async function requestJson({ port, path, method = 'GET', headers = {} }) {
  return await new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path, method, headers }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { data += c; });
      res.on('end', () => resolve({ status: res.statusCode, data }));
    });
    req.on('error', reject);
    req.end();
  });
}

await test('GET decision-pack returns markdown payload', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const fakeRoomId = '507f191e810c19729de860aa';
  const fakeUserId = 'user_pack_1';

  const restoreFindRoom = withStub(Room, 'findById', async () => ({
    _id: fakeRoomId,
    name: 'Growth Team',
    members: [{ userId: fakeUserId, role: 'owner' }],
  }));
  const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () => buildChain([
    { _id: 'd1', roomId: fakeRoomId, title: 'Launch pilot', summary: 'Start with 5 design partners.' },
  ]));
  const restoreFindTasks = withStub(WorkspaceTask, 'find', () => buildChain([
    { _id: 't1', roomId: fakeRoomId, decisionId: 'd1', title: 'Prepare outreach list', ownerName: 'Lina' },
  ]));

  t.after(() => {
    restoreFindRoom();
    restoreFindDecisions();
    restoreFindTasks();
  });

  const app = createApp();
  const server = app.listen(0);
  t.after(() => server.close());
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;

  const res = await requestJson({
    port,
    path: `/api/rooms/${fakeRoomId}/decision-pack`,
    headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Lina' },
  });

  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.pack.roomName, 'Growth Team');
  assert.match(json.pack.markdown, /Decision Pack/);
  assert.match(json.pack.markdown, /Launch pilot/);
});
