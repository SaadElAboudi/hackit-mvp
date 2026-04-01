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
    if (process.env.NODE_ENV === 'test') {
        return heuristicTranscript(videoTitle);
    }
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
    const transcript = cached ? cached.value : await fetchRemoteTranscript(videoId, videoTitle);
    if (!transcript || transcript.length === 0) {
        return { transcript: [], cache: 'MISS', keyTakeaways: [], quiz: [], summary: '' };
    }
    if (!cached) setCacheEntry(videoId, transcript);

    // Fuzzy Gemini cache lookup
    let keyTakeaways = [];
    let quiz = [];
    let summary = '';
    try {
        const { getGeminiCacheFuzzy, setGeminiCache } = await import('../utils/persistence.js');
        const gemini = getGeminiCacheFuzzy(transcript);
        if (gemini && gemini.keyTakeaways && gemini.quiz) {
            keyTakeaways = gemini.keyTakeaways;
            quiz = gemini.quiz;
            summary = gemini.summary || '';
        } else {
            const { generateWithGemini } = await import('./gemini.js');
            // Single prompt for all info
            const prompt = `Given the following transcript, provide:\n1. A concise summary.\n2. Three key takeaways as a list.\n3. Two quiz questions and answers.\nTranscript:\n${transcript.map(t => t.text).join('\n')}`;
            const geminiText = await generateWithGemini(prompt, 256);
            // Parse Gemini response
            // Expect: Summary: ...\nKey Takeaways:\n- ...\n- ...\nQuiz:\nQ: ...\nA: ...
            const summaryMatch = geminiText.match(/Summary:(.*?)(Key Takeaways:|$)/is);
            summary = summaryMatch ? summaryMatch[1].trim() : '';
            const takeawaysMatch = geminiText.match(/Key Takeaways:(.*?)(Quiz:|$)/is);
            keyTakeaways = takeawaysMatch ? takeawaysMatch[1].split(/\n|-/).map(s => s.trim()).filter(Boolean) : [];
            const quizMatch = geminiText.match(/Quiz:(.*)$/is);
            quiz = quizMatch ? quizMatch[1].split(/Q:/).map(q => {
                const parts = q.split(/A:/);
                if (parts.length === 2) {
                    return { question: parts[0].trim(), answer: parts[1].trim() };
                }
                return null;
            }).filter(Boolean) : [];
            setGeminiCache(videoId, { summary, keyTakeaways, quiz, transcript });
        }
    } catch (e) {
        keyTakeaways = [];
        quiz = [];
        summary = '';
    }
    return { transcript, cache: cached ? 'HIT' : 'MISS', keyTakeaways, quiz, summary };
}

export function clearTranscriptCache() {
    cache.clear();
}
