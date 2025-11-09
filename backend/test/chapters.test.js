import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'true';

const { createApp } = await import('../src/index.js');

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

await test('GET /api/chapters returns ordered chapters (>=5)', async (t) => {
    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const videoId = 'dQw4w9WgXcQ';
    const res = await getJson({ port, path: `/api/chapters?videoId=${videoId}&title=Demo` });
    assert.equal(res.status, 200);
    assert.equal(res.headers['x-cache'], 'MISS');
    const json = JSON.parse(res.data);
    assert.ok(Array.isArray(json.chapters));
    assert.ok(json.chapters.length >= 5);
    for (let i = 1; i < json.chapters.length; i++) {
        assert.ok(json.chapters[i].startSec >= json.chapters[i - 1].startSec);
    }

    const res2 = await getJson({ port, path: `/api/chapters?videoId=${videoId}&title=Demo` });
    assert.equal(res2.status, 200);
    assert.equal(res2.headers['x-cache'], 'HIT');
});
