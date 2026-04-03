// import { deleteLesson } from "./utils/persistence.js";
// Deprecated persistence import removed. Use Mongoose models instead.
import { randomBytes } from 'crypto';
import { pathToFileURL } from 'url';

import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import mongoose from 'mongoose';
import morgan from 'morgan';

import { getFeatureFlags } from './config/featureFlags.js';
import lessonsRouter from './routes/lessons.js';
import { validateFeedbackPayload, validateSearchPayload, validateTtvPayload } from './middleware/validation.js';
import { getChapters, extractDesiredChapters } from './services/chapters.js';
import { getTranscript } from './services/transcript.js';
import { searchYouTube as originalSearchYouTube } from './services/youtube.js';
import { buildObservabilitySnapshot, evaluateAlerts, observeExternal, observeHttp, observeQualityEvent, observeTtvEvent } from './utils/observability.js';
import { userIdMiddleware } from './utils/userIdMiddleware.js';

// Avoid importing yt-search at module load on Node<20 to prevent undici File init crash
const dynamicImport = (moduleName) => Function('m', 'return import(m)')(moduleName);

dotenv.config({ quiet: true });

const featureFlags = getFeatureFlags();



const app = express();
// CORS middleware at the very top
// Restrict CORS in production, allow all in dev
app.use(cors({
  origin: process.env.NODE_ENV === 'production'
    ? [process.env.FRONTEND_ORIGIN || 'https://yourfrontend.com']
    : true,
  credentials: true
}));
app.use(express.json({ limit: process.env.JSON_BODY_LIMIT || '1mb' }));
app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on('finish', () => {
    const resolvedPath = req.route?.path ? `${req.baseUrl || ''}${req.route.path}` : req.path;
    const routeKey = `${req.method} ${resolvedPath}`;
    observeHttp({ key: routeKey, durationMs: Date.now() - startedAt, statusCode: res.statusCode });
  });
  next();
});
// Rate limiter with Redis support (distributed) and in-memory fallback
const rateLimit = {};
const REDIS_URL = process.env.REDIS_URL;
let redisClient = null;
let redisReady = false;

async function initRedisRateLimiter() {
  if (!REDIS_URL || process.env.NODE_ENV === 'test' || redisReady || redisClient) return;
  try {
    const { createClient } = await dynamicImport('redis');
    redisClient = createClient({ url: REDIS_URL });
    redisClient.on('error', (err) => {
      redisReady = false;
      console.warn('Redis rate limiter unavailable:', err?.message || err);
    });
    await redisClient.connect();
    redisReady = true;
  } catch (err) {
    redisClient = null;
    redisReady = false;
    if (process.env.NODE_ENV !== 'test') {
      console.warn('Redis rate limiter disabled, fallback to memory:', err?.message || err);
    }
  }
}

await initRedisRateLimiter();

async function simpleRateLimit(key, maxPerMinute = 30) {
  if (redisReady && redisClient) {
    try {
      const bucket = Math.floor(Date.now() / 60000);
      const redisKey = `ratelimit:${key}:${bucket}`;
      const current = await redisClient.incr(redisKey);
      if (current === 1) {
        await redisClient.expire(redisKey, 60);
      }
      return current <= maxPerMinute;
    } catch (err) {
      redisReady = false;
      console.warn('Redis rate limiting failed, using memory fallback:', err?.message || err);
    }
  }

  const now = Date.now();
  if (!rateLimit[key]) rateLimit[key] = [];
  rateLimit[key] = rateLimit[key].filter((ts) => now - ts < 60000);
  if (rateLimit[key].length >= maxPerMinute) return false;
  rateLimit[key].push(now);
  return true;
}
// Enable concise logging in all non-test environments
if (process.env.NODE_ENV && process.env.NODE_ENV !== "test") {
  app.use(morgan("dev"));
}
app.get('/api/me', (req, res) => {
  return res.json({
    ok: true,
    auth: 'disabled',
    user: {
      id: req.headers['x-user-id'] || 'anonymous',
      isAnonymous: true,
    },
  });
});

function buildGuestAuthSuccessUrl(req) {
  const frontendOrigin = (process.env.FRONTEND_ORIGIN || '').trim().replace(/\/$/, '');
  const fallbackOrigin = `${req.protocol}://${req.get('host')}`;
  const base = frontendOrigin || fallbackOrigin;
  const userId = randomBytes(8).toString('hex');
  return `${base}/auth-success?userId=${userId}&mode=guest`;
}

// Compatibility endpoints: legacy login buttons may still call Google OAuth routes.
// The app currently runs in no-auth mode, so we redirect to guest success instead.
app.get('/auth/google/status', (_req, res) => {
  return res.json({
    enabled: false,
    mode: 'guest-only',
    reason: 'Authentication is disabled in this deployment',
  });
});

app.get('/auth/google', (req, res) => {
  return res.redirect(302, buildGuestAuthSuccessUrl(req));
});

app.get('/auth/google/callback', (req, res) => {
  return res.redirect(302, buildGuestAuthSuccessUrl(req));
});

app.get('/api/feature-flags', (_req, res) => {
  return res.json({ ok: true, flags: featureFlags });
});

const USE_GEMINI_ENV = (process.env.USE_GEMINI || "false") === "true";
const USE_GEMINI_REFORMULATION = (process.env.USE_GEMINI_REFORMULATION || "false") === "true";
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "models/gemini-2.0-flash-lite";
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "4000");
let GEMINI_OPERATIONAL = true; // set to false after first hard failure
// Circuit breaker state for Gemini
const FAILURE_WINDOW_MS = Number(process.env.GEMINI_FAILURE_WINDOW_MS || '120000'); // 2 minutes
const BREAKER_OPEN_MS = Number(process.env.GEMINI_BREAKER_OPEN_MS || '300000'); // 5 minutes
let GEMINI_FAILURE_TIMESTAMPS = []; // array of ms since epoch
let GEMINI_BREAKER_UNTIL = 0; // timestamp ms when breaker closes
const START_TIME = Date.now();
const APP_VERSION = process.env.APP_VERSION || process.env.npm_package_version || '1.0.0';
const MAX_QUERY_LEN = Number(process.env.MAX_QUERY_LEN || 500);
const MAX_STREAM_QUERY_LEN = Number(process.env.MAX_STREAM_QUERY_LEN || 500);

function makeMockResponse() {
  return {
    title: "Mock: Déboucher un évier",
    steps: [
      "Verse 1/2 tasse de bicarbonate dans la canalisation.",
      "Ajoute 1 tasse de vinaigre blanc.",
      "Laisse agir 10 minutes.",
      "Verse de l’eau bouillante.",
    ],
    videoUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    source: "mock"
  };
}

function heuristicSummary({ desiredSteps } = {}) {
  // Very simple local summary when Gemini is disabled/unavailable
  const base = [
    "Ouvre la vidéo et lis la description.",
    "Prépare le matériel nécessaire avant de commencer.",
    "Suis les étapes démontrées, étape par étape.",
    "Mets en pause et reviens en arrière si besoin.",
    "Vérifie le résultat et nettoie/range le matériel.",
  ];
  // If the user asked for a specific number of steps, try to match it by trimming or padding
  if (Number.isInteger(desiredSteps) && desiredSteps > 0) {
    if (desiredSteps <= base.length) {
      return base.slice(0, desiredSteps).join("\n");
    }
    const extras = [
      "Révise le processus et prends des notes.",
      "Adapte les étapes à ton contexte.",
      "Teste le résultat et corrige si nécessaire.",
      "Partage l’astuce ou sauvegarde-la pour plus tard.",
    ];
    const out = base.slice();
    let i = 0;
    while (out.length < desiredSteps) {
      out.push(extras[i % extras.length]);
      i++;
    }
    return out.join("\n");
  }
  return base.join("\n");
}

function getSummaryConfig(summaryLength = 'standard') {
  switch (summaryLength) {
    case 'tldr':
      return { stepsTarget: 3 };
    case 'deep':
      return { stepsTarget: 8 };
    default:
      return { stepsTarget: 5 };
  }
}

function detectDeliveryModeFromQuery(query) {
  const q = String(query || '').toLowerCase();
  if (q.includes('mode cadrer')) return 'cadrer';
  if (q.includes('mode produire')) return 'produire';
  if (q.includes('mode communiquer')) return 'communiquer';
  if (q.includes('mode audit')) return 'audit';
  return 'produire';
}

function buildDeliveryPlan({ mode, query, title, steps }) {
  const items = Array.isArray(steps) ? steps.filter(Boolean).map((s) => String(s).trim()).filter(Boolean) : [];
  const pick = (from, count) => items.slice(from, from + count);

  const fallbackObjective = `Transformer la demande en livrable concret: ${String(query || '').slice(0, 120)}`;
  const objective = pick(0, 1);
  const scope = pick(1, 2);
  const risks = pick(3, 2);
  const nextActions = pick(5, 3);

  let clientMessage = [];
  if (mode === 'communiquer') {
    clientMessage = items.length ? items : [
      `Bonjour, voici l'avancement sur "${title}".`,
      "Les prochaines actions sont planifiees et je vous propose un point de validation rapide.",
      "Pouvez-vous confirmer la priorite et la deadline cible ?",
    ];
  } else {
    clientMessage = [
      `Bonjour, voici le plan de livraison propose pour "${title}".`,
      "Je partage les priorites, risques et prochaines actions pour alignement.",
      "Merci de valider le perimetre et la priorite des taches.",
    ];
  }

  return {
    mode,
    objective: objective.length ? objective : [fallbackObjective],
    scope: scope.length ? scope : ["Perimetre initial a valider avec le client"],
    risks: risks.length ? risks : ["Risque de derive du perimetre"],
    nextActions: nextActions.length ? nextActions : items.slice(0, Math.min(3, items.length)),
    clientMessage,
  };
}

function annotateSource(source, mode = 'real') {
  return {
    source,
    resultMode: mode,
    badges: [mode.toUpperCase()],
  };
}

function extractDesiredSteps(text) {
  try {
    const s = String(text || '').toLowerCase();
    // Patterns like: "en 7 étapes", "7 étapes", "7 etapes", "7 steps", "en 3 points"
    const m = s.match(/(?:en\s+)?(\d{1,3})\s*(?:étapes?|etapes?|steps?|points?)/i);
    if (m) {
      const n = parseInt(m[1], 10);
      if (Number.isFinite(n) && n > 0) return n;
    }
  } catch (_) { /* ignore */ }
  return null;
}

function extractYouTubeVideoId(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes('youtu.be')) {
      return u.pathname.replace('/', '').split('?')[0];
    }
    if (u.searchParams.has('v')) return u.searchParams.get('v');
    // Fallback for embed URLs
    const parts = u.pathname.split('/');
    const idx = parts.indexOf('embed');
    if (idx !== -1 && parts[idx + 1]) return parts[idx + 1];
  } catch (_) { /* ignore */ }
  return null;
}

function normalizeQueryInput(raw, maxLen = MAX_QUERY_LEN) {
  const query = String(raw || '').trim();
  if (!query) return { ok: false, status: 400, error: 'query is required' };
  if (query.length > maxLen) {
    return { ok: false, status: 413, error: `query is too long (max ${maxLen} chars)` };
  }
  return { ok: true, value: query };
}

function withTimestamp(url, startSec) {
  try {
    const u = new URL(url);
    // Add t=STARTS seconds as query parameter; keep existing params
    u.searchParams.set('t', String(Math.max(0, Math.floor(startSec))));
    return u.toString();
  } catch (_) {
    return url;
  }
}

async function buildCitations({ videoId, videoTitle, videoUrl, max = 3 }) {
  try {
    const { transcript } = await getTranscript(videoId, videoTitle);
    const items = (transcript || []).slice(0, max);
    return items.map((seg) => ({
      url: withTimestamp(videoUrl, seg.startSec || 0),
      startSec: Math.max(0, Math.floor(seg.startSec || 0)),
      endSec: Math.max(0, Math.floor((seg.startSec || 0) + 25)),
      quote: String(seg.text || '').slice(0, 140)
    }));
  } catch (_) {
    return [];
  }
}

// Allow overriding YouTube search implementation in tests without affecting production import binding.
let searchYouTube = originalSearchYouTube;
export function setSearchYouTube(fn) {
  if (typeof fn === 'function') {
    searchYouTube = fn;
  } else {
    throw new Error('setSearchYouTube expects a function');
  }
}

async function generateWithGemini(prompt, maxOutputTokens = 256, options = {}) {
  const currentModel = options.model || GEMINI_MODEL;
  const allowModelFallback = options.allowModelFallback !== false;
  if (!GEMINI_API_KEY) throw new Error("GEMINI_API_KEY missing");
  // Use v1 generateContent endpoint for modern models; fall back to legacy if needed.
  const isLegacy = /bison|text-bison/i.test(currentModel);
  const baseUrl = isLegacy
    ? `https://generativelanguage.googleapis.com/v1beta2/${currentModel}:generateText?key=${GEMINI_API_KEY}`
    : `https://generativelanguage.googleapis.com/v1/${currentModel}:generateContent?key=${GEMINI_API_KEY}`;


  const body = isLegacy
    ? { prompt: { text: prompt }, maxOutputTokens, temperature: 0.2 }
    : {
      contents: [
        { role: "user", parts: [{ text: prompt }] }
      ],
      generationConfig: { maxOutputTokens, temperature: 0.2 },
      safetySettings: [
        { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
        { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
        { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
        { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
      ]
    };

  try {
    const resp = await axios.post(baseUrl, body, { headers: { "Content-Type": "application/json" }, timeout: GEMINI_TIMEOUT_MS });
    if (isLegacy) {
      const txt = resp.data?.candidates?.[0]?.output;
      if (!txt) throw new Error("Empty Gemini legacy output");
      return txt.trim();
    } else {
      const block = resp.data?.promptFeedback?.blockReason;
      if (block && block !== "BLOCK_NONE") {
        throw new Error(`Gemini blocked content: ${block}`);
      }
      const parts = resp.data?.candidates?.[0]?.content?.parts || [];
      let txt = parts.map(p => p?.text).filter(Boolean).join("\n").trim();
      if (!txt) txt = (resp.data?.candidates?.[0]?.text || "").trim();
      if (!txt) txt = (resp.data?.candidates?.[0]?.output || "").trim();
      if (!txt) throw new Error("Empty Gemini response");
      // success resets failure counters and closes breaker
      GEMINI_OPERATIONAL = true;
      GEMINI_FAILURE_TIMESTAMPS = [];
      GEMINI_BREAKER_UNTIL = 0;
      observeExternal('gemini', 'success');
      return txt;
    }
  } catch (error) {
    const status = error?.response?.status;
    const message = error?.response?.data?.error?.message || error.message;
    // On timeout or network abort, throw a concise timeout error
    if (error?.code === 'ECONNABORTED' || /timeout/i.test(message || '')) {
      GEMINI_OPERATIONAL = false;
      // record failure and possibly open breaker
      const now = Date.now();
      GEMINI_FAILURE_TIMESTAMPS = GEMINI_FAILURE_TIMESTAMPS.filter(ts => now - ts <= FAILURE_WINDOW_MS);
      GEMINI_FAILURE_TIMESTAMPS.push(now);
      if (GEMINI_FAILURE_TIMESTAMPS.length >= 3) {
        GEMINI_BREAKER_UNTIL = Math.max(GEMINI_BREAKER_UNTIL, now + BREAKER_OPEN_MS);
      }
      observeExternal('gemini', 'timeout');
      throw new Error(`Gemini timeout after ${GEMINI_TIMEOUT_MS}ms`);
    }
    // If NOT_FOUND: try a known accessible lite model explicitly once
    if (
      status === 404 &&
      allowModelFallback &&
      currentModel !== 'models/gemini-2.0-flash-lite' &&
      currentModel !== 'models/gemini-2.0-flash-lite-001'
    ) {
      return await generateWithGemini(prompt, maxOutputTokens, {
        model: 'models/gemini-2.0-flash-lite',
        allowModelFallback: false,
      });
    }
    observeExternal('gemini', 'error');
    if (status === 404) {
      // mark non-operational and record failure
      GEMINI_OPERATIONAL = false;
      const now = Date.now();
      GEMINI_FAILURE_TIMESTAMPS = GEMINI_FAILURE_TIMESTAMPS.filter(ts => now - ts <= FAILURE_WINDOW_MS);
      GEMINI_FAILURE_TIMESTAMPS.push(now);
      if (GEMINI_FAILURE_TIMESTAMPS.length >= 3) {
        GEMINI_BREAKER_UNTIL = Math.max(GEMINI_BREAKER_UNTIL, now + BREAKER_OPEN_MS);
      }
    }
    throw new Error(message || "Gemini generation failed");
  }
}

app.get("/health", (_req, res) => {
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  const mock = (process.env.MOCK_MODE || mockDefault) === "true";
  res.json({
    ok: true,
    mode: mock ? 'MOCK' : 'REAL',
    mock,
    uptimeSeconds: Math.round((Date.now() - START_TIME) / 1000),
    version: APP_VERSION,
    projectId: process.env.PROJECT_ID || null,
    youtubeApi: Boolean(process.env.YT_API_KEY),
    gemini: {
      enabled: USE_GEMINI_ENV,
      model: GEMINI_MODEL,
      hasKey: Boolean(GEMINI_API_KEY),
      timeoutMs: GEMINI_TIMEOUT_MS,
      operational: GEMINI_OPERATIONAL,
      breakerActive: Date.now() < GEMINI_BREAKER_UNTIL,
      retryAt: GEMINI_BREAKER_UNTIL || null,
    }
  });
});

// Extended health with dynamic Gemini state
app.get("/health/extended", (_req, res) => {
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  const mock = (process.env.MOCK_MODE || mockDefault) === "true";
  res.json({
    ok: true,
    mode: mock ? 'MOCK' : 'REAL',
    mock,
    uptimeSeconds: Math.round((Date.now() - START_TIME) / 1000),
    version: APP_VERSION,
    timestamp: new Date().toISOString(),
    projectId: process.env.PROJECT_ID || null,
    youtube: { hasKey: Boolean(process.env.YT_API_KEY) },
    gemini: {
      configured: (process.env.USE_GEMINI || "false") === "true",
      hasKey: Boolean(GEMINI_API_KEY),
      model: GEMINI_MODEL,
      timeoutMs: GEMINI_TIMEOUT_MS,
      operational: GEMINI_OPERATIONAL,
      breakerActive: Date.now() < GEMINI_BREAKER_UNTIL,
      retryAt: GEMINI_BREAKER_UNTIL || null,
    }
  });
});
app.get("/health/observability", (_req, res) => {
  const snapshot = buildObservabilitySnapshot();
  const alerts = evaluateAlerts(snapshot);
  res.json({ ok: true, snapshot, alerts });
});

app.post('/api/search/feedback', async (req, res) => {
  let payload;
  try {
    payload = validateFeedbackPayload(req.body || {});
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload' });
  }
  const { requestId, clicked, completed, rating } = payload;
  observeQualityEvent({ requestId, clicked, completed, rating });
  return res.json({ ok: true });
});

app.post('/api/analytics/ttv', async (req, res) => {
  let payload;
  try {
    payload = validateTtvPayload(req.body || {});
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload' });
  }
  const { requestId, ttvMs } = payload;
  observeTtvEvent({ requestId, ttvMs });
  return res.json({ ok: true });
});

app.get('/api/recommendations', userIdMiddleware, async (req, res) => {
  try {
    const Lesson = (await import('./models/lesson.js')).default;
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized user context' });
    const history = await Lesson.find({ userId }).sort({ lastViewedAt: -1, updatedAt: -1 }).limit(20).lean();
    const seedWords = new Set();
    history.forEach((l) => String(l.title || '').toLowerCase().split(/\W+/).filter((w) => w.length > 3).forEach((w) => seedWords.add(w)));
    const candidates = await Lesson.find({ userId: { $ne: userId } }).sort({ favorite: -1, views: -1, createdAt: -1 }).limit(100).lean();
    const scored = candidates.map((l) => {
      const words = String(l.title || '').toLowerCase().split(/\W+/);
      const overlap = words.filter((w) => seedWords.has(w)).length;
      const score = overlap * 3 + (l.favorite ? 2 : 0) + Math.min(5, Math.floor((l.views || 0) / 10));
      return { ...l, score };
    }).sort((a, b) => b.score - a.score).slice(0, 10);
    return res.json({ items: scored });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to build recommendations', detail: e?.message || 'Unknown error' });
  }
});


app.post("/api/search", async (req, res) => {
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!(await simpleRateLimit(`search:${ip}`, 20))) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  let query;
  let summaryLength;
  let useGeminiOverride;
  try {
    ({ query, summaryLength, useGemini: useGeminiOverride } = validateSearchPayload(req.body || {}));
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload' });
  }
  const summaryConfig = getSummaryConfig(featureFlags.multiLengthSummary ? summaryLength : 'standard');
  const deliveryMode = detectDeliveryModeFromQuery(query);
  const requestId = randomBytes(8).toString('hex');

  // Dev mock mode: quick responses without keys. Default mock false if YT_API_KEY exists.
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    const mock = makeMockResponse();
    const steps = Array.isArray(mock.steps) ? mock.steps : [];
    const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
    const citations = await buildCitations({ videoId: vid, videoTitle: mock.title, videoUrl: mock.videoUrl, max: 3 });
    const desiredChapters = extractDesiredChapters(query);
    const chapters = (await getChapters(vid, mock.title, { desired: desiredChapters })).chapters;
    const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: mock.title, steps });
    return res.json({
      ...mock,
      steps,
      ...annotateSource(mock.source, 'mock'),
      citations,
      chapters,
      deliveryPlan,
      requestId,
      summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
    });
  }

  try {
    let searchTerm = query;
    const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
    const useGemini = USE_GEMINI_ENV && !breakerActive && (useGeminiOverride !== false);
    let reformulationTimedOut = false;
    if (useGemini && USE_GEMINI_REFORMULATION) {
      const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
      try {
        let reform = await generateWithGemini(reformPrompt, 32);
        reform = String(reform)
          .split(/\r?\n/)[0]
          .replace(/^[-*•\s>"]+/, "")
          .replace(/["`]+/g, "")
          .trim();
        if (!reform || reform.length > 80) {
          searchTerm = query;
        } else {
          searchTerm = reform;
        }
      } catch (e) {
        console.warn("Gemini reformulation failed:", e.message);
        if (/timeout/i.test(e.message || "")) {
          reformulationTimedOut = true;
        }
        searchTerm = query;
      }
    }

    let videoTitle, videoUrl, source, videoId;
    try {
      const video = await searchYouTube(searchTerm);
      videoTitle = video.title;
      videoUrl = video.url;
      source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
      observeExternal('youtube', 'success');
    } catch (videoErr) {
      console.warn("Video search failed:", videoErr.message);
      if (videoErr.code === "YOUTUBE_NO_RESULTS" && searchTerm !== query) {
        console.log("Retrying YouTube search with original query after no results for reformulated term.");
        try {
          const retryVideo = await searchYouTube(query);
          videoTitle = retryVideo.title;
          videoUrl = retryVideo.url;
          videoId = retryVideo.videoId || extractYouTubeVideoId(retryVideo.url);
          source = retryVideo.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
          console.log("Recovered video via original query.");
        } catch (retryErr) {
          console.warn("Retry with original query also failed:", retryErr.message);
          if ((process.env.ALLOW_FALLBACK || "true") === "true") {
            observeExternal('youtube', 'fallback');
            return res.json({ ...makeMockResponse(), source: "mock-fallback" });
          }
          throw retryErr;
        }
      } else {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          observeExternal('youtube', 'fallback');
          return res.json({ ...makeMockResponse(), source: "mock-fallback" });
        }
        throw videoErr;
      }
    }

    let summaryText = "";
    const attemptGeminiSummary = useGemini && !reformulationTimedOut;
    const desiredSteps = extractDesiredSteps(query) || summaryConfig.stepsTarget;
    if (attemptGeminiSummary) {
      // Récupère le transcript YouTube
      let transcriptText = "";
      try {
        const { transcript } = await getTranscript(videoId, videoTitle);
        transcriptText = Array.isArray(transcript) ? transcript.map(seg => seg.text).join(" ") : "";
      } catch (e) {
        console.warn("Transcript fetch failed, fallback to title only:", e.message);
      }
      // Utilise le transcript comme input Gemini si disponible
      const summaryPrompt = transcriptText
        ? (desiredSteps
          ? `Résume ce texte en ${desiredSteps} étapes claires:\n${transcriptText}`
          : `Résume ce texte en étapes claires:\n${transcriptText}`)
        : (desiredSteps
          ? `Résume cette vidéo YouTube en ${desiredSteps} étapes claires: ${videoTitle}`
          : `Résume cette vidéo YouTube en étapes claires: ${videoTitle}`);
      try {
        summaryText = await generateWithGemini(summaryPrompt, 300);
      } catch (e) {
        console.warn("Gemini summary failed:", e.message);
        summaryText = heuristicSummary({ desiredSteps });
      }
    } else {
      summaryText = heuristicSummary({ desiredSteps });
    }

    const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
    const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: videoTitle, steps });
    const vid = videoId || extractYouTubeVideoId(videoUrl);
    const citations = vid ? await buildCitations({ videoId: vid, videoTitle, videoUrl, max: 3 }) : [];
    const desiredChapters = extractDesiredChapters(query);
    const chapters = vid ? (await getChapters(vid, videoTitle, { desired: desiredChapters })).chapters : [];
    return res.json({
      title: videoTitle,
      steps,
      videoUrl,
      ...annotateSource(source, 'real'),
      citations,
      chapters,
      deliveryPlan,
      requestId,
      summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
    });
  } catch (err) {
    console.error("Search error:", err?.response?.data || err.message || err);
    const statusCode = err?.status || err?.response?.status || 500;
    const detail = err?.message || "Unexpected error";
    return res.status(statusCode).json({ error: statusCode === 404 ? "Not found" : "Internal server error", detail });
  }
});

// Server-Sent Events streaming endpoint for progressive UI updates
// Usage: GET /api/search/stream?query=...
app.get("/api/search/stream", async (req, res) => {
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!(await simpleRateLimit(`stream:${ip}`, 10))) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  const validation = normalizeQueryInput(req.query.query, MAX_STREAM_QUERY_LEN);
  if (!validation.ok) return res.status(validation.status).json({ error: validation.error });
  const query = validation.value;
  const deliveryMode = detectDeliveryModeFromQuery(query);

  // Set SSE headers
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  const clientState = { closed: false };
  req.on('close', () => {
    clientState.closed = true;
  });

  const writeEvent = (obj) => {
    if (clientState.closed || res.writableEnded || res.destroyed) return;
    try {
      res.write(`data: ${JSON.stringify(obj)}\n\n`);
    } catch (e) {
      // client likely disconnected
      clientState.closed = true;
      return;
    }
  };

  const end = () => {
    if (res.writableEnded || res.destroyed) return;
    try {
      res.end();
    } catch (_) {
      return;
    }
  };

  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    // Stream mock in small chunks
    const mock = makeMockResponse();
    const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: mock.title, steps: mock.steps || [] });
    writeEvent({ type: "meta", title: mock.title, videoUrl: mock.videoUrl, source: mock.source, deliveryMode });
    const steps = mock.steps || [];
    let idx = 0;
    const interval = setInterval(() => {
      if (idx < steps.length) {
        writeEvent({ type: "partial", step: steps[idx] });
        idx++;
      } else {
        clearInterval(interval);
        // final event with citations and chapters
        (async () => {
          try {
            if (clientState.closed) return;
            const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
            const citations = await buildCitations({ videoId: vid, videoTitle: mock.title, videoUrl: mock.videoUrl, max: 3 });
            const desiredChapters = extractDesiredChapters(query);
            const chapters = (await getChapters(vid, mock.title, { desired: desiredChapters })).chapters;
            writeEvent({ type: 'final', citations, chapters, deliveryPlan });
            writeEvent({ type: 'done' });
          } catch (err) {
            writeEvent({ type: 'error', error: 'Internal server error', detail: err?.message || 'Unexpected error' });
          } finally {
            end();
          }
        })();
      }
    }, 220);
    req.on("close", () => clearInterval(interval));
    return;
  }

  (async () => {
    try {
      let searchTerm = query;
      const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
      const useGemini = USE_GEMINI_ENV && !breakerActive && (req.query?.useGemini !== "false");
      let reformulationTimedOut = false;
      if (useGemini && USE_GEMINI_REFORMULATION) {
        const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
        try {
          let reform = await generateWithGemini(reformPrompt, 32);
          reform = String(reform)
            .split(/\r?\n/)[0]
            .replace(/^[-*•\s>"]+/, "")
            .replace(/["`]+/g, "")
            .trim();
          if (reform && reform.length <= 80) searchTerm = reform;
        } catch (e) {
          if (/timeout/i.test(e.message || "")) reformulationTimedOut = true;
          console.warn("Gemini reformulation (stream) failed:", e.message);
        }
      }

      // Search video first and emit meta
      let videoTitle, videoUrl, source, videoId;
      try {
        const video = await searchYouTube(searchTerm);
        videoTitle = video.title;
        videoUrl = video.url;
        source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
        observeExternal('youtube', 'success');
      } catch (videoErr) {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          const mock = makeMockResponse();
          observeExternal('youtube', 'fallback');
          writeEvent({ type: "meta", title: mock.title, videoUrl: mock.videoUrl, source: "mock-fallback" });
          for (const s of mock.steps) {
            writeEvent({ type: "partial", step: s });
            await new Promise(r => setTimeout(r, 180));
          }
          writeEvent({ type: "done" });
          return end();
        }
        throw videoErr;
      }

      writeEvent({ type: "meta", title: videoTitle, videoUrl, source, deliveryMode });

      // Summarize and stream steps one by one (Gemini returns full text; we simulate token streaming)
      let summaryText = "";
      const attemptGeminiSummary = useGemini && !reformulationTimedOut;
      const desiredSteps = extractDesiredSteps(query);
      if (attemptGeminiSummary) {
        const summaryPrompt = desiredSteps
          ? `Résume cette vidéo YouTube en ${desiredSteps} étapes claires: ${videoTitle}`
          : `Résume cette vidéo YouTube en étapes claires: ${videoTitle}`;
        try {
          summaryText = await generateWithGemini(summaryPrompt, 300);
        } catch (e) {
          console.warn("Gemini summary (stream) failed:", e.message);
          summaryText = heuristicSummary({ desiredSteps });
        }
      } else {
        summaryText = heuristicSummary({ desiredSteps });
      }

      const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
      const deliveryPlan = buildDeliveryPlan({ mode: deliveryMode, query, title: videoTitle, steps });
      for (const s of steps) {
        if (clientState.closed) return end();
        writeEvent({ type: "partial", step: s });
        await new Promise(r => setTimeout(r, 160));
      }
      if (clientState.closed) return end();
      const vid = videoId || extractYouTubeVideoId(videoUrl);
      const citations = vid ? await buildCitations({ videoId: vid, videoTitle, videoUrl, max: 3 }) : [];
      const desiredChapters = extractDesiredChapters(query);
      const chapters = vid ? (await getChapters(vid, videoTitle, { desired: desiredChapters })).chapters : [];
      writeEvent({ type: "final", citations, chapters, deliveryPlan });
      writeEvent({ type: "done" });
      end();
    } catch (err) {
      console.error("Stream error:", err?.message || err);
      // Standardize error shape with /api/search endpoint: error + detail
      writeEvent({ type: "error", error: "Internal server error", detail: err?.message || "Unexpected error" });
      end();
    }
  })();
});

// Transcript endpoint: /api/transcript?videoId=...&title=...
app.get("/api/transcript", async (req, res) => {
  const videoId = String(req.query.videoId || '').trim();
  const title = String(req.query.title || '').trim();
  if (!videoId) return res.status(400).json({ error: 'videoId is required' });
  try {
    const { transcript, cache } = await getTranscript(videoId, title);
    // Optional key takeaways and quiz fields
    const keyTakeaways = transcript ? transcript.slice(0, 3).map(seg => seg.text) : [];
    const quiz = transcript ? [{ question: 'What is the first step?', answer: transcript[0]?.text }] : [];
    res.setHeader('X-Cache', cache);
    return res.json({ videoId, transcript, cached: cache === 'HIT', keyTakeaways, quiz });
  } catch (e) {
    return res.status(500).json({
      error: 'Transcript fetch failed', detail: e?.message || 'Unknown error', suggestedActions: [
        { label: 'Retry', action: '/api/transcript' },
        { label: 'Request help', action: '/support' }
      ]
    });
  }
});

// Chapters endpoint: /api/chapters?videoId=...&title=...
app.get("/api/chapters", async (req, res) => {
  const videoId = String(req.query.videoId || '').trim();
  const title = String(req.query.title || '').trim();
  const desired = req.query.desired ? parseInt(String(req.query.desired), 10) : undefined;
  if (!videoId) return res.status(400).json({ error: 'videoId is required' });
  try {
    const { chapters, cache } = await getChapters(videoId, title, { desired });
    // Optional key takeaways and quiz fields
    const keyTakeaways = chapters ? chapters.slice(0, 3).map(ch => ch.title) : [];
    const quiz = chapters ? [{ question: 'What is the main chapter?', answer: chapters[0]?.title }] : [];
    res.setHeader('X-Cache', cache);
    return res.json({ videoId, chapters, cached: cache === 'HIT', desired: Number.isFinite(desired) ? desired : null, keyTakeaways, quiz });
  } catch (e) {
    return res.status(500).json({
      error: 'Chapterization failed', detail: e?.message || 'Unknown error', suggestedActions: [
        { label: 'Retry', action: '/api/chapters' },
        { label: 'Request help', action: '/support' }
      ]
    });
  }
});

export function createApp() {
  return app;
}

// Only start server if run directly (not when imported for tests)
// Use URL-safe comparison to handle paths with spaces (e.g., "app howto")
const isDirectRun = Boolean(process.argv?.[1]) && import.meta.url === pathToFileURL(process.argv[1]).href;
let server = null;

if (isDirectRun) {
  const PORT = process.env.PORT || 3000;
  // Persistence initialization removed; handled by Mongoose.
  // Persistence mode logging removed; handled by Mongoose.
  server = app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Project: ${process.env.PROJECT_ID || 'unknown'}`);
    console.log(`Mock mode: ${(process.env.MOCK_MODE || 'true') === 'true' ? 'enabled' : 'disabled'}`);
    console.log(`Gemini: ${USE_GEMINI_ENV ? `enabled (${GEMINI_MODEL}, timeout=${GEMINI_TIMEOUT_MS}ms)` : 'disabled'}`);
    console.log(`YouTube API key: ${process.env.YT_API_KEY ? 'present' : 'missing'}`);
  });

  server.on('error', (err) => {
    console.error('Server listen error:', err?.message || err);
  });
}

// Connect to MongoDB (skip in tests to avoid external dependency requirement)
const shouldConnectMongo = process.env.NODE_ENV !== 'test';
if (shouldConnectMongo) {
  const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/hackit';
  mongoose.connect(mongoUri)
    .then(() => {
      console.log('MongoDB connected');
    })
    .catch((err) => {
      console.error('MongoDB connection error:', err);
    });
}

// ============ LESSON GENERATION & PERSISTENCE ============
// POST /api/generateLesson { query } (userId via middleware)
app.post("/api/generateLesson", userIdMiddleware, async (req, res) => {
  console.log('[POST /api/generateLesson] Authorization:', req.headers.authorization, 'userId:', req.userId);
  const validation = normalizeQueryInput(req.body?.query, MAX_QUERY_LEN);
  if (!validation.ok) return res.status(validation.status).json({ error: validation.error });
  const query = validation.value;
  const userId = req.userId;
  if (!userId) return res.status(400).json({ error: 'query and userId are required' });

  try {
    // 1) Find a video for the query (reuse same logic as /api/search)
    let searchTerm = query;
    const breakerActive = Date.now() < GEMINI_BREAKER_UNTIL;
    const useGemini = USE_GEMINI_ENV && !breakerActive && (req.body?.useGemini !== false);
    let reformulationTimedOut = false;
    if (useGemini && USE_GEMINI_REFORMULATION) {
      const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
      try {
        let reform = await generateWithGemini(reformPrompt, 32);
        reform = String(reform)
          .split(/\r?\n/)[0]
          .replace(/^[-*•\s>"]+/, "")
          .replace(/["`]+/g, "")
          .trim();
        if (reform && reform.length <= 80) searchTerm = reform;
      } catch (e) {
        if (/timeout/i.test(e.message || "")) reformulationTimedOut = true;
        console.warn("Gemini reformulation (generateLesson) failed:", e.message);
      }
    }

    let videoTitle, videoUrl;
    try {
      const video = await searchYouTube(searchTerm);
      videoTitle = video.title;
      videoUrl = video.url;
    } catch (e) {
      console.warn("Video search (generateLesson) failed:", e.message);
      if ((process.env.ALLOW_FALLBACK || "true") === "true") {
        const mock = makeMockResponse();
        videoTitle = mock.title; videoUrl = mock.videoUrl;
      } else {
        throw e;
      }
    }

    // 2) Summarize into steps and summary text
    let summaryText = "";
    const desiredSteps = extractDesiredSteps(query);
    const attemptGeminiSummary = useGemini && !reformulationTimedOut;
    if (attemptGeminiSummary) {
      const summaryPrompt = desiredSteps
        ? `Résume cette vidéo YouTube en ${desiredSteps} étapes claires: ${videoTitle}`
        : `Résume cette vidéo YouTube en étapes claires: ${videoTitle}`;
      try {
        summaryText = await generateWithGemini(summaryPrompt, 300);
      } catch (e) {
        console.warn("Gemini summary (generateLesson) failed:", e.message);
        summaryText = heuristicSummary({ desiredSteps });
      }
    } else {
      summaryText = heuristicSummary({ desiredSteps });
    }
    const steps = String(summaryText).split("\n").map(s => s.trim()).filter(Boolean);

    // 3) Persist lesson
    // Use Mongoose Lesson model directly
    const Lesson = (await import('./models/lesson.js')).default;
    const User = (await import('./models/User.js')).default;
    const mongoose = (await import('mongoose')).default;
    const lesson = await Lesson.create({ userId, title: videoTitle, steps, videoUrl, summary: summaryText });
    if (mongoose.Types.ObjectId.isValid(userId)) {
      await User.findByIdAndUpdate(userId, { $push: { savedLessons: lesson._id } });
    }
    // 4) Shape response
    return res.json({
      id: lesson._id?.toString() ?? '',
      userId: lesson.userId?.toString() ?? '',
      title: lesson.title?.toString() ?? '',
      summary: lesson.summary?.toString() ?? '',
      steps: Array.isArray(lesson.steps) ? lesson.steps.map(s => s?.toString() ?? '') : [],
      videoUrl: lesson.videoUrl?.toString() ?? '',
      favorite: !!lesson.favorite,
      views: typeof lesson.views === 'number' ? lesson.views : 0,
      createdAt: lesson.createdAt?.toISOString?.() ?? new Date().toISOString(),
      updatedAt: lesson.updatedAt?.toISOString?.() ?? new Date().toISOString(),
    });
  } catch (err) {
    console.error("generateLesson error:", err?.response?.data || err.message || err);
    const statusCode = err?.status || err?.response?.status || 500;
    const detail = err?.message || "Unexpected error";
    return res.status(statusCode).json({ error: statusCode === 404 ? "Not found" : "Internal server error", detail });
  }
});

// Mount lessons and users routers.
app.use('/api/lessons', lessonsRouter);

app.use((req, res) => {
  return res.status(404).json({ error: 'Not found' });
});

app.use((err, _req, res, next) => {
  if (res.headersSent) return next(err);
  if (err instanceof SyntaxError && Object.prototype.hasOwnProperty.call(err, 'body')) {
    return res.status(400).json({ error: 'Invalid JSON payload' });
  }
  const status = Number(err?.status || err?.statusCode) || 500;
  const detail = err?.message || 'Unexpected error';
  return res.status(status).json({ error: status >= 500 ? 'Internal server error' : 'Request failed', detail });
});

if (isDirectRun) {
  const closeServerGracefully = (signal) => {
    console.log(`Received ${signal}, shutting down gracefully...`);
    const timeout = setTimeout(() => {
      console.error('Graceful shutdown timeout reached, forcing exit');
      process.exit(1);
    }, 10000);

    const finalize = () => {
      clearTimeout(timeout);
      process.exit(0);
    };

    Promise.resolve()
      .then(async () => {
        if (redisClient && typeof redisClient.quit === 'function') {
          await redisClient.quit();
        }
      })
      .catch(() => { })
      .finally(() => {
        if (!server) return finalize();
        server.close(() => finalize());
      });
  };

  process.on('SIGINT', () => closeServerGracefully('SIGINT'));
  process.on('SIGTERM', () => closeServerGracefully('SIGTERM'));
  process.on('unhandledRejection', (reason) => {
    console.error('Unhandled promise rejection:', reason);
  });
}
