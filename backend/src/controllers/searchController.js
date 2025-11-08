import express from "express";
import { reformulateQuestion } from "../services/openai.js";
import { searchYouTube } from "../services/youtube.js";
import { rankVideos } from "../utils/ranker.js";

const router = express.Router();

router.post("/search", async (req, res) => {
  const { query } = req.body;

  try {
    // Reformulate the question for search
    const reformulatedQuery = await reformulateQuestion(query);

    // Search for videos on YouTube
    const videos = await searchYouTube(reformulatedQuery);

    // Rank the videos based on views and relevance
    const rankedVideos = rankVideos(videos);

    if (rankedVideos.length === 0) {
      return res.status(404).json({ message: "No videos found." });
    }

    // Get the best video
    const bestVideo = rankedVideos[0];

    // Generate a summary for the best video
    const summary = await generateSummary(bestVideo.id);

    res.json({
      title: bestVideo.title,
      summary: summary,
      videoUrl: `https://www.youtube.com/watch?v=${bestVideo.id}`,
      source: "YouTube"
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: "An error occurred while processing your request." });
  }
});

export default router;