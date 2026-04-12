/**
 * E2E WebSocket multi-client tests for the Salons (Rooms) WS hub.
 *
 * Tests:
 *   1. Two clients join the same room and both receive `research_attached`.
 *   2. A disconnected client is NOT in the broadcast set — no crash, only live
 *      clients receive the frame.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { WebSocket } from 'ws';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'true';

const { createApp } = await import('../src/index.js');
const { attachWebSocketServer } = await import('../src/services/threadRooms.js');
const { broadcastRoomResearchAttached } = await import('../src/services/roomWS.js');

// Valid 24-char hex roomId (no DB lookup required — roomWS only checks the URL regex)
const ROOM_ID = 'aabbccddeeff001122334455';

/** Start an HTTP server bound to a random port and attach the WS hub. */
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

/**
 * Open a WS client, wait for it to be connected, send a `join` frame,
 * and resolve with { ws, waitForFrame }.
 *
 * `waitForFrame(predicate, timeoutMs)` resolves with the first message
 * whose parsed JSON satisfies the predicate.
 */
function connectClient(port, roomId) {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}/ws/rooms/${roomId}`);

        const pending = []; // { predicate, resolve, reject, timer }

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
            ws.send(JSON.stringify({ type: 'join', roomId, userId: `test-user-${Math.random().toString(36).slice(2)}` }));

            function waitForFrame(predicate, timeoutMs = 5000) {
                return new Promise((res, rej) => {
                    const timer = setTimeout(() => rej(new Error(`waitForFrame timeout (${timeoutMs}ms)`)), timeoutMs);
                    pending.push({ predicate, resolve: res, reject: rej, timer });
                });
            }

            resolve({ ws, waitForFrame });
        });
    });
}

// ─── Test 1: two live clients both receive research_attached ─────────────────

await test('two WS clients in the same room both receive research_attached', async (t) => {
    const { server, port } = await startServer();
    t.after(() => server.close());

    const [a, b] = await Promise.all([
        connectClient(port, ROOM_ID),
        connectClient(port, ROOM_ID),
    ]);

    t.after(() => { try { a.ws.close(); } catch { } });
    t.after(() => { try { b.ws.close(); } catch { } });

    // Wait until both have received their `joined` confirmation
    await Promise.all([
        a.waitForFrame((m) => m.type === 'joined'),
        b.waitForFrame((m) => m.type === 'joined'),
    ]);

    // Prepare mock research message (same shape as roomOrchestrator sends)
    const mockMessage = {
        _id: '507f1f77bcf86cd799439011',
        roomId: ROOM_ID,
        type: 'research',
        data: {
            query: 'changer un pneu',
            title: 'Comment changer un pneu efficacement',
            keyTakeaways: ['Vérifier la pression', 'Serrer les boulons en étoile', 'Tester à basse vitesse'],
            citations: [{ url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30', startSec: 30, quote: 'Déposez la roue crevée' }],
            chapters: [{ title: 'Introduction', startSec: 0 }, { title: 'Démontage', startSec: 45 }],
        },
    };

    // Set up listeners BEFORE broadcasting
    const [frameA, frameB] = await Promise.all([
        a.waitForFrame((m) => m.type === 'research_attached'),
        b.waitForFrame((m) => m.type === 'research_attached'),
        // Broadcast happens synchronously, listeners are already registered above
        Promise.resolve().then(() => broadcastRoomResearchAttached(ROOM_ID, mockMessage)),
    ]);

    // Both frames should carry the correct shape
    for (const frame of [frameA, frameB]) {
        assert.equal(frame.type, 'research_attached', 'frame type is research_attached');
        assert.equal(frame.roomId, ROOM_ID, 'frame carries correct roomId');
        assert.ok(frame.message && typeof frame.message === 'object', 'frame.message is present');
        assert.equal(frame.message.data.query, 'changer un pneu', 'query is preserved');
        assert.ok(Array.isArray(frame.message.data.keyTakeaways), 'keyTakeaways is array');
        assert.ok(frame.message.data.keyTakeaways.length === 3, 'all 3 keyTakeaways received');
        assert.ok(Array.isArray(frame.message.data.citations), 'citations is array');
        assert.ok(Array.isArray(frame.message.data.chapters), 'chapters is array');
    }
});

// ─── Test 2: disconnected client does not crash broadcast ────────────────────

await test('disconnected client is excluded from research_attached broadcast', async (t) => {
    const { server, port } = await startServer();
    t.after(() => server.close());

    const [a, b] = await Promise.all([
        connectClient(port, ROOM_ID),
        connectClient(port, ROOM_ID),
    ]);

    t.after(() => { try { b.ws.close(); } catch { } });

    // Wait for both to join
    await Promise.all([
        a.waitForFrame((m) => m.type === 'joined'),
        b.waitForFrame((m) => m.type === 'joined'),
    ]);

    // Disconnect client A
    await new Promise((res) => {
        a.ws.once('close', res);
        a.ws.close();
    });

    // Give the server a tick to process the close event
    await new Promise((res) => setTimeout(res, 50));

    const mockMessage = {
        _id: '507f1f77bcf86cd799439012',
        roomId: ROOM_ID,
        type: 'research',
        data: {
            query: 'réparer un vélo',
            title: 'Réparer un vélo en 5 étapes',
            keyTakeaways: ['Démonter la chaîne', 'Lubrifier', 'Remonter'],
            citations: [],
            chapters: [],
        },
    };

    // Only client B should receive the frame — no error should be thrown
    const [frameB] = await Promise.all([
        b.waitForFrame((m) => m.type === 'research_attached'),
        Promise.resolve().then(() => broadcastRoomResearchAttached(ROOM_ID, mockMessage)),
    ]);

    assert.equal(frameB.type, 'research_attached', 'live client receives research_attached');
    assert.equal(frameB.message.data.query, 'réparer un vélo', 'correct query delivered to live client');
});
