// import { deleteLesson } from "./utils/persistence.js";
// Deprecated persistence import removed. Use Mongoose models instead.
import { randomBytes } from 'crypto';
import { pathToFileURL } from 'url';

import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import session from 'express-session';
import mongoose from 'mongoose';
import morgan from 'morgan';

import { getFeatureFlags } from './config/featureFlags.js';
import lessonsRouter from './routes/lessons.js';
import userRouter from './routes/user.js';
import { getChapters, extractDesiredChapters } from './services/chapters.js';
import { buildLearningPath, buildNextActions, normalizeLearningPreferences } from './services/learningExperience.js';
import { analyzeQuery, buildSearchSuggestions } from './services/queryAssist.js';
import { buildRelatedQueries, buildSearchCacheKey, createSearchCache } from './services/searchExperience.js';
import { getTranscript } from './services/transcript.js';
import { searchYouTube as originalSearchYouTube } from './services/youtube.js';
import { requireJwtAuthOrGoogle } from './utils/jwtAuth.js';
import { validateBody, validateFeedbackPayload, validateSearchPayload, validateTtvPayload } from './middleware/validation.js';
import { buildObservabilitySnapshot, evaluateAlerts, observeExternal, observeHttp, observeQualityEvent, observeTtvEvent } from './utils/observability.js';
import passport, { isGoogleOAuthEnabled } from './utils/passportGoogle.js';
import { userIdMiddleware } from './utils/userIdMiddleware.js';

// Avoid importing yt-search at module load on Node<20 to prevent undici File init crash
const dynamicImport = (moduleName) => Function('m', 'return import(m)')(moduleName);

dotenv.config({ quiet: true });

const featureFlags = getFeatureFlags();
const searchCache = createSearchCache();
const recentSearchQueries = [];
const MAX_RECENT_SEARCHES = 80;
const SEARCH_ENRICHMENT_TIMEOUT_MS = Number(process.env.SEARCH_ENRICHMENT_TIMEOUT_MS || 1800);

const app = express();
// CORS middleware at the very top
// Restrict CORS in production, allow all in dev
app.use(cors({
  origin: process.env.NODE_ENV === 'production'
    ? [process.env.FRONTEND_ORIGIN || 'https://yourfrontend.com']
    : true,
  credentials: true
}));
app.use(express.json());
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
// Route GET /api/lessons accessible sans requireAuth
// Removed duplicate /api/lessons route. Only the protected version remains below.
// Session pour Passport
const sessionConfig = {
  name: 'hackit.sid',
  secret: process.env.SESSION_SECRET || "dev_secret",
  resave: false,
  saveUninitialized: false,
  rolling: process.env.NODE_ENV === 'production',
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: 1000 * 3600 * 24 * 30,
  },
};

const sessionStoreMongoUrl = process.env.SESSION_STORE_MONGO_URL || process.env.MONGODB_URI;
if (process.env.NODE_ENV === 'production' && sessionStoreMongoUrl) {
  try {
    const mongoStoreModule = await dynamicImport('connect-mongo');
    const MongoStore = mongoStoreModule.default;
    sessionConfig.store = MongoStore.create({
      mongoUrl: sessionStoreMongoUrl,
      ttl: 60 * 60 * 24 * 30,
      autoRemove: 'native',
    });
  } catch (err) {
    console.warn('External session store unavailable, falling back to memory store:', err?.message || err);
  }
}

app.use(session(sessionConfig));
app.use(passport.initialize());
app.use(passport.session());
// Enable concise logging in all non-test environments
if (process.env.NODE_ENV && process.env.NODE_ENV !== "test") {
  app.use(morgan("dev"));
}
// ============ AUTHENTIFICATION GOOGLE ============
app.get('/auth/google/status', (_req, res) => {
  return res.json({
    enabled: isGoogleOAuthEnabled(),
    hasClientId: Boolean(process.env.GOOGLE_CLIENT_ID),
    hasCallbackUrl: Boolean(process.env.GOOGLE_CALLBACK_URL),
  });
});

app.get('/api/feature-flags', (_req, res) => {
  return res.json({ ok: true, flags: featureFlags });
});

// Lance le flow OAuth Google (CSRF state token)
app.get('/auth/google', (req, res, next) => {
  if (!isGoogleOAuthEnabled()) {
    return res.status(503).json({
      error: 'Google OAuth is not configured',
      detail: 'Missing GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, or GOOGLE_CALLBACK_URL',
    });
  }

  const state = randomBytes(24).toString('hex');
  req.session.oauthState = state;
  return passport.authenticate('google', { scope: ['profile', 'email'], state })(req, res, next);
});

// Callback Google OAuth + state validation + session rotation
app.get('/auth/google/callback',
  (req, res, next) => {
    if (!isGoogleOAuthEnabled()) {
      return res.status(503).json({ error: 'Google OAuth is not configured' });
    }
    const expectedState = req.session?.oauthState;
    if (req.session) delete req.session.oauthState;
    if (!expectedState || req.query.state !== expectedState) {
      return res.status(403).json({ error: 'Invalid OAuth state' });
    }
    return next();
  },
  passport.authenticate('google', { failureRedirect: '/' }),
  (req, res, next) => {
    const authenticatedUser = req.user;
    req.session.regenerate((sessionErr) => {
      if (sessionErr) return next(sessionErr);
      req.login(authenticatedUser, (loginErr) => {
        if (loginErr) return next(loginErr);
        const userId = authenticatedUser?.id;
        const frontendOrigin = process.env.FRONTEND_ORIGIN || '';
        if (frontendOrigin) {
          return res.redirect(`${frontendOrigin.replace(/\/$/, '')}/auth-success?userId=${userId}`);
        }
        return res.redirect(`/auth-success?userId=${userId}`);
      });
    });
  }
);
// Endpoint pour récupérer l'utilisateur authentifié
app.get('/api/me', userIdMiddleware, (req, res) => {
  if (req.isAuthenticated?.() && req.user) {
    return res.json({ ok: true, user: req.user, auth: 'google-session' });
  }

  return res.json({
    ok: true,
    auth: 'anonymous',
    user: {
      id: req.userId,
      isAnonymous: Boolean(req.isAnonymous),
    },
  });
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
      return { stepsTarget: 3, maxOutputTokens: 140 };
    case 'deep':
      return { stepsTarget: 8, maxOutputTokens: 420 };
    default:
      return { stepsTarget: 5, maxOutputTokens: 300 };
  }
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

async function withTimeout(promise, timeoutMs, fallbackValue) {
  let timeoutId;
  const timeoutPromise = new Promise((resolve) => {
    timeoutId = setTimeout(() => resolve(fallbackValue), timeoutMs);
  });
  const result = await Promise.race([promise, timeoutPromise]);
  clearTimeout(timeoutId);
  return result;
}

async function buildSearchEnrichments({ query, videoId, videoTitle, videoUrl }) {
  if (!videoId) {
    return { citations: [], chapters: [] };
  }
  const desiredChapters = extractDesiredChapters(query);
  const [citations, chaptersResult] = await Promise.all([
    withTimeout(
      buildCitations({ videoId, videoTitle, videoUrl, max: 3 }).catch(() => []),
      SEARCH_ENRICHMENT_TIMEOUT_MS,
      []
    ),
    withTimeout(
      getChapters(videoId, videoTitle, { desired: desiredChapters }).catch(() => ({ chapters: [] })),
      SEARCH_ENRICHMENT_TIMEOUT_MS,
      { chapters: [] }
    ),
  ]);
  return { citations, chapters: chaptersResult?.chapters || [] };
}

async function buildFallbackSearchResponse({ query, summaryLength, learningPreferences, requestId, mode = 'fallback' }) {
  const mock = makeMockResponse();
  const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
  const { citations, chapters } = await buildSearchEnrichments({
    query,
    videoId: vid,
    videoTitle: mock.title,
    videoUrl: mock.videoUrl,
  });
  const relatedQueries = buildRelatedQueries({ query, title: mock.title, alternatives: [], max: 5 });
  const learningPath = buildLearningPath({ steps: mock.steps, expertiseLevel: learningPreferences.expertiseLevel });
  const nextActions = buildNextActions({ videoId: vid, videoUrl: mock.videoUrl, relatedQueries });
  const queryAnalysis = analyzeQuery(query);
  const suggestions = buildSearchSuggestions({
    query,
    relatedQueries,
    recentQueries: recentSearchQueries.slice(0, 20),
    max: 6,
  });

  return {
    ...mock,
    ...annotateSource('mock-fallback', mode),
    citations,
    chapters,
    relatedQueries,
    learningPath,
    nextActions,
    queryAnalysis,
    suggestions,
    learningPreferences,
    requestId,
    summaryLength,
    cache: { hit: false },
  };
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

function rememberRecentQuery(query) {
  const q = String(query || '').trim();
  if (!q) return;
  const existingIndex = recentSearchQueries.findIndex((item) => item.toLowerCase() === q.toLowerCase());
  if (existingIndex !== -1) recentSearchQueries.splice(existingIndex, 1);
  recentSearchQueries.unshift(q);
  if (recentSearchQueries.length > MAX_RECENT_SEARCHES) {
    recentSearchQueries.length = MAX_RECENT_SEARCHES;
  }
}

async function generateWithGemini(prompt, maxOutputTokens = 256) {
  if (!GEMINI_API_KEY) throw new Error("GEMINI_API_KEY missing");
  // Use v1 generateContent endpoint for modern models; fall back to legacy if needed.
  const isLegacy = /bison|text-bison/i.test(GEMINI_MODEL);
  const baseUrl = isLegacy
    ? `https://generativelanguage.googleapis.com/v1beta2/${GEMINI_MODEL}:generateText?key=${GEMINI_API_KEY}`
    : `https://generativelanguage.googleapis.com/v1/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

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
    // If NOT_FOUND: try a known accessible lite model explicitly
    if (status === 404 && GEMINI_MODEL !== "models/gemini-2.0-flash-lite" && GEMINI_MODEL !== "models/gemini-2.0-flash-lite-001") {
      process.env.GEMINI_MODEL = "models/gemini-2.0-flash-lite";
      return await generateWithGemini(prompt, maxOutputTokens);
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
  if (!featureFlags.observability) {
    return res.status(503).json({ error: 'Observability is disabled by feature flag' });
  }
  const snapshot = buildObservabilitySnapshot();
  const alerts = evaluateAlerts(snapshot);
  res.json({ ok: true, snapshot, alerts });
});

app.post('/api/search/feedback', validateBody(validateFeedbackPayload), async (req, res) => {
  if (!featureFlags.searchFeedback) {
    return res.status(503).json({ error: 'Search feedback is disabled by feature flag' });
  }
  const { requestId, clicked, completed, rating } = req.validatedBody;
  observeQualityEvent({ requestId, clicked, completed, rating });
  return res.json({ ok: true });
});

app.post('/api/analytics/ttv', validateBody(validateTtvPayload), async (req, res) => {
  const { requestId, ttvMs } = req.validatedBody;
  observeTtvEvent({ requestId, ttvMs });
  return res.json({ ok: true });
});

app.get('/api/recommendations', requireJwtAuthOrGoogle, userIdMiddleware, async (req, res) => {
  if (!featureFlags.recommendations) {
    return res.status(503).json({ error: 'Recommendations are disabled by feature flag' });
  }
  try {
    const Lesson = (await import('./models/lesson.js')).default;
    const userId = req.userId;
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

app.get('/api/search/suggestions', async (req, res) => {
  const query = String(req.query.query || '').trim();
  const related = String(req.query.related || '')
    .split('|')
    .map((x) => x.trim())
    .filter(Boolean);
  const suggestions = buildSearchSuggestions({
    query,
    relatedQueries: related,
    recentQueries: recentSearchQueries.slice(0, 20),
    max: 6,
  });
  return res.json({ query, suggestions, recentCount: recentSearchQueries.length });
});


app.post("/api/search", async (req, res) => {
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!(await simpleRateLimit(`search:${ip}`, 20))) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  let query;
  let useGeminiOverride;
  let summaryLength;
  let maxResults;
  let pageToken;
  let tone;
  let expertiseLevel;
  try {
    ({ query, useGemini: useGeminiOverride, summaryLength, maxResults, pageToken, tone, expertiseLevel } = validateSearchPayload(req.body || {}));
  } catch (e) {
    return res.status(e?.status || 400).json({ error: e?.message || 'Invalid payload', detail: e?.details || null });
  }
  const learningPreferences = normalizeLearningPreferences({ tone, expertiseLevel });
  const queryAnalysis = analyzeQuery(query);
  const requestId = randomBytes(8).toString('hex');
  const summaryConfig = getSummaryConfig(featureFlags.multiLengthSummary ? summaryLength : 'standard');
  const searchOptions = { maxResults, pageToken };
  const cacheAllowed = useGeminiOverride === false || !USE_GEMINI_ENV;
  const cacheKey = buildSearchCacheKey({
    query,
    summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
    useGemini: useGeminiOverride,
    maxResults,
    pageToken,
    tone: learningPreferences.tone,
    expertiseLevel: learningPreferences.expertiseLevel,
  });
  if (cacheAllowed) {
    const cachedResult = searchCache.get(cacheKey);
    if (cachedResult) {
      res.setHeader('X-Search-Cache', 'HIT');
      rememberRecentQuery(query);
      return res.json({
        ...cachedResult,
        requestId,
        cache: { hit: true },
        badges: [...new Set([...(cachedResult.badges || []), 'CACHED'])],
      });
    }
  }
  res.setHeader('X-Search-Cache', 'MISS');

  // Dev mock mode: quick responses without keys. Default mock false if YT_API_KEY exists.
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    const mock = makeMockResponse();
    const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
    const { citations, chapters } = await buildSearchEnrichments({
      query,
      videoId: vid,
      videoTitle: mock.title,
      videoUrl: mock.videoUrl,
    });
    const sourceMeta = annotateSource(mock.source, 'mock');
    const relatedQueries = buildRelatedQueries({ query, title: mock.title, alternatives: [], max: 5 });
    const learningPath = buildLearningPath({ steps: mock.steps, expertiseLevel: learningPreferences.expertiseLevel });
    const nextActions = buildNextActions({ videoId: vid, videoUrl: mock.videoUrl, relatedQueries });
    const suggestions = buildSearchSuggestions({
      query,
      relatedQueries,
      recentQueries: recentSearchQueries.slice(0, 20),
      max: 6,
    });
    rememberRecentQuery(query);
    return res.json({
      ...mock,
      ...sourceMeta,
      citations,
      chapters,
      relatedQueries,
      learningPath,
      nextActions,
      queryAnalysis,
      suggestions,
      learningPreferences,
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
    let videoAlternatives = [];
    let nextPageToken = null;
    try {
      const video = await searchYouTube(searchTerm, searchOptions);
      videoTitle = video.title;
      videoUrl = video.url;
      videoId = video.videoId || extractYouTubeVideoId(video.url);
      source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
      videoAlternatives = Array.isArray(video.alternatives) ? video.alternatives : [];
      nextPageToken = video.nextPageToken || null;
      observeExternal('youtube', 'success');
    } catch (videoErr) {
      console.warn("Video search failed:", videoErr.message);
      if (videoErr.code === "YOUTUBE_NO_RESULTS" && searchTerm !== query) {
        console.log("Retrying YouTube search with original query after no results for reformulated term.");
        try {
          const retryVideo = await searchYouTube(query, searchOptions);
          videoTitle = retryVideo.title;
          videoUrl = retryVideo.url;
          videoId = retryVideo.videoId || extractYouTubeVideoId(retryVideo.url);
          source = retryVideo.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
          videoAlternatives = Array.isArray(retryVideo.alternatives) ? retryVideo.alternatives : [];
          nextPageToken = retryVideo.nextPageToken || null;
          console.log("Recovered video via original query.");
        } catch (retryErr) {
          console.warn("Retry with original query also failed:", retryErr.message);
          if ((process.env.ALLOW_FALLBACK || "true") === "true") {
            observeExternal('youtube', 'fallback');
            const fallbackPayload = await buildFallbackSearchResponse({
              query,
              summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
              learningPreferences,
              requestId,
              mode: 'fallback',
            });
            rememberRecentQuery(query);
            return res.json(fallbackPayload);
          }
          throw retryErr;
        }
      } else {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          observeExternal('youtube', 'fallback');
          const fallbackPayload = await buildFallbackSearchResponse({
            query,
            summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
            learningPreferences,
            requestId,
            mode: 'fallback',
          });
          rememberRecentQuery(query);
          return res.json(fallbackPayload);
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
      const toneInstruction = learningPreferences.tone === 'coach'
        ? 'Use a motivating coaching tone.'
        : learningPreferences.tone === 'friendly'
          ? 'Use a warm, friendly tone.'
          : 'Use a concise, practical tone.';
      const levelInstruction = learningPreferences.expertiseLevel === 'beginner'
        ? 'Assume the user is a beginner and avoid jargon.'
        : learningPreferences.expertiseLevel === 'advanced'
          ? 'Assume the user is advanced and include optimization tips.'
          : 'Assume the user has intermediate knowledge.';

      const summaryPrompt = transcriptText
        ? (desiredSteps
          ? `Summarize this content in ${desiredSteps} clear steps. ${toneInstruction} ${levelInstruction}\n${transcriptText}`
          : `Summarize this content in clear steps. ${toneInstruction} ${levelInstruction}\n${transcriptText}`)
        : (desiredSteps
          ? `Summarize this YouTube video in ${desiredSteps} clear steps: ${videoTitle}. ${toneInstruction} ${levelInstruction}`
          : `Summarize this YouTube video in clear steps: ${videoTitle}. ${toneInstruction} ${levelInstruction}`);
      try {
        summaryText = await generateWithGemini(summaryPrompt, summaryConfig.maxOutputTokens);
      } catch (e) {
        console.warn("Gemini summary failed:", e.message);
        summaryText = heuristicSummary({ desiredSteps });
      }
    } else {
      summaryText = heuristicSummary({ desiredSteps });
    }

    const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
    const vid = videoId || extractYouTubeVideoId(videoUrl);
    const { citations, chapters } = await buildSearchEnrichments({
      query,
      videoId: vid,
      videoTitle,
      videoUrl,
    });
    const sourceMeta = annotateSource(source, 'real');
    const relatedQueries = buildRelatedQueries({ query, title: videoTitle, alternatives: videoAlternatives, max: 5 });
    const learningPath = buildLearningPath({ steps, expertiseLevel: learningPreferences.expertiseLevel });
    const nextActions = buildNextActions({ videoId: vid, videoUrl, relatedQueries });
    const suggestions = buildSearchSuggestions({
      query,
      relatedQueries,
      recentQueries: recentSearchQueries.slice(0, 20),
      max: 6,
    });
    const responsePayload = {
      title: videoTitle,
      steps,
      videoUrl,
      ...sourceMeta,
      citations,
      chapters,
      alternatives: videoAlternatives,
      nextPageToken,
      relatedQueries,
      learningPath,
      nextActions,
      queryAnalysis,
      suggestions,
      learningPreferences,
      requestId,
      summaryLength: featureFlags.multiLengthSummary ? summaryLength : 'standard',
      cache: { hit: false },
    };
    if (cacheAllowed) {
      searchCache.set(cacheKey, { ...responsePayload, requestId: null });
    }
    rememberRecentQuery(query);
    return res.json(responsePayload);
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
  if (!featureFlags.searchStreaming) {
    return res.status(503).json({ error: 'Search streaming is disabled by feature flag' });
  }
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!(await simpleRateLimit(`stream:${ip}`, 10))) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  const query = String(req.query.query || "").trim();
  if (!query) return res.status(400).json({ error: "query is required" });

  // Set SSE headers
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  const writeEvent = (obj) => {
    try {
      res.write(`data: ${JSON.stringify(obj)}\n\n`);
    } catch (e) {
      // client likely disconnected
      return; // avoid empty catch block per lint rules
    }
  };

  const end = () => {
    try { res.end(); } catch (_) { return; }
  };

  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    // Stream mock in small chunks
    const mock = makeMockResponse();
    writeEvent({ type: "meta", title: mock.title, videoUrl: mock.videoUrl, source: mock.source });
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
          const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
          const { citations, chapters } = await buildSearchEnrichments({
            query,
            videoId: vid,
            videoTitle: mock.title,
            videoUrl: mock.videoUrl,
          });
          writeEvent({ type: "final", citations, chapters });
          writeEvent({ type: "done" });
          end();
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
        videoId = video.videoId || extractYouTubeVideoId(video.url);
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

      writeEvent({ type: "meta", title: videoTitle, videoUrl, source });

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
      for (const s of steps) {
        writeEvent({ type: "partial", step: s });
        await new Promise(r => setTimeout(r, 160));
      }
      const vid = videoId || extractYouTubeVideoId(videoUrl);
      const { citations, chapters } = await buildSearchEnrichments({
        query,
        videoId: vid,
        videoTitle,
        videoUrl,
      });
      writeEvent({ type: "final", citations, chapters });
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



app.use((err, _req, res, _next) => {
  const status = err?.status || 500;
  const code = err?.code || (status === 500 ? 'INTERNAL_ERROR' : 'REQUEST_ERROR');
  const message = err?.message || 'Internal server error';
  const detail = err?.details || null;
  return res.status(status).json({ error: message, code, detail });
});

export function createApp() {
  return app;
}

// Only start server if run directly (not when imported for tests)
// Use URL-safe comparison to handle paths with spaces (e.g., "app howto")
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const PORT = process.env.PORT || 3000;
  // Persistence initialization removed; handled by Mongoose.
  // Persistence mode logging removed; handled by Mongoose.
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Project: ${process.env.PROJECT_ID || 'unknown'}`);
    console.log(`Mock mode: ${(process.env.MOCK_MODE || 'true') === 'true' ? 'enabled' : 'disabled'}`);
    console.log(`Gemini: ${USE_GEMINI_ENV ? `enabled (${GEMINI_MODEL}, timeout=${GEMINI_TIMEOUT_MS}ms)` : 'disabled'}`);
    console.log(`YouTube API key: ${process.env.YT_API_KEY ? 'present' : 'missing'}`);
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
app.post("/api/generateLesson", requireJwtAuthOrGoogle, userIdMiddleware, async (req, res) => {
  console.log('[POST /api/generateLesson] Authorization:', req.headers.authorization, 'userId:', req.userId);
  const { query } = req.body || {};
  const userId = req.userId;
  if (!query || !userId) return res.status(400).json({ error: "query and userId are required" });

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
app.use('/api/users', userRouter);
