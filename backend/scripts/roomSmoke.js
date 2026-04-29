#!/usr/bin/env node
/**
 * roomSmoke.js — Load smoke test for the Salons (Rooms) feature.
 *
 * Validates:
 *   1. Room creation
 *   2. Sending N messages (including one AI command)
 *   3. Listing messages back
 *   4. /health/observability snapshot includes room route latencies
 *   5. /health/integrations endpoint responds
 *
 * Usage:
 *   API_HOST=localhost API_PORT=3000 node scripts/roomSmoke.js
 *   N=20 node scripts/roomSmoke.js
 *
 * Exits 0 on full pass, non-zero on any violation.
 */

import http from 'node:http';

const host = process.env.API_HOST || 'localhost';
const port = Number(process.env.API_PORT || 3000);
const N = Number(process.env.N || 10); // messages to send per room
const timeoutMs = Number(process.env.SMOKE_TIMEOUT_MS || 10000);
const userId = `smoke-${Date.now()}`;

let passed = 0;
let failed = 0;

function ok(label) {
    console.log(`  [OK]  ${label}`);
    passed++;
}

function fail(label, detail) {
    console.error(`  [FAIL] ${label}${detail ? ': ' + detail : ''}`);
    failed++;
}

async function request(method, path, body) {
    return new Promise((resolve, reject) => {
        const payload = body ? JSON.stringify(body) : '';
        const headers = {
            'content-type': 'application/json',
            'x-user-id': userId,
            'x-display-name': 'SmokeBot',
        };
        if (payload) headers['content-length'] = String(Buffer.byteLength(payload));

        const req = http.request({ host, port, path, method, headers }, (res) => {
            let data = '';
            res.on('data', (c) => (data += c));
            res.on('end', () => {
                let json;
                try { json = JSON.parse(data); } catch { json = {}; }
                resolve({ status: res.statusCode, json });
            });
        });
        req.setTimeout(timeoutMs, () => {
            req.destroy(new Error(`Timeout ${timeoutMs}ms on ${method} ${path}`));
        });
        req.on('error', reject);
        if (payload) req.write(payload);
        req.end();
    });
}

// ── 1. Health baseline ────────────────────────────────────────────────────────

console.log('\n[roomSmoke] Step 1: health baseline');
const health = await request('GET', '/health');
if (health.status === 200 && health.json.ok) {
    ok(`/health → ok (mode=${health.json.mode})`);
} else {
    fail('/health', `status=${health.status}`);
}

const intHealth = await request('GET', '/health/integrations');
if (intHealth.status === 200 && intHealth.json.ok) {
    ok(`/health/integrations → ok (status=${intHealth.json.status})`);
} else {
    fail('/health/integrations', `status=${intHealth.status}`);
}

// ── 2. Create room ────────────────────────────────────────────────────────────

console.log('\n[roomSmoke] Step 2: create room');
const createRes = await request('POST', '/api/rooms', {
    name: `Smoke-${Date.now()}`,
    type: 'group',
    members: [{ userId, displayName: 'SmokeBot' }],
});
if (createRes.status !== 201 && createRes.status !== 200) {
    fail('POST /api/rooms', `status=${createRes.status} body=${JSON.stringify(createRes.json).slice(0, 120)}`);
    process.exit(1);
}
const room = createRes.json.room;
if (!room?.id) {
    fail('POST /api/rooms', 'response missing room.id');
    process.exit(1);
}
ok(`Room created: id=${room.id}`);

// ── 3. Send N messages ────────────────────────────────────────────────────────

console.log(`\n[roomSmoke] Step 3: send ${N} messages`);
const latencies = [];
for (let i = 0; i < N; i++) {
    const content = i === 2
        ? `/doc Résumé de la réunion smoke ${i}`  // AI command on 3rd message
        : `Message de smoke test #${i} — ${Date.now()}`;
    const t0 = Date.now();
    const res = await request('POST', `/api/rooms/${room.id}/messages`, { content });
    const ms = Date.now() - t0;
    latencies.push(ms);
    if (res.status !== 200 && res.status !== 201) {
        fail(`send message #${i}`, `status=${res.status}`);
    }
}
const sorted = [...latencies].sort((a, b) => a - b);
const p50 = sorted[Math.floor(sorted.length * 0.5)];
const p95 = sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1)];
const SLO_P95 = 2000;
if (p95 <= SLO_P95) {
    ok(`p95 latency ${p95}ms ≤ ${SLO_P95}ms SLO (p50=${p50}ms, n=${N})`);
} else {
    fail(`p95 latency SLO breach`, `p95=${p95}ms > ${SLO_P95}ms threshold`);
}

// ── 4. List messages back ─────────────────────────────────────────────────────

console.log('\n[roomSmoke] Step 4: list messages');
const listRes = await request('GET', `/api/rooms/${room.id}/messages`);
if (listRes.status === 200 && Array.isArray(listRes.json.messages)) {
    ok(`GET messages → ${listRes.json.messages.length} messages`);
} else {
    fail('GET /api/rooms/:id/messages', `status=${listRes.status}`);
}

// ── 5. Observability snapshot ─────────────────────────────────────────────────

console.log('\n[roomSmoke] Step 5: observability snapshot');
const obsRes = await request('GET', '/health/observability');
if (obsRes.status === 200 && obsRes.json.ok) {
    const snap = obsRes.json.snapshot;
    const roomRoute = snap?.endpoints?.['POST /api/rooms/:id/messages'];
    if (roomRoute && roomRoute.requests >= N) {
        ok(`Observability tracks room messages: ${roomRoute.requests} requests, p95=${roomRoute.latencyMs.p95}ms`);
    } else {
        fail('Observability snapshot', `room route missing or request count low: ${JSON.stringify(roomRoute)}`);
    }
    if (Array.isArray(obsRes.json.alerts)) {
        if (obsRes.json.alerts.length === 0) {
            ok('No active alerts');
        } else {
            const critical = obsRes.json.alerts.filter(a => a.severity === 'critical');
            if (critical.length > 0) {
                fail('Critical alerts active', critical.map(a => a.code).join(', '));
            } else {
                ok(`${obsRes.json.alerts.length} non-critical alert(s): ${obsRes.json.alerts.map(a => a.code).join(', ')}`);
            }
        }
    }
} else {
    fail('/health/observability', `status=${obsRes.status}`);
}

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\n[roomSmoke] Done — ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
