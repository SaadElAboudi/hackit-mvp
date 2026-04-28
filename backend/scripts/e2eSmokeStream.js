#!/usr/bin/env node

import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.MOCK_MODE = process.env.MOCK_MODE || 'true';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const artifactsDir = path.resolve(__dirname, '../artifacts/e2e-smoke');

function timestampId() {
    return new Date().toISOString().replace(/[:.]/g, '-');
}

async function writeArtifact(name, payload) {
    await fs.mkdir(artifactsDir, { recursive: true });
    const filePath = path.join(artifactsDir, `${timestampId()}-${name}.json`);
    await fs.writeFile(filePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
    return filePath;
}

function fail(message, context = {}) {
    const err = new Error(message);
    err.context = context;
    throw err;
}

function parseSseChunk(raw) {
    const lines = String(raw || '').split('\n');
    const dataLine = lines.find((line) => line.startsWith('data: '));
    if (!dataLine) return null;

    const jsonStr = dataLine.slice('data: '.length);
    try {
        return JSON.parse(jsonStr);
    } catch (_) {
        return null;
    }
}

async function run() {
    const { createApp } = await import('../src/index.js');
    const app = createApp();

    const server = await new Promise((resolve) => {
        const s = app.listen(0, () => resolve(s));
    });

    const port = server.address().port;
    const host = '127.0.0.1';
    const query = process.env.SMOKE_QUERY || 'deboucher evier';

    const networkTrace = {
        request: {
            method: 'GET',
            path: `/api/search/stream?query=${encodeURIComponent(query)}`,
            headers: { Accept: 'text/event-stream' },
        },
        response: {
            status: 0,
            headers: {},
        },
        events: [],
    };

    try {
        await new Promise((resolve, reject) => {
            const req = http.request(
                {
                    host,
                    port,
                    path: networkTrace.request.path,
                    method: 'GET',
                    headers: networkTrace.request.headers,
                },
                (res) => {
                    networkTrace.response.status = Number(res.statusCode || 0);
                    networkTrace.response.headers = res.headers;

                    let buffer = '';
                    res.setEncoding('utf8');
                    res.on('data', (chunk) => {
                        buffer += chunk;
                        let idx = buffer.indexOf('\n\n');
                        while (idx !== -1) {
                            const rawEvent = buffer.slice(0, idx);
                            buffer = buffer.slice(idx + 2);
                            const parsed = parseSseChunk(rawEvent);
                            if (parsed) {
                                networkTrace.events.push(parsed);
                                if (parsed.type === 'done') {
                                    resolve();
                                    return;
                                }
                            }
                            idx = buffer.indexOf('\n\n');
                        }
                    });
                    res.on('error', reject);
                    res.on('end', resolve);
                }
            );

            req.setTimeout(10000, () => reject(new Error('SSE request timeout after 10s')));
            req.on('error', reject);
            req.end();
        });

        if (networkTrace.response.status !== 200) {
            fail(`Unexpected status: ${networkTrace.response.status}`, { networkTrace });
        }
        const contentType = String(networkTrace.response.headers['content-type'] || '');
        if (!contentType.includes('text/event-stream')) {
            fail(`Unexpected content-type: ${contentType}`, { networkTrace });
        }

        const events = networkTrace.events;
        const typeSet = new Set(events.map((event) => event?.type));
        if (!typeSet.has('meta')) fail('Missing meta event', { networkTrace });
        if (!typeSet.has('partial')) fail('Missing partial event', { networkTrace });
        if (!typeSet.has('final')) fail('Missing final event', { networkTrace });
        if (!typeSet.has('done')) fail('Missing done event', { networkTrace });

        const finalEvent = events.find((event) => event?.type === 'final');
        if (!finalEvent || !Array.isArray(finalEvent.citations)) {
            fail('Final event missing citations array', { networkTrace });
        }
        if (finalEvent.citations.length === 0) {
            fail('Expected at least one citation in final event', { networkTrace });
        }

        const hasTimestampedCitation = finalEvent.citations.some((citation) =>
            /[?&]t=\d+/.test(String(citation?.url || ''))
        );
        if (!hasTimestampedCitation) {
            fail('Expected at least one citation URL with timestamp parameter', { networkTrace });
        }

        const artifactPath = await writeArtifact('success-network-log', networkTrace);
        console.log(`[e2eSmokeStream] OK: stream flow validated. Artifact: ${artifactPath}`);
    } catch (err) {
        const artifactPath = await writeArtifact('failure-network-log', {
            message: err?.message || 'Unknown error',
            context: err?.context || null,
            networkTrace,
        });
        console.error(`[e2eSmokeStream] FAIL: ${err?.message || 'Unknown error'}`);
        console.error(`[e2eSmokeStream] Failure artifact: ${artifactPath}`);
        process.exitCode = 1;
    } finally {
        await new Promise((resolve) => server.close(() => resolve()));
    }
}

run().catch(async (err) => {
    const artifactPath = await writeArtifact('fatal-network-log', {
        message: err?.message || 'Fatal error',
        stack: err?.stack || null,
    });
    console.error(`[e2eSmokeStream] FATAL: ${err?.message || 'Fatal error'}`);
    console.error(`[e2eSmokeStream] Fatal artifact: ${artifactPath}`);
    process.exit(1);
});
