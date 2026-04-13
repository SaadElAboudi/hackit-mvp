import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { WebSocket } from 'ws';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'true';

const { createApp } = await import('../src/index.js');
const { attachWebSocketServer } = await import('../src/services/threadRooms.js');
const { broadcastRoomSynthesisSuggested } = await import('../src/services/roomWS.js');

const ROOM_ID = 'aabbccddeeff001122334456';

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

        ws.on('message', (raw) => {
            let msg;
            try { msg = JSON.parse(raw.toString()); } catch { return; }
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
            ws.send(JSON.stringify({ type: 'join', roomId, userId: `u-${Math.random().toString(36).slice(2)}` }));
            function waitForFrame(predicate, timeoutMs = 5000) {
                return new Promise((res, rej) => {
                    const timer = setTimeout(() => rej(new Error('wait timeout')), timeoutMs);
                    pending.push({ predicate, resolve: res, reject: rej, timer });
                });
            }
            resolve({ ws, waitForFrame });
        });
    });
}

await test('synthesis_suggested is broadcast to all live clients in room', async (t) => {
    const { server, port } = await startServer();
    t.after(() => server.close());

    const [a, b] = await Promise.all([connectClient(port, ROOM_ID), connectClient(port, ROOM_ID)]);
    t.after(() => { try { a.ws.close(); } catch {} });
    t.after(() => { try { b.ws.close(); } catch {} });

    await Promise.all([
        a.waitForFrame((m) => m.type === 'joined'),
        b.waitForFrame((m) => m.type === 'joined'),
    ]);

    const mockMessage = {
        _id: '507f1f77bcf86cd799439019',
        roomId: ROOM_ID,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        type: 'system',
        content: '# Suggestion de synthese\\n- Point 1\\n- Point 2',
        data: {
            kind: 'synthesis_suggestion',
            basedOnMessages: 9,
            suggestedCommands: ['/decide', '/doc'],
        },
    };

    const [evtA, evtB] = await Promise.all([
        a.waitForFrame((m) => m.type === 'synthesis_suggested'),
        b.waitForFrame((m) => m.type === 'synthesis_suggested'),
        Promise.resolve().then(() => broadcastRoomSynthesisSuggested(ROOM_ID, mockMessage)),
    ]);

    for (const evt of [evtA, evtB]) {
        assert.equal(evt.type, 'synthesis_suggested');
        assert.equal(evt.roomId, ROOM_ID);
        assert.equal(evt.message?.data?.kind, 'synthesis_suggestion');
        assert.equal(evt.message?.data?.basedOnMessages, 9);
    }
});
