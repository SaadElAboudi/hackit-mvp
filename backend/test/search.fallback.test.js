import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

// Ensure quiet logs and real-mode to exercise fallback
process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'false';
process.env.ALLOW_FALLBACK = 'true';
process.env.USE_GEMINI = 'false';

const { createApp, setSearchYouTube } = await import('../src/index.js');

function startServer(app, port = 0) {
    return new Promise((resolve) => {
        const server = app.listen(port, () => {
            const address = server.address();
            resolve({ server, port: address.port });
        });
    });
}

async function postJson({ host = '127.0.0.1', port, path, body, timeoutMs = 5000 }) {
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

await test('POST /api/search falls back to mock-fallback on search error when allowed', async (t) => {
    // Override search to simulate an error
    setSearchYouTube(() => {
        const err = new Error('Simulated YouTube failure');
        err.code = 'YOUTUBE_API_ERROR';
        throw err;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await postJson({ port, path: '/api/search', body: { query: 'how to tie a tie' } });
    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.source, 'mock-fallback');
    assert.ok(Array.isArray(json.steps) && json.steps.length > 0);
});
