// Chapterization service: derives simple chapters from transcript segments
// MVP heuristic: group transcript segments into fixed-size buckets and assign titles.

import { getTranscript } from './transcript.js';

const CHAPTER_TTL_MS = Number(process.env.CHAPTER_TTL_MS || '600000'); // 10 minutes
const chapterCache = new Map(); // key -> { value, expiresAt }

function now() { return Date.now(); }

function getCache(key) {
    const entry = chapterCache.get(key);
    if (!entry) return null;
    if (entry.expiresAt < now()) { chapterCache.delete(key); return null; }
    return entry.value;
}

function setCache(key, value) {
    chapterCache.set(key, { value, expiresAt: now() + CHAPTER_TTL_MS });
}

function autoTitle(lines) {
    if (!lines.length) return 'Intro';
    const first = lines[0].text || '';
    if (first.length < 50) return first.replace(/^[\s:]+/, '').slice(0, 60) || 'Section';
    return (first.split(/[,.;]/)[0] || 'Section').slice(0, 60);
}

function extractDesiredChapters(hint) {
    try {
        const s = String(hint || '').toLowerCase();
        const m = s.match(/(?:en\s+)?(\d{1,3})\s*(?:chapitres?|chapters?)/i);
        if (m) {
            const n = parseInt(m[1], 10);
            if (Number.isFinite(n) && n > 0) return n;
        }
    } catch (_) { /* ignore */ }
    return null;
}

export async function getChapters(videoId, videoTitle, { desired } = {}) {
    const key = videoId;
    const cached = getCache(key);
    if (cached) {
        return { chapters: cached, cache: 'HIT' };
    }
    const { transcript } = await getTranscript(videoId, videoTitle);
    // Determine desired chapter count from explicit param or inferrable title text
    let desiredCount = null;
    if (Number.isInteger(desired) && desired > 0) desiredCount = desired;
    else desiredCount = extractDesiredChapters(videoTitle);

    // Heuristic: choose bucket size based on desired count (fallback to size=2)
    // bucketSize approx = ceil(transcriptLines / desiredCount)
    let bucketSize = 2;
    if (desiredCount && transcript.length > 0) {
        bucketSize = Math.max(1, Math.ceil(transcript.length / desiredCount));
    }
    const buckets = [];
    for (let i = 0; i < transcript.length; i += bucketSize) {
        buckets.push(transcript.slice(i, i + bucketSize));
    }
    const chapters = buckets.map((lines, idx) => ({
        index: idx,
        startSec: lines[0]?.startSec || idx * 60,
        title: autoTitle(lines) || `Section ${idx + 1}`,
    })).filter(Boolean);
    // Ensure ascending order only; do not enforce arbitrary min/max counts
    const normalized = chapters.sort((a, b) => a.startSec - b.startSec);
    setCache(key, normalized);
    return { chapters: normalized, cache: 'MISS' };
}

export function clearChapterCache() { chapterCache.clear(); }
export { extractDesiredChapters };
