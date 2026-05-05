#!/usr/bin/env node

import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';

const targetUrl = process.env.TARGET_URL || 'http://localhost:3000';
const roomSmokeN = process.env.ROOM_SMOKE_N || '12';
const roomSmokeTimeoutMs = process.env.ROOM_SMOKE_TIMEOUT_MS || '15000';
const runRoomSmoke = process.env.RUN_ROOM_SMOKE !== 'false';

const now = new Date();
const ymd = now.toISOString().slice(0, 10);
const reportPath = process.env.REPORT_PATH || path.resolve(
    process.cwd(),
    '..',
    'docs',
    `observability_validation_report_${ymd}.md`,
);

function formatJson(value) {
    return JSON.stringify(value, null, 2);
}

async function fetchJson(url) {
    try {
        const res = await fetch(url, {
            headers: {
                accept: 'application/json',
            },
        });

        const text = await res.text();
        let json = {};
        try {
            json = text ? JSON.parse(text) : {};
        } catch {
            json = { parseError: true, raw: text.slice(0, 400) };
        }

        return {
            ok: res.ok,
            status: res.status,
            json,
            error: null,
        };
    } catch (err) {
        return {
            ok: false,
            status: 0,
            json: {},
            error: err?.message || 'fetch failed',
        };
    }
}

function runNodeScript(scriptPath, env = {}) {
    return new Promise((resolve) => {
        const child = spawn('node', [scriptPath], {
            cwd: process.cwd(),
            env: {
                ...process.env,
                ...env,
            },
            stdio: ['ignore', 'pipe', 'pipe'],
        });

        let stdout = '';
        let stderr = '';

        child.stdout.on('data', (chunk) => {
            stdout += chunk.toString();
        });

        child.stderr.on('data', (chunk) => {
            stderr += chunk.toString();
        });

        child.on('close', (code) => {
            resolve({ code: code ?? 1, stdout, stderr });
        });
    });
}

function resolveRoomSmokeTarget(urlValue) {
    const parsed = new URL(urlValue);
    const explicitHost = process.env.SMOKE_API_HOST;
    const explicitPort = process.env.SMOKE_API_PORT;

    if (explicitHost && explicitPort) {
        return {
            runnable: true,
            host: explicitHost,
            port: String(explicitPort),
            reason: 'Using SMOKE_API_HOST/SMOKE_API_PORT overrides.',
        };
    }

    if (parsed.protocol === 'http:') {
        return {
            runnable: true,
            host: parsed.hostname,
            port: parsed.port || '80',
            reason: 'Derived host/port from TARGET_URL.',
        };
    }

    return {
        runnable: false,
        host: parsed.hostname,
        port: parsed.port || '443',
        reason:
            'HTTPS target detected. roomSmoke.js uses raw HTTP; provide SMOKE_API_HOST/SMOKE_API_PORT that can be reached over HTTP (e.g. internal gateway).',
    };
}

function statusLine(status, title) {
    return `### ${title}\n\nResult: ${status}\n`;
}

async function main() {
    const sections = [];
    let hasHardFailure = false;

    sections.push(`# Observability Validation Report (${ymd})\n`);
    sections.push(`Scope: BL-002 (staging observability validation)`);
    sections.push('Runbook source: `docs/observability_staging_checklist.md`');
    sections.push('Executed by: observabilityAudit.js');
    sections.push(`Execution time: ${now.toISOString()}\n`);

    sections.push('## Environment\n');
    sections.push(`- Target URL: ${targetUrl}`);
    sections.push(`- RUN_ROOM_SMOKE: ${String(runRoomSmoke)}`);
    sections.push(`- ROOM_SMOKE_N: ${roomSmokeN}`);
    sections.push(`- ROOM_SMOKE_TIMEOUT_MS: ${roomSmokeTimeoutMs}\n`);

    sections.push('## Evidence Summary\n');

    // Step 1
    const health = await fetchJson(`${targetUrl}/health`);
    const integrations = await fetchJson(`${targetUrl}/health/integrations`);
    const observability = await fetchJson(`${targetUrl}/health/observability`);

    const healthPass = health.ok && health.json?.ok === true;
    const integrationsPass = integrations.ok && integrations.json?.ok === true;
    const obsShapePass =
        observability.ok &&
        observability.json?.ok === true &&
        observability.json?.snapshot &&
        Array.isArray(observability.json?.alerts);

    const step1Status = healthPass && integrationsPass && obsShapePass
        ? 'PASS'
        : (health.error || integrations.error || observability.error)
            ? 'BLOCKED'
            : 'PARTIAL PASS';

    if (step1Status === 'BLOCKED') {
        hasHardFailure = true;
    }

    sections.push(statusLine(step1Status, 'Step 1 - Baseline health endpoints'));
    sections.push('Observed payload summary:\n');
    sections.push('```json');
    sections.push(formatJson({
        health: {
            ok: health.json?.ok,
            status: health.status,
            error: health.error,
            mode: health.json?.mode,
            mock: health.json?.mock,
            version: health.json?.version,
        },
        integrations: {
            ok: integrations.json?.ok,
            status: integrations.status,
            error: integrations.error,
            readiness: integrations.json?.status,
            dbConnected: integrations.json?.dbConnected,
        },
        observability: {
            ok: observability.json?.ok,
            status: observability.status,
            error: observability.error,
            hasSnapshot: Boolean(observability.json?.snapshot),
            alerts: Array.isArray(observability.json?.alerts)
                ? observability.json.alerts.length
                : null,
            endpointKeys: Object.keys(observability.json?.snapshot?.endpoints || {}),
        },
    }));
    sections.push('```\n');

    // Step 2
    const smokeTarget = resolveRoomSmokeTarget(targetUrl);
    if (!runRoomSmoke) {
        sections.push(statusLine('SKIPPED', 'Step 2 - Room smoke on target environment'));
        sections.push('- Skipped because `RUN_ROOM_SMOKE=false`.\n');
    } else if (!smokeTarget.runnable) {
        sections.push(statusLine('BLOCKED', 'Step 2 - Room smoke on target environment'));
        sections.push(`- ${smokeTarget.reason}`);
        sections.push(`- Derived target: host=${smokeTarget.host} port=${smokeTarget.port}\n`);
    } else {
        const smoke = await runNodeScript(path.resolve(process.cwd(), 'scripts', 'roomSmoke.js'), {
            API_HOST: smokeTarget.host,
            API_PORT: smokeTarget.port,
            N: roomSmokeN,
            SMOKE_TIMEOUT_MS: roomSmokeTimeoutMs,
        });

        const smokePassed = smoke.code === 0;
        if (!smokePassed) {
            hasHardFailure = true;
        }

        sections.push(statusLine(smokePassed ? 'PASS' : 'FAIL', 'Step 2 - Room smoke on target environment'));
        sections.push('Command:\n');
        sections.push('```bash');
        sections.push(`API_HOST=${smokeTarget.host} API_PORT=${smokeTarget.port} N=${roomSmokeN} SMOKE_TIMEOUT_MS=${roomSmokeTimeoutMs} node scripts/roomSmoke.js`);
        sections.push('```\n');
        sections.push('Output excerpt:\n');
        sections.push('```text');
        const merged = `${smoke.stdout}\n${smoke.stderr}`.trim();
        sections.push((merged || '(no output)').slice(0, 4000));
        sections.push('```\n');
    }

    // Step 3
    const expectedAlertCodes = [
        'slo_latency_breach',
        'room_message_5xx_spike',
        'gemini_timeout_spike',
        'youtube_error_spike',
        'ws_fanout_failures',
        'persistent_alerts',
    ];
    const observedCodes = Array.isArray(observability.json?.alerts)
        ? observability.json.alerts.map((a) => a.code).filter(Boolean)
        : [];

    sections.push(statusLine('PARTIAL PASS', 'Step 3 - Alert code wiring'));
    sections.push(`- Expected codes: ${expectedAlertCodes.join(', ')}`);
    sections.push(`- Codes currently active: ${observedCodes.length ? observedCodes.join(', ') : '(none active)'}`);
    sections.push('- Full code-path validation still requires induced staging traffic/fault scenarios.\n');

    // Step 7 summary
    sections.push('## Go / No-Go\n');
    if (hasHardFailure) {
        sections.push('- BL-002 status: IN PROGRESS');
        sections.push('- Decision: NO-GO until smoke pass and critical signals are validated in staging.\n');
    } else {
        sections.push('- BL-002 status: IN PROGRESS (automation pass, pending manual staging checks 4-6)');
        sections.push('- Decision: CONDITIONAL GO for backend observability shape; complete manual steps before final sign-off.\n');
    }

    sections.push('## Required Follow-ups\n');
    sections.push('1. Complete checklist Steps 4-6 manually in staging (banner, telemetry, request correlation).');
    sections.push('2. Attach dashboard screenshots/links and approver name.');
    sections.push('3. Re-run this script after any observability-related deploy to keep evidence fresh.\n');

    await fs.writeFile(reportPath, `${sections.join('\n')}\n`, 'utf8');

    console.log(`[observability-audit] report written: ${reportPath}`);
    if (hasHardFailure) {
        console.error('[observability-audit] blocking checks failed; returning exit code 1');
        process.exit(1);
    }
}

main().catch((err) => {
    console.error('[observability-audit] unexpected error:', err?.message || err);
    process.exit(1);
});
