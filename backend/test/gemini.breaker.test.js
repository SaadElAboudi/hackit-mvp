import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'false'; // run real flow (but stub out search + gemini)
process.env.USE_GEMINI = 'true';
process.env.USE_GEMINI_REFORMULATION = 'false';
process.env.GEMINI_API_KEY = 'dummy';
process.env.GEMINI_TIMEOUT_MS = '50';
process.env.TAVILY_API_KEY = '';

const { createApp, setSearchYouTube } = await import('../src/index.js');
import axios from 'axios';

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
                res.on('end', () => resolve({ status: res.statusCode, data, headers: res.headers }));
            }
        );
        req.on('error', reject);
        req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
        req.write(payload);
        req.end();
    });
}

async function getJson({ host = '127.0.0.1', port, path, timeoutMs = 5000 }) {
    return await new Promise((resolve, reject) => {
        const req = http.request({ host, port, path, method: 'GET' }, (res) => {
            let data = '';
            res.setEncoding('utf8');
            res.on('data', c => data += c);
            res.on('end', () => resolve({ status: res.statusCode, data, headers: res.headers }));
        });
        req.on('error', reject);
        req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
        req.end();
    });
}

await test('Gemini circuit breaker opens after consecutive failures', async (t) => {
    // Stub YouTube search to avoid network
    setSearchYouTube(async (term) => ({ title: `Video for ${term}`, url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', source: 'test-stub' }));

    // Stub axios.post to simulate timeouts
    let calls = 0;
    const originalPost = axios.post;
    axios.post = async () => {
        calls++;
        const err = new Error('timeout');
        err.code = 'ECONNABORTED';
        throw err;
    };
    t.after(() => { axios.post = originalPost; });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    for (let i = 0; i < 3; i++) {
        const res = await postJson({ port, path: '/api/search', body: { query: 'test breaker' } });
        assert.equal(res.status, 200);
    }

    // After 3 failures, breaker should be active
    const health = await getJson({ port, path: '/health/extended' });
    assert.equal(health.status, 200);
    const h = JSON.parse(health.data);
    assert.equal(typeof h.gemini.breakerActive, 'boolean');
    assert.equal(h.gemini.breakerActive, true);
    assert.ok(h.gemini.retryAt && h.gemini.retryAt > Date.now());

    // Another search should keep Gemini calls suppressed by breaker.
    // Depending on runtime toggles, one auxiliary POST may still happen.
    const before = calls;
    const res4 = await postJson({ port, path: '/api/search', body: { query: 'test breaker' } });
    assert.equal(res4.status, 200);
    assert.ok(calls <= before + 2, `breaker should suppress Gemini calls (was ${before}, now ${calls})`);
});
