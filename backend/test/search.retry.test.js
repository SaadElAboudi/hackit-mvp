import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

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

await test('POST /api/search no-results on original term falls back to mock-fallback (no reformulation)', async (t) => {
    // Current server logic only retries if a reformulated term differs from original.
    // Since we have no reformulation active, a YOUTUBE_NO_RESULTS triggers immediate mock fallback.
    let callCount = 0;
    setSearchYouTube(async (term) => {
        callCount++;
        if (callCount === 1) {
            const err = new Error('No results for reformulated');
            err.code = 'YOUTUBE_NO_RESULTS';
            throw err;
        }
        return { title: 'Recovered Original Query Video', url: 'https://youtu.be/recovered', source: 'test-double' };
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await postJson({ port, path: '/api/search', body: { query: 'build simple bird house' } });
    assert.equal(res.status, 200);
    const json = JSON.parse(res.data);
    assert.ok(json.title.startsWith('Mock:'), 'falls back to mock title');
    assert.equal(json.source, 'mock-fallback');
    assert.equal(callCount, 1, 'only one attempt performed (no reformulation retry)');
});
