// Simple transcript fetch & in-memory cache
// For MVP we attempt to approximate a transcript by splitting the video title/descriptions heuristically
// Later replace with real YouTube captions provider.

import axios from 'axios';

const TTL_MS = Number(process.env.TRANSCRIPT_TTL_MS || '600000'); // 10 min default
const cache = new Map(); // key -> { value, expiresAt }

export function _now() { return Date.now(); }

export function getCacheEntry(videoId) {
    const entry = cache.get(videoId);
    if (!entry) return null;
    if (entry.expiresAt < _now()) {
        cache.delete(videoId);
        return null;
    }
    return entry;
}

export function setCacheEntry(videoId, transcript) {
    cache.set(videoId, { value: transcript, expiresAt: _now() + TTL_MS });
}

// Heuristic placeholder: generate pseudo transcript lines
function heuristicTranscript(videoTitle) {
    const base = [
        `Introduction to: ${videoTitle}`,
        'Listing required tools and materials.',
        'Demonstration of the core procedure step-by-step.',
        'Troubleshooting common mistakes.',
        'Final result review and cleanup.'
    ];
    // Return array of { startSec, text }
    return base.map((text, i) => ({ startSec: i * 30, text }));
}

// Fetch real transcript placeholder (future: integrate provider)
async function fetchRemoteTranscript(videoId, videoTitle) {
    // If we had an API key / caption endpoint we'd call it here.
    // Attempt minimal HEAD request to YouTube watch page to ensure video exists.
    try {
        await axios.get(`https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`, { timeout: 4000 });
    } catch (_) {
        // Ignore; existence check not critical for heuristic fallback
    }
    return heuristicTranscript(videoTitle);
}

export async function getTranscript(videoId, videoTitle) {
    const cached = getCacheEntry(videoId);
    if (cached) {
        return { transcript: cached.value, cache: 'HIT' };
    }
    const transcript = await fetchRemoteTranscript(videoId, videoTitle);
    if (!transcript || transcript.length === 0) {
        return { transcript: [], cache: 'MISS' };
    }
    setCacheEntry(videoId, transcript);
    return { transcript, cache: 'MISS' };
}

export function clearTranscriptCache() {
    cache.clear();
}
