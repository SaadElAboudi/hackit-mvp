import { pathToFileURL } from "url";

import axios from "axios";
import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import morgan from "morgan";
// Avoid importing yt-search at module load on Node<20 to prevent undici File init crash

import { searchYouTube as originalSearchYouTube } from "./services/youtube.js";

dotenv.config({ quiet: true });

const app = express();
app.use(express.json());
app.use(cors());
// Silence noisy request logs during tests to avoid breaking node:test TAP output
if (process.env.NODE_ENV !== "test") {
  app.use(morgan("dev"));
}

const USE_GEMINI_ENV = (process.env.USE_GEMINI || "false") === "true";
const USE_GEMINI_REFORMULATION = (process.env.USE_GEMINI_REFORMULATION || "false") === "true";
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "models/gemini-2.0-flash-lite";
const GEMINI_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS || "4000");
let GEMINI_OPERATIONAL = true; // set to false after first hard failure

function makeMockResponse() {
  return {
    title: "Mock: Déboucher un évier",
    steps: [
      "Verse 1/2 tasse de bicarbonate dans la canalisation.",
      "Ajoute 1 tasse de vinaigre blanc.",
      "Laisse agir 10 minutes.",
      "Verse de l’eau bouillante.",
      "Rince à l’eau chaude."
    ],
    videoUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    source: "mock"
  };
}

function heuristicSummary() {
  // Very simple local summary when Gemini is disabled/unavailable
  const base = [
    "Ouvre la vidéo et lis la description.",
    "Prépare le matériel nécessaire avant de commencer.",
    "Suis les étapes démontrées, étape par étape.",
    "Mets en pause et reviens en arrière si besoin.",
    "Vérifie le résultat et nettoie/range le matériel.",
  ];
  // Ensure 5 steps max, trim
  return base.slice(0, 5).join("\n");
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
      return txt;
    }
  } catch (error) {
    const status = error?.response?.status;
    const message = error?.response?.data?.error?.message || error.message;
    // On timeout or network abort, throw a concise timeout error
    if (error?.code === 'ECONNABORTED' || /timeout/i.test(message || '')) {
      GEMINI_OPERATIONAL = false;
      throw new Error(`Gemini timeout after ${GEMINI_TIMEOUT_MS}ms`);
    }
    // If NOT_FOUND: try a known accessible lite model explicitly
    if (status === 404 && GEMINI_MODEL !== "models/gemini-2.0-flash-lite" && GEMINI_MODEL !== "models/gemini-2.0-flash-lite-001") {
      process.env.GEMINI_MODEL = "models/gemini-2.0-flash-lite";
      return await generateWithGemini(prompt, maxOutputTokens);
    }
    if (status === 404) {
      // mark non-operational to avoid chaining timeouts
      GEMINI_OPERATIONAL = false;
    }
    throw new Error(message || "Gemini generation failed");
  }
}

app.get("/health", (req, res) => {
  // If a YouTube API key is present, default mock mode to false, otherwise true.
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  const mock = (process.env.MOCK_MODE || mockDefault) === "true";
  res.json({
    ok: true,
    mock,
    projectId: process.env.PROJECT_ID || null,
    gemini: {
      useGemini: USE_GEMINI_ENV,
      model: GEMINI_MODEL,
      hasKey: Boolean(GEMINI_API_KEY),
      timeoutMs: GEMINI_TIMEOUT_MS
    },
    youtubeApi: Boolean(process.env.YT_API_KEY)
  });
});

// Extended health with dynamic Gemini state
app.get("/health/extended", (_req, res) => {
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  const mock = (process.env.MOCK_MODE || mockDefault) === "true";
  res.json({
    ok: true,
    projectId: process.env.PROJECT_ID || null,
    mock,
    youtube: { hasKey: Boolean(process.env.YT_API_KEY) },
    gemini: {
      configured: (process.env.USE_GEMINI || "false") === "true",
      hasKey: Boolean(GEMINI_API_KEY),
      model: GEMINI_MODEL,
      timeoutMs: GEMINI_TIMEOUT_MS,
      operational: GEMINI_OPERATIONAL,
    },
    timestamp: new Date().toISOString(),
  });
});

app.post("/api/search", async (req, res) => {
  const { query } = req.body;
  if (!query) return res.status(400).json({ error: "query is required" });

  // Dev mock mode: quick responses without keys. Default mock false if YT_API_KEY exists.
  const mockDefault = process.env.YT_API_KEY ? "false" : "true";
  if ((process.env.MOCK_MODE || mockDefault) === "true") {
    return res.json(makeMockResponse());
  }

  try {
    let searchTerm = query;
    const useGemini = USE_GEMINI_ENV && GEMINI_OPERATIONAL && (req.body?.useGemini !== false);
    let reformulationTimedOut = false;
    if (useGemini && USE_GEMINI_REFORMULATION) {
      const reformPrompt = `You are a YouTube search assistant. Convert the user question into ONE short English search query suitable for YouTube. Rules:\n- Max 6 words\n- No quotes, bullets, markdown, or explanations\n- Output ONLY the query.\n\nQuestion: ${query}\nQuery:`;
      try {
        let reform = await generateWithGemini(reformPrompt, 32);
        // Sanitize: take first line, strip bullets/quotes/markdown, limit length
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
        // If timeout occurred, mark and skip summary attempt to avoid doubling latency.
        if (/timeout/i.test(e.message || "")) {
          reformulationTimedOut = true;
        }
        searchTerm = query; // degrade gracefully
      }
    }

    // Unified YouTube search with internal API->fallback handling
    let videoTitle, videoUrl, source;
    try {
      const video = await searchYouTube(searchTerm);
      videoTitle = video.title;
      videoUrl = video.url;
      source = video.source || (process.env.YT_API_KEY ? "youtube-api" : "yt-search-fallback");
    } catch (videoErr) {
      console.warn("Video search failed:", videoErr.message);
      // If reformulated query failed, retry once with original user query before degrading
      if (videoErr.code === "YOUTUBE_NO_RESULTS" && searchTerm !== query) {
        console.log("Retrying YouTube search with original query after no results for reformulated term.");
        try {
          const retryVideo = await searchYouTube(query);
          videoTitle = retryVideo.title;
          videoUrl = retryVideo.url;
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
        // Graceful degrade: provide mock fallback if allowed instead of hard error
        if ((process.env.ALLOW_FALLBACK || "true") === "true") {
          return res.json({ ...makeMockResponse(), source: "mock-fallback" });
        }
        throw videoErr; // propagate to error handler
      }
    }

    let summaryText = "";
    // Skip summary Gemini call if the reformulation already timed out to keep total latency low.
    const attemptGeminiSummary = useGemini && !reformulationTimedOut;
    if (attemptGeminiSummary) {
      const summaryPrompt = `Résume cette vidéo YouTube en 5 étapes claires: ${videoTitle}`;
      try {
        summaryText = await generateWithGemini(summaryPrompt, 300);
      } catch (e) {
        console.warn("Gemini summary failed:", e.message);
        summaryText = heuristicSummary(videoTitle);
      }
    } else {
      summaryText = heuristicSummary(videoTitle);
    }

    const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
    return res.json({ title: videoTitle, steps, videoUrl, source });
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
        writeEvent({ type: "done" });
        end();
      }
    }, 220);
    req.on("close", () => clearInterval(interval));
    return;
  }

  (async () => {
    try {
      let searchTerm = query;
      const useGemini = USE_GEMINI_ENV && GEMINI_OPERATIONAL && (req.query?.useGemini !== "false");
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
      let videoTitle, videoUrl, source;
      try {
        const video = await searchYouTube(searchTerm);
        videoTitle = video.title;
        videoUrl = video.url;
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
      if (attemptGeminiSummary) {
        const summaryPrompt = `Résume cette vidéo YouTube en 5 étapes claires: ${videoTitle}`;
        try {
          summaryText = await generateWithGemini(summaryPrompt, 300);
        } catch (e) {
          console.warn("Gemini summary (stream) failed:", e.message);
          summaryText = heuristicSummary(videoTitle);
        }
      } else {
        summaryText = heuristicSummary(videoTitle);
      }

      const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
      for (const s of steps) {
        writeEvent({ type: "partial", step: s });
        await new Promise(r => setTimeout(r, 160));
      }
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

export function createApp() {
  return app;
}

// Only start server if run directly (not when imported for tests)
// Use URL-safe comparison to handle paths with spaces (e.g., "app howto")
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Project: ${process.env.PROJECT_ID || 'unknown'}`);
    console.log(`Mock mode: ${(process.env.MOCK_MODE || 'true') === 'true' ? 'enabled' : 'disabled'}`);
    console.log(`Gemini: ${USE_GEMINI_ENV ? `enabled (${GEMINI_MODEL}, timeout=${GEMINI_TIMEOUT_MS}ms)` : 'disabled'}`);
    console.log(`YouTube API key: ${process.env.YT_API_KEY ? 'present' : 'missing'}`);
  });
}