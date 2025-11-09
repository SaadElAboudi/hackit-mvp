import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import { createApp } from '../src/index.js';

// Helper to start/stop server for tests
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
            { host, port, path, method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } },
            (res) => {
                let data = '';
                res.setEncoding('utf8');
                res.on('data', (c) => (data += c));
                res.on('end', () => resolve({ status: res.statusCode, data }));
            }
        );
        req.on('error', reject);
        req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
        req.write(payload);
        req.end();
    });
}

// Use mock mode by default unless explicitly disabled for real-mode tests
process.env.MOCK_MODE = process.env.MOCK_MODE ?? 'true';

await test('POST /api/search returns expected shape in mock mode', async (t) => {
    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await postJson({ port, path: '/api/search', body: { query: 'changer un pneu' } });
    assert.equal(res.status, 200, 'status should be 200');
    const json = JSON.parse(res.data);
    assert.ok(json.title && typeof json.title === 'string');
    assert.ok(Array.isArray(json.steps) && json.steps.length > 0);
    assert.ok(json.videoUrl && typeof json.videoUrl === 'string');
    assert.ok(json.source && typeof json.source === 'string');
});
