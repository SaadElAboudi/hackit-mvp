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

export async function getChapters(videoId, videoTitle) {
    const key = videoId;
    const cached = getCache(key);
    if (cached) {
        return { chapters: cached, cache: 'HIT' };
    }
    const { transcript } = await getTranscript(videoId, videoTitle);
    // Heuristic bucket size: 2 transcript lines per chapter
    const buckets = [];
    for (let i = 0; i < transcript.length; i += 2) {
        buckets.push(transcript.slice(i, i + 2));
    }
    const chapters = buckets.map((lines, idx) => ({
        index: idx,
        startSec: lines[0]?.startSec || idx * 60,
        title: autoTitle(lines) || `Section ${idx + 1}`,
    })).filter(Boolean);
    // Ensure ascending order & minimum amount (fallback to generic if transcript short)
    const normalized = chapters.sort((a, b) => a.startSec - b.startSec);
    if (normalized.length < 5) {
        // Expand with synthetic chapters if needed for UI richness
        const baseStart = normalized[0]?.startSec || 0;
        while (normalized.length < 5) {
            const s = baseStart + normalized.length * 45;
            normalized.push({ index: normalized.length, startSec: s, title: `Section ${normalized.length + 1}` });
        }
    }
    setCache(key, normalized);
    return { chapters: normalized, cache: 'MISS' };
}

export function clearChapterCache() { chapterCache.clear(); }
