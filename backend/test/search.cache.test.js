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
        res.on('end', () => resolve({ status: res.statusCode, data, headers: res.headers }));
      }
    );
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => reject(new Error('timeout')));
    req.write(payload);
    req.end();
  });
}

await test('POST /api/search serves repeated requests from cache and exposes alternatives', async (t) => {
  let callCount = 0;
  setSearchYouTube(async (term, options) => {
    callCount += 1;
    return {
      title: `Video for ${term}`,
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      videoId: 'dQw4w9WgXcQ',
      source: 'test-double',
      nextPageToken: options?.pageToken ? `${options.pageToken}-next` : 'next-1',
      alternatives: [
        { title: 'Alt 1', url: 'https://youtu.be/111', videoId: '111', source: 'test-double' },
        { title: 'Alt 2', url: 'https://youtu.be/222', videoId: '222', source: 'test-double' },
      ],
    };
  });

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const payload = { query: 'learn guitar', maxResults: 2, pageToken: 'abc' };
  const first = await postJson({ port, path: '/api/search', body: payload });
  assert.equal(first.status, 200);
  assert.equal(first.headers['x-search-cache'], 'MISS');
  const firstJson = JSON.parse(first.data);
  assert.equal(firstJson.cache.hit, false);
  assert.equal(firstJson.alternatives.length, 2);
  assert.equal(firstJson.nextPageToken, 'abc-next');
  assert.ok(Array.isArray(firstJson.relatedQueries));

  const second = await postJson({ port, path: '/api/search', body: payload });
  assert.equal(second.status, 200);
  assert.equal(second.headers['x-search-cache'], 'HIT');
  const secondJson = JSON.parse(second.data);
  assert.equal(secondJson.cache.hit, true);
  assert.ok(secondJson.badges.includes('CACHED'));
  assert.equal(callCount, 1);
});
