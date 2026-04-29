import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import mongoose from 'mongoose';

import Room from '../src/models/Room.js';
import RoomMessage from '../src/models/RoomMessage.js';
import RoomFeedbackEvent from '../src/models/RoomFeedbackEvent.js';

process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

const originalReadyStateDescriptor = Object.getOwnPropertyDescriptor(
  mongoose.connection,
  'readyState'
);

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

async function requestJson({
  host = '127.0.0.1',
  port,
  path,
  method = 'POST',
  body,
  headers = {},
  timeoutMs = 8000,
}) {
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

await test('POST /api/rooms/:id/messages/:msgId/feedback accepts v1 payload with reason+metadata', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const originalRoomFindById = Room.findById;
  const originalMessageFindOne = RoomMessage.findOne;
  const originalEventUpsert = RoomFeedbackEvent.findOneAndUpdate;

  const roomId = '507f191e810c19729de860ea';
  const msgId = '507f191e810c19729de860eb';

  const message = {
    _id: msgId,
    roomId,
    isAI: true,
    feedback: [],
    async save() {
      return this;
    },
  };

  Room.findById = async () => ({
    _id: roomId,
    members: [{ userId: 'user_feedback_1', role: 'member' }],
  });
  RoomMessage.findOne = async () => message;

  let capturedEvent = null;
  RoomFeedbackEvent.findOneAndUpdate = async (filter, update) => {
    capturedEvent = { filter, update };
    return { ok: true };
  };

  t.after(() => {
    Room.findById = originalRoomFindById;
    RoomMessage.findOne = originalMessageFindOne;
    RoomFeedbackEvent.findOneAndUpdate = originalEventUpsert;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: `/api/rooms/${roomId}/messages/${msgId}/feedback`,
    method: 'POST',
    headers: {
      'x-user-id': 'user_feedback_1',
      'x-display-name': 'Reviewer',
    },
    body: {
      rating: 'moyen',
      reason: 'Manque des exemples concrets',
      metadata: {
        source: 'chat',
        surface: 'salon',
        locale: 'fr-FR',
      },
    },
  });

  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, true);
  assert.equal(json.userRating, 0);
  assert.equal(json.userRatingLabel, 'moyen');
  assert.equal(json.mixed, 1);
  assert.equal(json.thumbsUp, 0);
  assert.equal(json.thumbsDown, 0);

  assert.equal(capturedEvent.filter.userId, 'user_feedback_1');
  assert.equal(capturedEvent.update.$set.ratingLabel, 'moyen');
  assert.equal(capturedEvent.update.$set.reason, 'Manque des exemples concrets');
  assert.equal(capturedEvent.update.$set.metadata.source, 'chat');
});

await test('POST /api/rooms/:id/messages/:msgId/feedback rejects invalid v1 rating with BAD_REQUEST envelope', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const originalRoomFindById = Room.findById;
  const roomId = '507f191e810c19729de860ea';
  Room.findById = async () => ({
    _id: roomId,
    members: [{ userId: 'user_feedback_2', role: 'member' }],
  });

  t.after(() => {
    Room.findById = originalRoomFindById;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: `/api/rooms/${roomId}/messages/507f191e810c19729de860eb/feedback`,
    method: 'POST',
    headers: {
      'x-user-id': 'user_feedback_2',
    },
    body: {
      rating: 'invalid-rating',
    },
  });

  assert.equal(res.status, 400);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, false);
  assert.equal(json.code, 'BAD_REQUEST');
  assert.match(String(json.message || ''), /rating/i);
  assert.ok(typeof json.requestId === 'string' && json.requestId.length > 0);
});

await test('GET /api/rooms/:id/feedback/aggregate returns date and rating aggregates', async (t) => {
  forceMongoReady();
  t.after(() => restoreMongoReady());

  const originalRoomFindById = Room.findById;
  const originalEventFind = RoomFeedbackEvent.find;

  const roomId = '507f191e810c19729de860ea';
  Room.findById = async () => ({
    _id: roomId,
    members: [{ userId: 'user_feedback_3', role: 'member' }],
  });

  RoomFeedbackEvent.find = () => ({
    sort: () => ({
      lean: async () => [
        {
          ratingLabel: 'pertinent',
          createdAt: '2026-04-28T12:00:00.000Z',
        },
        {
          ratingLabel: 'hors_sujet',
          createdAt: '2026-04-28T13:00:00.000Z',
        },
        {
          ratingLabel: 'moyen',
          createdAt: '2026-04-29T09:00:00.000Z',
        },
      ],
    }),
  });

  t.after(() => {
    Room.findById = originalRoomFindById;
    RoomFeedbackEvent.find = originalEventFind;
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const res = await requestJson({
    port,
    path: `/api/rooms/${roomId}/feedback/aggregate?from=2026-04-28T00:00:00.000Z&to=2026-04-29T23:59:59.000Z`,
    method: 'GET',
    headers: {
      'x-user-id': 'user_feedback_3',
    },
  });

  assert.equal(res.status, 200);
  const json = JSON.parse(res.data);
  assert.equal(json.ok, true);
  assert.equal(json.total, 3);
  assert.equal(json.byRating.pertinent, 1);
  assert.equal(json.byRating.moyen, 1);
  assert.equal(json.byRating.hors_sujet, 1);
  assert.equal(json.byDay.length, 2);
});
