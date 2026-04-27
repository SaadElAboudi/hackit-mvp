import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { WebSocket } from 'ws';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'true';

const { createApp } = await import('../src/index.js');
const { attachWebSocketServer } = await import('../src/services/threadRooms.js');
const {
    broadcastCommentCreated,
    broadcastCommentResolved,
    broadcastPageBlockUpdated,
} = await import('../src/services/roomWS.js');

const ROOM_ID = 'bbccddeeff00112233445566';

function startServer() {
    return new Promise((resolve) => {
        const app = createApp();
        const server = http.createServer(app);
        attachWebSocketServer(server);
        server.listen(0, '127.0.0.1', () => {
            const { port } = server.address();
            resolve({ server, port });
        });
    });
}

function connectClient(port, roomId) {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}/ws/rooms/${roomId}`);
        const pending = [];
        const seen = [];

        ws.on('message', (raw) => {
            let msg;
            try { msg = JSON.parse(raw.toString()); } catch { return; }
            seen.push(msg);
            for (let i = pending.length - 1; i >= 0; i--) {
                if (pending[i].predicate(msg)) {
                    clearTimeout(pending[i].timer);
                    pending.splice(i, 1)[0].resolve(msg);
                    break;
                }
            }
        });

        ws.on('error', reject);

        ws.on('open', () => {
            ws.send(JSON.stringify({ type: 'join', roomId, userId: 'ws-phase2-user' }));

            function waitForFrame(predicate, timeoutMs = 5000) {
                return new Promise((res, rej) => {
                    const existing = seen.find((msg) => predicate(msg));
                    if (existing) {
                        res(existing);
                        return;
                    }
                    const timer = setTimeout(() => rej(new Error(`waitForFrame timeout (${timeoutMs}ms)`)), timeoutMs);
                    pending.push({ predicate, resolve: res, reject: rej, timer });
                });
            }

            resolve({ ws, waitForFrame });
        });
    });
}

await test('presence.updated is emitted on room join', async (t) => {
    const { server, port } = await startServer();
    t.after(() => server.close());

    const client = await connectClient(port, ROOM_ID);
    t.after(() => { try { client.ws.close(); } catch { } });

    const joined = await client.waitForFrame((m) => m.type === 'joined');
    assert.equal(joined.roomId, ROOM_ID);

    const presence = await client.waitForFrame((m) => m.type === 'presence.updated');
    assert.equal(presence.roomId, ROOM_ID);
    assert.ok(Array.isArray(presence.userIds));
    assert.ok(presence.userIds.includes('ws-phase2-user'));
});

await test('page.block.updated and comment events are broadcast to room clients', async (t) => {
    const { server, port } = await startServer();
    t.after(() => server.close());

    const client = await connectClient(port, ROOM_ID);
    t.after(() => { try { client.ws.close(); } catch { } });
    await client.waitForFrame((m) => m.type === 'joined');

    const [blockFrame, createdFrame, resolvedFrame] = await Promise.all([
        client.waitForFrame((m) => m.type === 'page.block.updated'),
        client.waitForFrame((m) => m.type === 'comment.created'),
        client.waitForFrame((m) => m.type === 'comment.resolved'),
        Promise.resolve().then(() => {
            broadcastPageBlockUpdated(ROOM_ID, {
                action: 'updated',
                pageId: '507f191e810c19729de860eb',
                block: { _id: '507f191e810c19729de860ec', version: 2, text: 'Updated' },
                pageRevision: 3,
                lastVersion: 2,
            });
            broadcastCommentCreated(ROOM_ID, {
                pageId: '507f191e810c19729de860eb',
                blockId: '507f191e810c19729de860ec',
                comment: { _id: '507f191e810c19729de860ed', text: 'Please refine this point' },
            });
            broadcastCommentResolved(ROOM_ID, {
                pageId: '507f191e810c19729de860eb',
                blockId: '507f191e810c19729de860ec',
                comment: { _id: '507f191e810c19729de860ed', resolved: true },
            });
        }),
    ]);

    assert.equal(blockFrame.action, 'updated');
    assert.equal(blockFrame.pageId, '507f191e810c19729de860eb');
    assert.equal(blockFrame.block.version, 2);

    assert.equal(createdFrame.pageId, '507f191e810c19729de860eb');
    assert.equal(createdFrame.comment.text, 'Please refine this point');

    assert.equal(resolvedFrame.pageId, '507f191e810c19729de860eb');
    assert.equal(resolvedFrame.comment.resolved, true);
});
