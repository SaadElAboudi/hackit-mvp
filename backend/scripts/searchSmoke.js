import dotenv from 'dotenv';
dotenv.config();

import { reformulateQuestion, generateSummary } from "../src/services/gemini.js";
import { searchYouTube } from "../src/services/youtube.js";

const run = async () => {
    const query = process.argv[2] || "how to clean a fridge";

    const USE_GEMINI = (process.env.USE_GEMINI || "false") === "true";
    console.log(`Query: ${query}`);
    console.log(`USE_GEMINI=${USE_GEMINI}`);

    let reformulated = query;
    try {
        reformulated = await reformulateQuestion(query);
    } catch (e) {
        console.warn("Reformulation failed, using original:", e.message);
        reformulated = query;
    }

    const video = await searchYouTube(reformulated);
    let summary = "Résumé non disponible";
    try {
        summary = await generateSummary(video.title);
    } catch (e) {
        console.warn("Summary generation failed:", e.message);
    }

    const steps = summary
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean)
        .map((s) => s.replace(/^\d+\.\s*/, ""));

    const result = {
        title: video.title,
        videoUrl: video.url,
        source: video.source,
        steps,
        reformulated: reformulated !== query,
    };

    console.log(JSON.stringify(result, null, 2));
};

run().catch((e) => {
    console.error("Smoke test error:", e?.response?.data || e.message || e);
    process.exit(1);
});
