import express from "express";
import dotenv from "dotenv";
import cors from "cors";
import morgan from "morgan";
import searchRoutes from "./routes/search.js";

// Load environment variables
dotenv.config();

// Initialize Express app
const app = express();

// Middleware
app.use(express.json());
app.use(cors());
app.use(morgan("dev"));



app.get("/health", (req, res) => res.json({ ok: true, mock: (process.env.MOCK_MODE || "true") === "true" }));

app.post("/api/search", async (req, res) => {
  const { query } = req.body;
  if (!query) return res.status(400).json({ error: "query is required" });

  // Dev mock mode: quick responses without keys
  if ((process.env.MOCK_MODE || "true") === "true") {
    return res.json({
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
    });
  }

  try {
    let searchTerm = query;
    if (USE_GEMINI) {
      const reformPrompt = `Reformule cette question en anglais pour une recherche YouTube: "${query}"`;
      searchTerm = await generateWithGemini(reformPrompt, 128);
    }

    let videoTitle, videoUrl, source;
    if (process.env.YT_API_KEY) {
      const yt = await axios.get("https://www.googleapis.com/youtube/v3/search", {
        params: { q: searchTerm, key: process.env.YT_API_KEY, maxResults: 5, type: "video" }
      });
      const item = yt.data?.items?.[0];
      if (!item) return res.status(404).json({ error: "No video found via YouTube Data API" });
      videoTitle = item.snippet.title;
      videoUrl = `https://www.youtube.com/watch?v=${item.id.videoId}`;
      source = "youtube-api";
    } else {
      const r = await yts(searchTerm);
      const v = r?.videos?.[0];
      if (!v) return res.status(404).json({ error: "No video found via yt-search fallback" });
      videoTitle = v.title;
      videoUrl = v.url || `https://www.youtube.com/watch?v=${v.videoId}`;
      source = "yt-search-fallback";
    }

    let summaryText = "";
    if (USE_GEMINI) {
      const summaryPrompt = `Résume cette vidéo YouTube en 5 étapes claires: ${videoTitle}`;
      summaryText = await generateWithGemini(summaryPrompt, 300);
    } else {
      summaryText = "Résumé non disponible: activez USE_GEMINI=true ou set MOCK_MODE=true pour un mock.";
    }

    const steps = summaryText.split("\n").map(s => s.trim()).filter(Boolean);
    return res.json({ title: videoTitle, steps, videoUrl, source });
  } catch (err) {
    console.error("Search error:", err?.response?.data || err.message || err);
    return res.status(500).json({ error: "Internal server error", detail: err?.message || err });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));