#!/usr/bin/env node
// Simple CI smoke test: calls /api/search and validates essential fields.
// Exits non-zero on failure.

import http from 'node:http';

const query = process.env.SMOKE_QUERY || 'test plomberie';
const host = process.env.API_HOST || 'localhost';
const port = process.env.API_PORT || 3000;
const timeoutMs = Number(process.env.SMOKE_TIMEOUT_MS || 8000);

function fail(msg) {
    console.error('\n[ciSmoke] FAIL:', msg);
    process.exit(1);
}

function ok(msg) {
    console.log('[ciSmoke] OK:', msg);
}

const payload = JSON.stringify({ query });
const req = http.request(
    {
        host,
        port,
        path: '/api/search',
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payload),
        },
    },
    (res) => {
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
            if (res.statusCode !== 200) {
                return fail(`Unexpected status ${res.statusCode}. Body: ${data.slice(0, 300)}`);
            }
            try {
                const json = JSON.parse(data);
                if (!json.title || !Array.isArray(json.steps) || json.steps.length === 0) {
                    return fail('Missing required fields (title, non-empty steps).');
                }
                if (!json.videoUrl || typeof json.videoUrl !== 'string') {
                    return fail('Missing videoUrl string.');
                }
                ok(`Search succeeded: title="${json.title}" steps=${json.steps.length}`);
                process.exit(0);
            } catch (e) {
                fail('Invalid JSON response: ' + e.message);
            }
        });
    }
);

req.setTimeout(timeoutMs, () => {
    fail('Request timeout after ' + timeoutMs + 'ms');
});
req.on('error', (err) => fail(err.message));
req.write(payload);
req.end();
