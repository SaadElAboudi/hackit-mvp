const MAX_SAMPLES = 400;
const ALERT_CONSECUTIVE_WINDOWS = 3;

const state = {
  endpoints: new Map(),
  wsFanout: {
    attempts: 0,
    success: 0,
    failed: 0,
    byHub: {
      rooms: { attempts: 0, success: 0, failed: 0 },
      threads: { attempts: 0, success: 0, failed: 0 },
    },
  },
  external: {
    gemini: { total: 0, timeout: 0, error: 0, success: 0, fallback: 0 },
    youtube: { total: 0, timeout: 0, error: 0, success: 0, fallback: 0 },
  },
  qualityEvents: [],
  ttvEvents: [],
  alertsHistory: [],
};

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

function clampRecent(arr, size = MAX_SAMPLES) {
  if (arr.length > size) arr.splice(0, arr.length - size);
}

export function observeHttp({ key, durationMs, statusCode }) {
  const bucket = state.endpoints.get(key) || { count: 0, errors5xx: 0, latenciesMs: [] };
  bucket.count += 1;
  if (statusCode >= 500) bucket.errors5xx += 1;
  bucket.latenciesMs.push(Math.max(0, Math.round(durationMs)));
  clampRecent(bucket.latenciesMs);
  state.endpoints.set(key, bucket);
}

export function observeExternal(provider, outcome) {
  const bucket = state.external[provider];
  if (!bucket) return;
  bucket.total += 1;
  if (outcome === 'success') bucket.success += 1;
  if (outcome === 'timeout') bucket.timeout += 1;
  if (outcome === 'error') bucket.error += 1;
  if (outcome === 'fallback') bucket.fallback += 1;
}

export function observeWsFanout({ hub = 'rooms', outcome }) {
  if (outcome !== 'success' && outcome !== 'failed') return;
  const bucket = state.wsFanout;
  bucket.attempts += 1;
  if (outcome === 'success') bucket.success += 1;
  if (outcome === 'failed') bucket.failed += 1;

  const hubKey = hub === 'threads' ? 'threads' : 'rooms';
  const hubBucket = bucket.byHub[hubKey];
  hubBucket.attempts += 1;
  if (outcome === 'success') hubBucket.success += 1;
  if (outcome === 'failed') hubBucket.failed += 1;
}

export function observeQualityEvent({ requestId, clicked = false, completed = false, rating = null }) {
  state.qualityEvents.push({ requestId, clicked: Boolean(clicked), completed: Boolean(completed), rating: Number.isFinite(rating) ? Number(rating) : null, at: Date.now() });
  clampRecent(state.qualityEvents);
}

export function observeTtvEvent({ requestId, ttvMs }) {
  state.ttvEvents.push({ requestId, ttvMs: Math.max(0, Math.round(ttvMs)), at: Date.now() });
  clampRecent(state.ttvEvents);
}

export function buildObservabilitySnapshot() {
  const endpoints = {};
  for (const [key, value] of state.endpoints.entries()) {
    const p50 = percentile(value.latenciesMs, 50);
    const p95 = percentile(value.latenciesMs, 95);
    endpoints[key] = {
      requests: value.count,
      errorRate5xx: value.count ? Number((value.errors5xx / value.count).toFixed(4)) : 0,
      latencyMs: { p50, p95 },
    };
  }

  const qualityCount = state.qualityEvents.length;
  const clicks = state.qualityEvents.filter((e) => e.clicked).length;
  const completions = state.qualityEvents.filter((e) => e.completed).length;
  const ratings = state.qualityEvents.map((e) => e.rating).filter((n) => Number.isFinite(n));
  const avgRating = ratings.length ? ratings.reduce((a, b) => a + b, 0) / ratings.length : null;
  const ttvValues = state.ttvEvents.map((e) => e.ttvMs);

  const quality = {
    events: qualityCount,
    ctr: qualityCount ? Number((clicks / qualityCount).toFixed(4)) : 0,
    completionRate: qualityCount ? Number((completions / qualityCount).toFixed(4)) : 0,
    averageRating: avgRating === null ? null : Number(avgRating.toFixed(3)),
    score: qualityCount
      ? Number((((clicks / qualityCount) * 0.4) + ((completions / qualityCount) * 0.4) + (((avgRating || 0) / 5) * 0.2)).toFixed(4))
      : 0,
  };

  return {
    endpoints,
    wsFanout: {
      attempts: state.wsFanout.attempts,
      success: state.wsFanout.success,
      failed: state.wsFanout.failed,
      failureRate: state.wsFanout.attempts
        ? Number((state.wsFanout.failed / state.wsFanout.attempts).toFixed(4))
        : 0,
      byHub: {
        rooms: {
          ...state.wsFanout.byHub.rooms,
          failureRate: state.wsFanout.byHub.rooms.attempts
            ? Number((state.wsFanout.byHub.rooms.failed / state.wsFanout.byHub.rooms.attempts).toFixed(4))
            : 0,
        },
        threads: {
          ...state.wsFanout.byHub.threads,
          failureRate: state.wsFanout.byHub.threads.attempts
            ? Number((state.wsFanout.byHub.threads.failed / state.wsFanout.byHub.threads.attempts).toFixed(4))
            : 0,
        },
      },
    },
    external: state.external,
    quality,
    timeToValueMs: {
      samples: ttvValues.length,
      p50: percentile(ttvValues, 50),
      p95: percentile(ttvValues, 95),
    },
  };
}

export function evaluateAlerts(snapshot) {
  const alerts = [];
  const search = snapshot.endpoints['POST /api/search'];
  if (search && search.errorRate5xx > 0.2) {
    alerts.push({ severity: 'high', code: 'search_5xx_spike', message: '5xx spike on /api/search' });
  }

  const gemini = snapshot.external.gemini;
  if (gemini.total >= 10 && (gemini.timeout / gemini.total) > 0.25) {
    alerts.push({ severity: 'high', code: 'gemini_timeout_spike', message: 'Gemini timeout ratio above threshold' });
  }

  if (snapshot.external.youtube.total >= 10 && (snapshot.external.youtube.error / snapshot.external.youtube.total) > 0.2) {
    alerts.push({ severity: 'medium', code: 'youtube_error_spike', message: 'YouTube error ratio above threshold' });
  }

  if (snapshot.wsFanout?.attempts >= 30 && snapshot.wsFanout.failureRate > 0.1) {
    alerts.push({ severity: 'high', code: 'ws_fanout_failures', message: 'WebSocket fanout failure ratio above threshold' });
  }

  state.alertsHistory.push({ at: Date.now(), count: alerts.length });
  clampRecent(state.alertsHistory, 200);

  const recentNonZero = state.alertsHistory.slice(-ALERT_CONSECUTIVE_WINDOWS).filter((w) => w.count > 0).length;
  if (recentNonZero >= ALERT_CONSECUTIVE_WINDOWS) {
    alerts.push({ severity: 'critical', code: 'persistent_alerts', message: 'Alerts active for multiple consecutive windows' });
  }

  return alerts;
}
