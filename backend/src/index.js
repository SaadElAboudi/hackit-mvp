// import { deleteLesson } from "./utils/persistence.js";
// Deprecated persistence import removed. Use Mongoose models instead.
import { OAuth2Client } from 'google-auth-library';
import { pathToFileURL } from "url";

import axios from "axios";
import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import morgan from "morgan";
// Avoid importing yt-search at module load on Node<20 to prevent undici File init crash

import { searchYouTube as originalSearchYouTube } from "./services/youtube.js";
import { getTranscript } from "./services/transcript.js";
import { getChapters, extractDesiredChapters } from "./services/chapters.js";


import { userIdMiddleware } from "./utils/userIdMiddleware.js";
import passport from "./utils/passportGoogle.js";
import { requireJwtAuth, requireJwtAuthOrGoogle } from "./utils/jwtAuth.js";
// Import requireAuth middleware from this file
// (already defined above)
import session from "express-session";
import userRouter from './routes/user.js';
import mongoose from 'mongoose';

const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

// Middleware pour exiger une authentification Google ou un token Google
async function requireAuth(req, res, next) {
  // Logging of authorization header removed for security.
  // Vérifie d'abord la session Passport
  if (req.isAuthenticated?.() && req.user) {
    return next();
  }

  // Vérifie le token Google envoyé en header
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    try {
      const ticket = await googleClient.verifyIdToken({
        idToken: token,
        audience: process.env.GOOGLE_CLIENT_ID,
      });
      const payload = ticket.getPayload();
      if (payload && payload.sub) {
        // Vérifie si l'utilisateur existe dans la BDD
        const User = (await import('./models/User.js')).default;
        let user = await User.findOne({ email: payload.email });
        if (!user) {
          // Crée automatiquement un compte utilisateur Google
          user = new User({
            email: payload.email,
            password: '', // pas de mot de passe pour Google
            favorites: [],
            history: [],
            savedLessons: []
          });
          await user.save();
        }
        req.user = {
          id: user._id,
          email: user.email,
          displayName: payload.name,
          photo: payload.picture,
          provider: 'google',
        };
        return next();
      }
    } catch (err) {
      // Token invalide
      return res.status(401).json({ error: 'Invalid Google token', detail: err.message });
    }
  }

  // Sinon, refuse
  res.status(401).json({ error: 'Authentication required' });
}


dotenv.config({ quiet: true });



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
// Simple rate limiter for expensive endpoints
const rateLimit = {};
function simpleRateLimit(key, maxPerMinute = 30) {
  const now = Date.now();
  if (!rateLimit[key]) rateLimit[key] = [];
  rateLimit[key] = rateLimit[key].filter(ts => now - ts < 60000);
  if (rateLimit[key].length >= maxPerMinute) return false;
  rateLimit[key].push(now);
  return true;
}
// Route GET /api/lessons accessible sans requireAuth
// Removed duplicate /api/lessons route. Only the protected version remains below.
// Session pour Passport
app.use(session({
  secret: process.env.SESSION_SECRET || "dev_secret",
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production", maxAge: 1000 * 3600 * 24 * 365 }
}));
app.use(passport.initialize());
app.use(passport.session());
// Enable concise logging in all non-test environments
if (process.env.NODE_ENV && process.env.NODE_ENV !== "test") {
  app.use(morgan("dev"));
}
// ============ AUTHENTIFICATION GOOGLE ============
// Lance le flow OAuth Google
app.get('/auth/google', passport.authenticate('google', { scope: ['profile', 'email'] }));

// Callback Google OAuth
app.get('/auth/google/callback',
  passport.authenticate('google', { failureRedirect: '/' }),
  (req, res) => {
    // Redirige vers le frontend avec le userId en paramètre (à adapter selon l'URL du frontend)
    const userId = req.user?.id;
    res.redirect(`/auth-success?userId=${userId}`);
  }
);
// DELETE /api/lessons/:id
app.delete("/api/lessons/:id", requireJwtAuthOrGoogle, userIdMiddleware, async (req, res) => {
  const id = String(req.params.id || '').trim();
  if (!id) return res.status(400).json({ error: 'id is required' });
  try {
    await deleteLesson(id);
    return res.json({ deleted: true, id });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to delete lesson', detail: e?.message || 'Unknown error' });
  }
});

// Endpoint pour récupérer l'utilisateur authentifié
app.get('/api/me', (req, res) => {
  if (req.isAuthenticated?.() && req.user) {
    res.json({ ok: true, user: req.user });
  } else {
    res.status(401).json({ ok: false, error: 'Not authenticated' });
  }
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

// Allow overriding YouTube search implementation in tests without affecting production import binding.
let searchYouTube = originalSearchYouTube;
export function setSearchYouTube(fn) {
  if (typeof fn === 'function') {
    searchYouTube = fn;
  } else {
    throw new Error('setSearchYouTube expects a function');
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
      throw new Error(`Gemini timeout after ${GEMINI_TIMEOUT_MS}ms`);
    }
    // If NOT_FOUND: try a known accessible lite model explicitly
    if (status === 404 && GEMINI_MODEL !== "models/gemini-2.0-flash-lite" && GEMINI_MODEL !== "models/gemini-2.0-flash-lite-001") {
      process.env.GEMINI_MODEL = "models/gemini-2.0-flash-lite";
      return await generateWithGemini(prompt, maxOutputTokens);
    }
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

app.post("/api/search", async (req, res) => {
  // Rate limit by IP
  const ip = req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress;
  if (!simpleRateLimit(`search:${ip}`, 20)) {
    return res.status(429).json({ error: 'Too many requests, slow down.' });
  }
  const { query } = req.body;
  if (!query) return res.status(400).json({ error: "query is required" });

  // Dev mock mode: quick responses without keys. Default mock false if YT_API_KEY exists.
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    const mock = makeMockResponse();
    const vid = extractYouTubeVideoId(mock.videoUrl) || 'dQw4w9WgXcQ';
    const citations = await buildCitations({ videoId: vid, videoTitle: mock.title, videoUrl: mock.videoUrl, max: 3 });
    return res.json({ ...mock, citations });
  }

  try {
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
      videoId = video.videoId || extractYouTubeVideoId(video.url);
      source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
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
            return res.json({ ...makeMockResponse(), source: "mock-fallback" });
          }
          throw retryErr;
        }
      } else {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          return res.json({ ...makeMockResponse(), source: "mock-fallback" });
        }
        throw videoErr;
      }
    }

    let summaryText = "";
    const attemptGeminiSummary = useGemini && !reformulationTimedOut;
    const desiredSteps = extractDesiredSteps(query);
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
    const vid = videoId || extractYouTubeVideoId(videoUrl);
    const citations = vid ? await buildCitations({ videoId: vid, videoTitle, videoUrl, max: 3 }) : [];
    const desiredChapters = extractDesiredChapters(query);
    const chapters = vid ? (await getChapters(vid, videoTitle, { desired: desiredChapters })).chapters : [];
    return res.json({ title: videoTitle, steps, videoUrl, source, citations, chapters });
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
  if (!simpleRateLimit(`stream:${ip}`, 10)) {
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
          const citations = await buildCitations({ videoId: vid, videoTitle: mock.title, videoUrl: mock.videoUrl, max: 3 });
          const desiredChapters = extractDesiredChapters(query);
          const chapters = (await getChapters(vid, mock.title, { desired: desiredChapters })).chapters;
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
      } catch (videoErr) {
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          const mock = makeMockResponse();
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
      const citations = vid ? await buildCitations({ videoId: vid, videoTitle, videoUrl, max: 3 }) : [];
      const desiredChapters = extractDesiredChapters(query);
      const chapters = vid ? (await getChapters(vid, videoTitle, { desired: desiredChapters })).chapters : [];
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

// Connect to MongoDB
mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/hackit', {
  useNewUrlParser: true,
  useUnifiedTopology: true,
});

mongoose.connection.on('connected', () => {
  console.log('MongoDB connected');
});
mongoose.connection.on('error', (err) => {
  console.error('MongoDB connection error:', err);
});

// ============ LESSON GENERATION & PERSISTENCE ============
// POST /api/lessons { title, steps[], videoUrl, summary? } (userId via middleware)
app.post("/api/lessons", requireJwtAuthOrGoogle, userIdMiddleware, async (req, res) => {
  // Only log userId, not full headers
  console.log('[POST /api/lessons] userId:', req.userId);
  try {
    const { title, steps, videoUrl, summary } = req.body || {};
    const userId = req.userId;
    // Advanced validation
    if (!userId || typeof userId !== 'string' || userId.length < 3 || userId.length > 128) {
      return res.status(400).json({ error: "Invalid userId" });
    }
    // Autoriser les userId anonymes ou numériques
    const isAnon = userId.startsWith('anon_');
    const isNumeric = /^[0-9]+$/.test(userId);
    const isAlphaNum = /^[a-zA-Z0-9_\-]+$/.test(userId);
    if (!(isAnon || isNumeric || isAlphaNum)) {
      return res.status(400).json({ error: "userId must be anon_, numeric, or alphanum" });
    }
    if (!title || typeof title !== 'string' || title.length < 2 || title.length > 120) {
      return res.status(400).json({ error: "Title must be 2-120 chars" });
    }
    if (!videoUrl || typeof videoUrl !== 'string' || !/^https?:\/\/.{8,}/.test(videoUrl)) {
      return res.status(400).json({ error: "Invalid videoUrl" });
    }
    if (!Array.isArray(steps) || steps.length === 0 || steps.length > 20 || !steps.every(s => typeof s === 'string' && s.length > 1 && s.length < 200)) {
      return res.status(400).json({ error: "steps[] must be 1-20 non-empty strings, each 2-200 chars" });
    }
    // Use Mongoose Lesson model directly
    const Lesson = (await import('./models/lesson.js')).default;
    const User = (await import('./models/User.js')).default;
    const lesson = await Lesson.create({ userId, title, steps, videoUrl, summary });
    // Only link lesson to user if userId is a valid ObjectId
    const mongoose = (await import('mongoose')).default;
    if (mongoose.Types.ObjectId.isValid(userId)) {
      await User.findByIdAndUpdate(userId, { $push: { savedLessons: lesson._id } });
    }
    // Ensure all fields are non-null strings/arrays for frontend
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
  } catch (e) {
    console.error('[POST /api/lessons] Internal error:', e?.message || e);
    return res.status(500).json({ error: 'Failed to save lesson', detail: 'Internal error' });
  }
});
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

    let videoTitle, videoUrl, videoId;
    try {
      const video = await searchYouTube(searchTerm);
      videoTitle = video.title;
      videoUrl = video.url;
      videoId = video.videoId || extractYouTubeVideoId(video.url);
    } catch (e) {
      console.warn("Video search (generateLesson) failed:", e.message);
      if ((process.env.ALLOW_FALLBACK || "true") === "true") {
        const mock = makeMockResponse();
        videoTitle = mock.title; videoUrl = mock.videoUrl; videoId = extractYouTubeVideoId(videoUrl);
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

// PATCH /api/lessons/:id/favorite { favorite: true|false }
app.patch("/api/lessons/:id/favorite", requireJwtAuthOrGoogle, async (req, res) => {
  console.log('[PATCH /api/lessons/:id/favorite] Authorization:', req.headers.authorization, 'userId:', req.userId);
  const id = String(req.params.id || '').trim();
  const favorite = !!req.body?.favorite;
  if (!id || typeof id !== 'string') return res.status(400).json({ error: 'id is required' });
  try {
    const updated = await setFavorite(id, favorite);
    if (!updated) return res.status(404).json({ error: 'Not found' });
    return res.json(updated);
  } catch (e) {
    console.error('[PATCH /api/lessons/:id/favorite] Internal error:', e?.message || e);
    return res.status(500).json({ error: 'Failed to update favorite', detail: e?.message || 'Unknown error' });
  }
});

// POST /api/lessons/:id/view -> record history entry (views++, lastViewedAt=now)
app.post("/api/lessons/:id/view", requireJwtAuthOrGoogle, async (req, res) => {
  console.log('[POST /api/lessons/:id/view] Authorization:', req.headers.authorization, 'userId:', req.userId);
  const id = String(req.params.id || '').trim();
  if (!id || typeof id !== 'string') return res.status(400).json({ error: 'id is required' });
  try {
    const updated = await recordView(id);
    if (!updated) return res.status(404).json({ error: 'Not found' });
    return res.json(updated);
  } catch (e) {
    console.error('[POST /api/lessons/:id/view] Internal error:', e?.message || e);
    return res.status(500).json({ error: 'Failed to record view', detail: e?.message || 'Unknown error' });
  }
});

// GET /api/lessons?favorite=true|false&sort=createdAt|lastViewedAt&order=desc|asc (userId via middleware)
app.get("/api/lessons", requireJwtAuthOrGoogle, userIdMiddleware, async (req, res) => {
  // Middleware to accept either JWT (login/password) or Google OAuth
  function requireJwtAuthOrGoogle(req, res, next) {
    // Try JWT first
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.split(' ')[1];
      const { verifyToken } = require('./utils/jwtAuth.js');
      const payload = verifyToken(token);
      if (payload && payload.userId) {
        req.userId = payload.userId;
        req.jwtUser = payload;
        return next();
      }
    }
    // Fallback to Google OAuth
    return requireAuth(req, res, next);
  }
  const userId = req.userId;
  if (!userId) return res.status(400).json({ error: 'userId is required' });
  const favorite = req.query.favorite === undefined ? undefined : String(req.query.favorite).toLowerCase() === 'true';
  const sortBy = ['createdAt', 'lastViewedAt', 'views'].includes(String(req.query.sort || '')) ? String(req.query.sort) : 'createdAt';
  const order = String(req.query.order || 'desc').toLowerCase() === 'asc' ? 'asc' : 'desc';
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit || '50'), 10)));
  const offset = Math.max(0, parseInt(String(req.query.offset || '0'), 10));
  try {
    let items = await listLessons({ userId, favorite, sortBy, order, limit, offset });
    // Add progress/reminder fields for My Learning Journey pivot
    items = items.map(lesson => ({
      ...lesson,
      progress: lesson.progress || 0, // Placeholder, to be implemented
      reminder: lesson.reminder || null, // Placeholder, to be implemented
      // Guest mode prompt
      guestPrompt: (!req.isAuthenticated?.() && !req.user) ? 'Save progress or unlock premium features by signing in.' : undefined
    }));
    // Suggested actions for empty/error states
    const suggestedActions = items.length === 0 ? [
      { label: 'Search for a lesson', action: '/api/search' },
      { label: 'Request help', action: '/support' }
    ] : undefined;
    return res.json({ items, total: items.length, suggestedActions });
  } catch (e) {
    return res.status(500).json({
      error: 'Failed to list lessons', detail: e?.message || 'Unknown error', suggestedActions: [
        { label: 'Retry', action: '/api/lessons' },
        { label: 'Request help', action: '/support' }
      ]
    });
  }
});

// Import and mount the user router on /api/users to expose /api/users/all endpoint.
app.use('/api/users', userRouter);