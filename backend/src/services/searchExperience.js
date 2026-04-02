const DEFAULT_CACHE_TTL_MS = Number(process.env.SEARCH_CACHE_TTL_MS || 5 * 60 * 1000);
const DEFAULT_MAX_ENTRIES = Number(process.env.SEARCH_CACHE_MAX_ENTRIES || 200);

function normalizeWords(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .map((w) => w.trim())
    .filter((w) => w.length >= 4);
}

function sanitizeForKey(value) {
  return String(value || '').trim().toLowerCase();
}

export function buildSearchCacheKey({ query, summaryLength, useGemini, maxResults, pageToken, tone, expertiseLevel }) {
  return [
    sanitizeForKey(query),
    sanitizeForKey(summaryLength || 'standard'),
    useGemini === false ? 'nogem' : 'gem:auto',
    Number.isFinite(maxResults) ? String(maxResults) : 'mr:default',
    sanitizeForKey(pageToken || ''),
    sanitizeForKey(tone || 'practical'),
    sanitizeForKey(expertiseLevel || 'intermediate'),
  ].join('|');
}

export function createSearchCache({ ttlMs = DEFAULT_CACHE_TTL_MS, maxEntries = DEFAULT_MAX_ENTRIES } = {}) {
  const store = new Map();

  return {
    get(key) {
      const now = Date.now();
      const entry = store.get(key);
      if (!entry) return null;
      if (entry.expiresAt <= now) {
        store.delete(key);
        return null;
      }
      return entry.value;
    },
    set(key, value) {
      const now = Date.now();
      if (store.size >= maxEntries) {
        const firstKey = store.keys().next().value;
        if (firstKey) store.delete(firstKey);
      }
      store.set(key, { value, expiresAt: now + ttlMs });
    },
    clear() {
      store.clear();
    },
  };
}

export function buildRelatedQueries({ query, title, alternatives = [], max = 5 }) {
  const seeds = new Set([...normalizeWords(query), ...normalizeWords(title)]);
  alternatives.forEach((item) => normalizeWords(item?.title).forEach((w) => seeds.add(w)));

  const suggestions = [];
  for (const word of seeds) {
    suggestions.push(`how to ${word}`);
    suggestions.push(`${word} tutorial`);
    if (suggestions.length >= max * 2) break;
  }

  const deduped = [];
  const seen = new Set([sanitizeForKey(query)]);
  for (const candidate of suggestions) {
    const cleaned = sanitizeForKey(candidate);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    deduped.push(candidate);
    if (deduped.length >= max) break;
  }
  return deduped;
}
