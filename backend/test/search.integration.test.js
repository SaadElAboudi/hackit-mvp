import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

// Ensure we disable request logging in tests before loading the app
process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/index.js');

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
    assert.ok(Array.isArray(json.citations), 'citations array present');
    if (json.citations.length) {
        const c0 = json.citations[0];
        assert.ok(typeof c0.url === 'string');
        assert.match(c0.url, /[?&]t=\d+/);
        assert.ok(typeof c0.startSec === 'number');
    }
    assert.ok(Array.isArray(json.chapters), 'chapters array present');
    assert.ok(json.deliveryPlan && typeof json.deliveryPlan === 'object', 'deliveryPlan object present');
    assert.ok(Array.isArray(json.deliveryPlan.objective), 'deliveryPlan.objective is array');
    assert.ok(Array.isArray(json.deliveryPlan.nextActions), 'deliveryPlan.nextActions is array');
    assert.ok(Array.isArray(json.deliveryPlan.timeline), 'deliveryPlan.timeline is array');
    assert.ok(Array.isArray(json.deliveryPlan.effort), 'deliveryPlan.effort is array');
    assert.ok(Array.isArray(json.deliveryPlan.dependencies), 'deliveryPlan.dependencies is array');
    assert.ok(Array.isArray(json.deliveryPlan.acceptanceCriteria), 'deliveryPlan.acceptanceCriteria is array');
    if (json.chapters.length) {
        for (let i = 1; i < json.chapters.length; i++) {
            assert.ok(json.chapters[i].startSec >= json.chapters[i - 1].startSec);
        }
    }
});


await test('POST /api/search supports summaryLength=tldr and returns response metadata', async (t) => {
    const previousMockMode = process.env.MOCK_MODE;
    process.env.MOCK_MODE = 'true';
    t.after(() => {
        process.env.MOCK_MODE = previousMockMode;
    });

    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const res = await postJson({ port, path: '/api/search', body: { query: 'changer un pneu', summaryLength: 'tldr' } });
    assert.equal(res.status, 200, 'status should be 200');
    const json = JSON.parse(res.data);
    assert.equal(json.summaryLength, 'tldr');
    assert.equal(json.resultMode, 'mock');
    assert.ok(Array.isArray(json.badges));
});
