import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const Room = (await import('../src/models/Room.js')).default;
const RoomShareHistory = (await import('../src/models/RoomShareHistory.js')).default;
const WorkspaceDecision = (await import('../src/models/WorkspaceDecision.js')).default;
const WorkspaceTask = (await import('../src/models/WorkspaceTask.js')).default;
const RoomDecisionPackEvent = (await import('../src/models/RoomDecisionPackEvent.js')).default;

const originalReadyStateDescriptor = Object.getOwnPropertyDescriptor(mongoose.connection, 'readyState');

function forceMongoReady() { Object.defineProperty(mongoose.connection, 'readyState', { configurable: true, enumerable: true, get: () => 1 }); }
function restoreMongoReady() { if (originalReadyStateDescriptor) Object.defineProperty(mongoose.connection, 'readyState', originalReadyStateDescriptor); }
function withStub(object, key, impl) { const previous = object[key]; object[key] = impl; return () => { object[key] = previous; }; }
function buildChain(items) { return { sort() { return this; }, limit() { return this; }, lean: async () => items }; }
async function requestJson({ port, path, method = 'GET', headers = {}, body }) {
  const payload = body ? JSON.stringify(body) : '';
  return await new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path, method, headers: { ...headers, ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {}) } }, (res) => {
      let data = ''; res.setEncoding('utf8'); res.on('data', (c) => { data += c; }); res.on('end', () => resolve({ status: res.statusCode, data }));
    });
    req.on('error', reject); if (payload) req.write(payload); req.end();
  });
}

await test('GET decision-pack supports executive mode', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860aa'; const fakeUserId = 'user_pack_1';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Growth Team', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () => buildChain([{ _id: 'd1', roomId: fakeRoomId, title: 'Launch pilot', summary: 'Start with 5 design partners.' }]));
  const restoreFindTasks = withStub(WorkspaceTask, 'find', () => buildChain([{ _id: 't1', roomId: fakeRoomId, decisionId: 'd1', title: 'Prepare outreach list', ownerName: 'Lina' }]));
  t.after(() => { restoreFindRoom(); restoreFindDecisions(); restoreFindTasks(); });

  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, path: `/api/rooms/${fakeRoomId}/decision-pack?mode=executive`, headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Lina' } });
  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.pack.mode, 'executive');
  assert.match(json.pack.markdown, /Executive Decisions/);
});

await test('GET decision-pack rejects invalid mode', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860ab'; const fakeUserId = 'user_pack_2';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  t.after(() => restoreFindRoom());
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, path: `/api/rooms/${fakeRoomId}/decision-pack?mode=foo`, headers: { 'x-user-id': fakeUserId } });
  assert.equal(res.status, 400);
});

await test('POST decision-pack/share rejects unsupported target', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860ac'; const fakeUserId = 'user_pack_3';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  t.after(() => restoreFindRoom());
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, method: 'POST', path: `/api/rooms/${fakeRoomId}/decision-pack/share`, headers: { 'x-user-id': fakeUserId }, body: { target: 'email', note: 'x' } });
  assert.equal(res.status, 400);
});

await test('POST decision-pack/share supports csv target and returns csv payload', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860c1'; const fakeUserId = 'user_pack_csv_1';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () => buildChain([{ _id: 'd1', roomId: fakeRoomId, title: 'Launch pilot', summary: 'Summary' }]));
  const restoreFindTasks = withStub(WorkspaceTask, 'find', () => buildChain([{ _id: 't1', roomId: fakeRoomId, decisionId: 'd1', title: 'Prepare rollout', status: 'todo', ownerName: 'Lina' }]));
  const restoreCreateHistory = withStub(RoomShareHistory, 'create', async (payload) => ({
    _id: 'hcsv1',
    ...payload,
    externalUrl: '',
    metadata: null,
    async save() { return this; },
  }));
  t.after(() => { restoreFindRoom(); restoreFindDecisions(); restoreFindTasks(); restoreCreateHistory(); });

  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, method: 'POST', path: `/api/rooms/${fakeRoomId}/decision-pack/share?mode=executive`, headers: { 'x-user-id': fakeUserId }, body: { target: 'csv', note: 'export csv' } });
  assert.equal(res.status, 201);
  const json = JSON.parse(res.data);
  assert.equal(json.share.target, 'csv');
  assert.equal(typeof json.csv?.fileName, 'string');
  assert.match(String(json.csv?.fileName || ''), /\.csv$/i);
  assert.match(String(json.csv?.content || ''), /generated_at,|"generated_at"/i);
  assert.match(String(json.csv?.content || ''), /Launch pilot/);
});

await test('GET decision-pack can disable open tasks', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860ad'; const fakeUserId = 'user_pack_4';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () => buildChain([{ _id: 'd1', roomId: fakeRoomId, title: 'Rollout', summary: '' }]));
  const restoreFindTasks = withStub(WorkspaceTask, 'find', () => buildChain([{ _id: 't1', roomId: fakeRoomId, decisionId: 'd1', title: 'Task linked' }]));
  t.after(() => { restoreFindRoom(); restoreFindDecisions(); restoreFindTasks(); });
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, path: `/api/rooms/${fakeRoomId}/decision-pack?includeOpenTasks=false`, headers: { 'x-user-id': fakeUserId } });
  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.pack.includeOpenTasks, false);
});

await test('GET decision-pack/readiness returns score and recommendations', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860b1'; const fakeUserId = 'user_pack_8';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () => buildChain([{ _id: 'd1', roomId: fakeRoomId, title: 'Rollout', summary: '' }]));
  const restoreFindTasks = withStub(WorkspaceTask, 'find', () => buildChain([
    { _id: 't1', roomId: fakeRoomId, decisionId: 'd1', title: 'Task linked', ownerName: 'Lina', dueDate: new Date() },
    { _id: 't2', roomId: fakeRoomId, decisionId: null, title: 'Task open' },
  ]));
  t.after(() => { restoreFindRoom(); restoreFindDecisions(); restoreFindTasks(); });
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, path: `/api/rooms/${fakeRoomId}/decision-pack/readiness`, headers: { 'x-user-id': fakeUserId } });
  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.readiness.totalTasks, 2);
  assert.equal(json.readiness.tasksWithOwners, 1);
  assert.ok(json.readiness.score > 0);
  assert.ok(json.readiness.recommendations.some((item) => /owners/i.test(item)));
});

await test('POST decision-pack/share returns 412 when target integration is missing', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860ae'; const fakeUserId = 'user_pack_5';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }], integrations: { notion: { enabled: false } } }));
  t.after(() => restoreFindRoom());
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, method: 'POST', path: `/api/rooms/${fakeRoomId}/decision-pack/share?mode=checklist`, headers: { 'x-user-id': fakeUserId }, body: { target: 'notion', note: 'x' } });
  assert.equal(res.status, 412);
});

await test('POST decision-pack/events stores event', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860af'; const fakeUserId = 'user_pack_6';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreCreateEvent = withStub(RoomDecisionPackEvent, 'create', async (payload) => ({ _id: 'ev1', createdAt: new Date(), ...payload }));
  t.after(() => { restoreFindRoom(); restoreCreateEvent(); });
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, method: 'POST', path: `/api/rooms/${fakeRoomId}/decision-pack/events`, headers: { 'x-user-id': fakeUserId }, body: { eventType: 'viewed', mode: 'executive' } });
  assert.equal(res.status, 201);
});

await test('GET decision-pack aggregate returns counters', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860b0'; const fakeUserId = 'user_pack_7';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreAggregate = withStub(RoomDecisionPackEvent, 'aggregate', async () => ([{ _id: 'viewed', count: 3 }, { _id: 'shared', count: 1 }]));
  t.after(() => { restoreFindRoom(); restoreAggregate(); });
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, path: `/api/rooms/${fakeRoomId}/decision-pack/aggregate?sinceDays=14`, headers: { 'x-user-id': fakeUserId } });
  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.aggregate.events.viewed, 3);
  assert.equal(json.aggregate.events.shared, 1);
});

await test('GET decision-pack checklist mode renders task list', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860b2'; const fakeUserId = 'user_pack_9';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Growth Team', members: [{ userId: fakeUserId, role: 'owner' }] }));
  const restoreFindDecisions = withStub(WorkspaceDecision, 'find', () => buildChain([{ _id: 'd1', roomId: fakeRoomId, title: 'Launch pilot', summary: 'Start small.' }]));
  const restoreFindTasks = withStub(WorkspaceTask, 'find', () => buildChain([{ _id: 't1', roomId: fakeRoomId, decisionId: 'd1', title: 'Prepare outreach list', ownerName: 'Lina' }]));
  t.after(() => { restoreFindRoom(); restoreFindDecisions(); restoreFindTasks(); });
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const res = await requestJson({ port, path: `/api/rooms/${fakeRoomId}/decision-pack?mode=checklist`, headers: { 'x-user-id': fakeUserId, 'x-display-name': 'Lina' } });
  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.pack.mode, 'checklist');
  assert.match(json.pack.markdown, /## Decisions\n/);
  assert.match(json.pack.markdown, /Prepare outreach list/);
  assert.doesNotMatch(json.pack.markdown, /Executive Decisions/);
});

await test('POST decision-pack/share accepts mode in body and rejects invalid mode', async (t) => {
  forceMongoReady(); t.after(() => restoreMongoReady());
  const fakeRoomId = '507f191e810c19729de860b3'; const fakeUserId = 'user_pack_10';
  const restoreFindRoom = withStub(Room, 'findById', async () => ({ _id: fakeRoomId, name: 'Ops', members: [{ userId: fakeUserId, role: 'owner' }] }));
  t.after(() => restoreFindRoom());
  const app = createApp(); const server = app.listen(0); t.after(() => server.close()); await new Promise((r) => server.once('listening', r)); const port = server.address().port;
  const invalidRes = await requestJson({ port, method: 'POST', path: `/api/rooms/${fakeRoomId}/decision-pack/share`, headers: { 'x-user-id': fakeUserId }, body: { target: 'csv', mode: 'invalid' } });
  assert.equal(invalidRes.status, 400);
  const invalidJson = JSON.parse(invalidRes.data);
  assert.match(invalidJson.error, /mode/i);
});
