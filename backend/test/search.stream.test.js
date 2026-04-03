import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

// Silence request logs and force mock mode for deterministic streaming
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

await test('GET /api/search/stream streams meta, partial steps, then done', async (t) => {
    const app = createApp();
    const { server, port } = await startServer(app);
    t.after(() => server.close());

    const events = [];
    const headersOut = {};

    await new Promise((resolve, reject) => {
        const req = http.request({
            host: '127.0.0.1',
            port,
            path: '/api/search/stream?query=deboucher+evier',
            method: 'GET',
            headers: { Accept: 'text/event-stream' }
        }, (res) => {
            headersOut['content-type'] = res.headers['content-type'];
            let buffer = '';
            res.setEncoding('utf8');
            res.on('data', (chunk) => {
                buffer += chunk;
                // Parse complete SSE messages separated by double newlines
                let idx;
                while ((idx = buffer.indexOf('\n\n')) !== -1) {
                    const raw = buffer.slice(0, idx);
                    buffer = buffer.slice(idx + 2);
                    const line = raw.split('\n').find((l) => l.startsWith('data: '));
                    if (!line) continue;
                    const jsonStr = line.slice('data: '.length);
                    try {
                        const obj = JSON.parse(jsonStr);
                        events.push(obj);
                        if (obj.type === 'done') {
                            resolve();
                        }
                    } catch (_) {
                        // ignore parse errors, continue buffering
                    }
                }
            });
            res.on('end', () => resolve());
        });
        req.on('error', reject);
        req.end();
    });

    assert.ok((headersOut['content-type'] || '').includes('text/event-stream'));
    assert.ok(events.length >= 2, 'should receive at least meta and done');
    assert.equal(events[0].type, 'meta');
    assert.ok(typeof events[0].title === 'string' && events[0].title.length > 0);
    assert.ok(typeof events[0].videoUrl === 'string' && events[0].videoUrl.startsWith('http'));
    assert.ok(typeof events[0].source === 'string');
    assert.ok(typeof events[0].deliveryMode === 'string');

    const partials = events.filter(e => e.type === 'partial');
    assert.ok(partials.length >= 1, 'should stream at least one partial step');
    const finalEvent = events.find(e => e.type === 'final');
    assert.ok(finalEvent, 'final event with citations present');
    assert.ok(Array.isArray(finalEvent.citations));
    if (finalEvent.citations.length) {
        assert.match(finalEvent.citations[0].url, /[?&]t=\d+/);
    }
    assert.ok(Array.isArray(finalEvent.chapters), 'chapters included in final event');
    assert.ok(finalEvent.deliveryPlan && typeof finalEvent.deliveryPlan === 'object');
    assert.ok(Array.isArray(finalEvent.deliveryPlan.nextActions));
    if (finalEvent.chapters.length) {
        for (let i = 1; i < finalEvent.chapters.length; i++) {
            assert.ok(finalEvent.chapters[i].startSec >= finalEvent.chapters[i - 1].startSec);
        }
    }
    assert.equal(events[events.length - 1].type, 'done');
});
