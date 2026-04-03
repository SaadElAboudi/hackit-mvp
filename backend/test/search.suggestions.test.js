import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

process.env.NODE_ENV = 'test';
process.env.MOCK_MODE = 'false';
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

await test('search response includes queryAnalysis/suggestions and endpoint returns suggestions', async (t) => {
  setSearchYouTube(async () => ({
    title: 'How to solder electronics',
    url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    videoId: 'dQw4w9WgXcQ',
    source: 'test-double',
    alternatives: [{ title: 'Soldering basics tutorial', url: 'https://youtu.be/abc', videoId: 'abc', source: 'test-double' }],
  }));

  const app = createApp();
  const { server, port } = await startServer(app);
  t.after(() => server.close());

  const searchRes = await postJson({ port, path: '/api/search', body: { query: 'solder tiny wires', tone: 'friendly' } });
  assert.equal(searchRes.status, 200);
  const searchJson = JSON.parse(searchRes.data);
  assert.equal(searchJson.queryAnalysis.complexity, 'low');
  assert.ok(['tldr', 'standard', 'deep'].includes(searchJson.queryAnalysis.recommendedSummaryLength));
  assert.ok(Array.isArray(searchJson.suggestions));
  assert.ok(searchJson.suggestions.length > 0);

  const suggestionsRes = await getJson({ port, path: '/api/search/suggestions?query=solder%20tiny%20wires' });
  assert.equal(suggestionsRes.status, 200);
  const suggestionsJson = JSON.parse(suggestionsRes.data);
  assert.ok(Array.isArray(suggestionsJson.suggestions));
  assert.ok(suggestionsJson.suggestions.length > 0);
  assert.ok(typeof suggestionsJson.recentCount === 'number');
});
