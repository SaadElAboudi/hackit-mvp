#!/usr/bin/env node

export function normalizeDecisionPackAggregate(payload, fallbackDays = 14) {
  const aggregate = payload?.aggregate || {};
  const events = aggregate?.events || {};
  const viewed = Number(events.viewed || 0);
  const shared = Number(events.shared || 0);
  const failed = Number(events.share_failed || 0);
  const conversion = viewed > 0 ? Number(((shared / viewed) * 100).toFixed(1)) : 0;
  return {
    sinceDays: Number(aggregate.sinceDays || fallbackDays),
    since: aggregate.since || 'n/a',
    viewed,
    shared,
    failed,
    conversion,
  };
}

export function formatDecisionPackBaselineLines(stats) {
  return [
    'Decision Pack KPI Baseline',
    '==========================',
    `sinceDays   : ${stats.sinceDays}`,
    `since       : ${stats.since}`,
    `viewed      : ${stats.viewed}`,
    `shared      : ${stats.shared}`,
    `share_failed: ${stats.failed}`,
    `conversion% : ${stats.conversion.toFixed(1)}`,
  ];
}

export async function runDecisionPackKpiBaseline({
  apiBase,
  roomId,
  userId,
  days,
  fetchFn = fetch,
  write = console.log,
} = {}) {
  const normalizedBase = String(apiBase || 'http://localhost:5001').replace(/\/$/, '');
  const normalizedRoomId = String(roomId || '').trim();
  const normalizedUserId = String(userId || 'ops_kpi_bot').trim();
  const normalizedDays = Math.max(1, Math.min(90, Number.parseInt(String(days || '14'), 10) || 14));

  if (!normalizedRoomId) {
    throw new Error('Missing ROOM_ID env var');
  }

  const url = `${normalizedBase}/api/rooms/${encodeURIComponent(normalizedRoomId)}/decision-pack/aggregate?sinceDays=${normalizedDays}`;
  const res = await fetchFn(url, { headers: { 'x-user-id': normalizedUserId } });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`Request failed: ${res.status} ${JSON.stringify(json)}`);
  }

  const stats = normalizeDecisionPackAggregate(json, normalizedDays);
  formatDecisionPackBaselineLines(stats).forEach((line) => write(line));
  return stats;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runDecisionPackKpiBaseline({
    apiBase: process.env.API_BASE,
    roomId: process.env.ROOM_ID,
    userId: process.env.X_USER_ID,
    days: process.env.DAYS,
  }).catch((err) => {
    console.error(err?.message || err);
    process.exit(1);
  });
}
