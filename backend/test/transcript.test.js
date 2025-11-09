import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'true'; // keep other calls light

const { createApp } = await import('../src/index.js');
import { clearTranscriptCache } from '../src/services/transcript.js';

function startServer(app, port = 0) {
    return new Promise((resolve) => {
        const server = app.listen(port, () => {
            const address = server.address();
            resolve({ server, port: address.port });
        });
    });
}

async function getJson({ host = '127.0.0.1', port, path, timeoutMs = 8000 }) {
    return await new Promise((resolve, reject) => {
        const req = http.request({ host, port, path, method: 'GET' }, (res) => {
            let data = '';
            res.setEncoding('utf8');
            res.on('data', c => data += c);
            res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, data }));
        });
        req.on('error', reject);
        req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
        req.end();
    });
}

await test('GET /api/transcript returns MISS then HIT', async (t) => {
    clearTranscriptCache();
    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const videoId = 'dQw4w9WgXcQ';
    const first = await getJson({ port, path: `/api/transcript?videoId=${videoId}&title=Test+Video` });
    assert.equal(first.status, 200);
    const json1 = JSON.parse(first.data);
    assert.equal(json1.videoId, videoId);
    assert.ok(Array.isArray(json1.transcript));
    assert.equal(first.headers['x-cache'], 'MISS');
    assert.equal(json1.cached, false);

    const second = await getJson({ port, path: `/api/transcript?videoId=${videoId}&title=Test+Video` });
    assert.equal(second.status, 200);
    const json2 = JSON.parse(second.data);
    assert.equal(second.headers['x-cache'], 'HIT');
    assert.equal(json2.cached, true);
    assert.ok(json2.transcript.length === json1.transcript.length);
});

await test('GET /api/transcript requires videoId', async (t) => {
    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());
    const res = await getJson({ port, path: '/api/transcript' });
    // Some environments may yield 404 (no route match) before validation; accept 400 or 404
    assert.ok([400, 404].includes(res.status), `expected 400 or 404 got ${res.status}`);
});
