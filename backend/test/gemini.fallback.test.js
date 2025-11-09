import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

// Ensure logs quiet and disable actual Gemini usage
process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'false';
process.env.USE_GEMINI = 'true'; // simulate configured
process.env.USE_GEMINI_REFORMULATION = 'true';
process.env.GEMINI_API_KEY = ''; // missing key triggers immediate throw in generateWithGemini
process.env.ALLOW_FALLBACK = 'true';

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

await test('Gemini disabled path falls back to heuristic summary when key missing', async (t) => {
    // Provide a deterministic video result
    setSearchYouTube(async () => ({ title: 'Simple Test Video', url: 'https://youtu.be/test', source: 'test-double' }));
    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await postJson({ port, path: '/api/search', body: { query: 'make coffee' } });
    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.equal(json.title, 'Simple Test Video');
    assert.ok(Array.isArray(json.steps) && json.steps.length === 5, 'heuristic summary yields 5 steps');
});
