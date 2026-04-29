#!/usr/bin/env node
/**
 * feedbackKpiBaseline.js
 *
 * Query the feedback aggregate endpoint and print a compact KPI baseline:
 * - total feedback volume over window
 * - average daily volume
 * - rating split (pertinent / moyen / hors_sujet)
 * - per-day timeline
 *
 * Usage:
 *   API_BASE=http://localhost:3000 \
 *   ROOM_ID=<roomId> \
 *   X_USER_ID=<memberUserId> \
 *   DAYS=7 \
 *   node scripts/feedbackKpiBaseline.js
 */

const apiBase = (process.env.API_BASE || 'http://localhost:3000').replace(/\/$/, '');
const roomId = String(process.env.ROOM_ID || '').trim();
const userId = String(process.env.X_USER_ID || '').trim();
const days = Number(process.env.DAYS || 7);

if (!roomId) {
    console.error('[feedbackKpiBaseline] ROOM_ID is required');
    process.exit(1);
}
if (!userId) {
    console.error('[feedbackKpiBaseline] X_USER_ID is required');
    process.exit(1);
}
if (!Number.isFinite(days) || days <= 0 || days > 180) {
    console.error('[feedbackKpiBaseline] DAYS must be a number between 1 and 180');
    process.exit(1);
}

function percent(value, total) {
    if (!total) return '0.0%';
    return `${((value / total) * 100).toFixed(1)}%`;
}

const to = new Date();
const from = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

const url = new URL(`${apiBase}/api/rooms/${roomId}/feedback/aggregate`);
url.searchParams.set('from', from.toISOString());
url.searchParams.set('to', to.toISOString());

const response = await fetch(url, {
    method: 'GET',
    headers: {
        'x-user-id': userId,
        'x-display-name': 'KpiBot',
        'content-type': 'application/json',
    },
});

const payload = await response.json().catch(() => ({}));
if (!response.ok || !payload?.ok) {
    console.error(
        `[feedbackKpiBaseline] request failed status=${response.status} body=${JSON.stringify(payload).slice(0, 300)}`
    );
    process.exit(1);
}

const total = Number(payload.total || 0);
const byRating = payload.byRating || {};
const pertinent = Number(byRating.pertinent || 0);
const moyen = Number(byRating.moyen || 0);
const horsSujet = Number(byRating.hors_sujet || 0);
const byDay = Array.isArray(payload.byDay) ? payload.byDay : [];

console.log('\n[feedbackKpiBaseline] Feedback KPI baseline');
console.log(`Window: ${payload.from} -> ${payload.to} (${days}d)`);
console.log(`Total feedback events: ${total}`);
console.log(`Average daily volume: ${(total / days).toFixed(2)}`);
console.log(
    `Split: pertinent=${pertinent} (${percent(pertinent, total)}), moyen=${moyen} (${percent(moyen, total)}), hors_sujet=${horsSujet} (${percent(horsSujet, total)})`
);

if (byDay.length > 0) {
    console.log('\nDaily timeline:');
    for (const day of byDay) {
        const d = String(day.day || '').trim();
        const p = Number(day.pertinent || 0);
        const m = Number(day.moyen || 0);
        const h = Number(day.hors_sujet || 0);
        const dayTotal = p + m + h;
        console.log(`- ${d}: total=${dayTotal} | pertinent=${p}, moyen=${m}, hors_sujet=${h}`);
    }
}

console.log('\n[feedbackKpiBaseline] done');
