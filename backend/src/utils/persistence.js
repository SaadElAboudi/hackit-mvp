// In-memory Gemini transcript cache (per server session).
// Replaces the old SQLite layer. For cross-restart persistence, save to MongoDB.

const _geminiCache = new Map();

/**
 * Store Gemini analysis (summary, keyTakeaways, quiz) keyed by videoId.
 */
export function setGeminiCache(videoId, data) {
    if (videoId) _geminiCache.set(String(videoId), data);
}

/**
 * Retrieve cached Gemini analysis by videoId. Returns null on miss.
 */
export function getGeminiCache(videoId) {
    return _geminiCache.get(String(videoId)) ?? null;
}

/**
 * Legacy fuzzy lookup by transcript content (not implemented — returns null).
 * Kept for API compatibility with transcript.js.
 */
export function getGeminiCacheFuzzy(_transcript) {
    return null;
}
