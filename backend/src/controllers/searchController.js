import express from "express";

import { reformulateQuestion, generateSummary } from "../services/openai.js";
import { searchYouTube } from "../services/youtube.js";

const router = express.Router();

router.post("/search", async (req, res) => {
  const { query } = req.body || {};

  try {
    if (!query || typeof query !== "string" || !query.trim()) {
      return res.status(400).json({ message: "Missing or invalid 'query' in request body." });
    }

    // Reformulate the question for search
    const reformulatedQuery = await reformulateQuestion(query.trim());

    // Search for a video on YouTube (service returns best match object)
    const video = await searchYouTube(reformulatedQuery);

    if (!video || !video.videoId) {
      return res.status(404).json({ message: "No videos found." });
    }

    // Generate a summary for the video using its title
    const summary = await generateSummary(video.title);

    res.json({
      title: video.title,
      summary,
      videoUrl: video.url || `https://www.youtube.com/watch?v=${video.videoId}`,
      source: video.source || "youtube",
    });
  } catch (error) {
    const status = error?.status || 500;
    const message = error?.message || "An error occurred while processing your request.";
    console.error("/api/search error:", error?.response?.data || message);
    res.status(status).json({ message });
  }
});

export default router;