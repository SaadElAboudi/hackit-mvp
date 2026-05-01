import test from 'node:test';
import assert from 'node:assert/strict';

import {
  formatDecisionPackBaselineLines,
  normalizeDecisionPackAggregate,
  runDecisionPackKpiBaseline,
} from '../scripts/decisionPackKpiBaseline.js';

test('normalizeDecisionPackAggregate computes conversion safely', () => {
  const stats = normalizeDecisionPackAggregate({
    aggregate: {
      sinceDays: 14,
      since: '2026-04-01T00:00:00.000Z',
      events: { viewed: 10, shared: 3, share_failed: 1 },
    },
  });

  assert.equal(stats.viewed, 10);
  assert.equal(stats.shared, 3);
  assert.equal(stats.failed, 1);
  assert.equal(stats.conversion, 30.0);
});

test('formatDecisionPackBaselineLines renders expected lines', () => {
  const lines = formatDecisionPackBaselineLines({
    sinceDays: 7,
    since: 'n/a',
    viewed: 0,
    shared: 0,
    failed: 0,
    conversion: 0,
  });

  assert.equal(lines[0], 'Decision Pack KPI Baseline');
  assert.match(lines[7], /conversion%\s+: 0.0/);
});

test('runDecisionPackKpiBaseline fetches and returns normalized stats', async () => {
  const writes = [];
  const fakeFetch = async () => ({
    ok: true,
    status: 200,
    async json() {
      return {
        aggregate: {
          sinceDays: 30,
          since: '2026-03-31T00:00:00.000Z',
          events: { viewed: 20, shared: 5, share_failed: 2 },
        },
      };
    },
  });

  const stats = await runDecisionPackKpiBaseline({
    apiBase: 'http://localhost:5001',
    roomId: 'room_1',
    userId: 'u1',
    days: 30,
    fetchFn: fakeFetch,
    write: (line) => writes.push(line),
  });

  assert.equal(stats.conversion, 25.0);
  assert.ok(writes.some((line) => line.includes('shared      : 5')));
});
