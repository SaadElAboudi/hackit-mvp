import axios from "axios";

const YOUTUBE_API_URL = "https://www.googleapis.com/youtube/v3/search";
const DEFAULT_MAX_RESULTS = 5;
const MAX_ALLOWED_RESULTS = 50;

export const normalizeSearchYouTubeOptions = (options = {}) => {
  const requestedMaxResults = Number.parseInt(options.maxResults, 10);
  const maxResults = Number.isInteger(requestedMaxResults)
    ? Math.min(Math.max(requestedMaxResults, 1), MAX_ALLOWED_RESULTS)
    : DEFAULT_MAX_RESULTS;
  const pageToken = typeof options.pageToken === "string" && options.pageToken.trim()
    ? options.pageToken.trim()
    : undefined;

  return { maxResults, pageToken };
};

/**
 * Search YouTube using the official API
 * @param {string} query - Search query
 * @param {string} apiKey - YouTube API key
 * @returns {Promise<{ items: Array, nextPageToken: string | null }>} - API search results
 */
export const searchYouTubeAPI = async (query, apiKey, options = {}) => {
  const normalizedOptions = normalizeSearchYouTubeOptions(options);

  try {
    const response = await axios.get(YOUTUBE_API_URL, {
      params: {
        part: "snippet",
        q: query,
        key: apiKey,
        maxResults: normalizedOptions.maxResults,
        pageToken: normalizedOptions.pageToken,
        type: "video",
        relevanceLanguage: process.env.YT_RELEVANCE_LANG || "fr",
        regionCode: process.env.YT_REGION_CODE || "FR",
        safeSearch: process.env.YT_SAFE_SEARCH || "none",
      },
    });
    return { items: response.data.items || [], nextPageToken: response.data.nextPageToken || null };
  } catch (error) {
    console.error("Error fetching videos from YouTube API:", error?.response?.data || error.message);
    const err = new Error("Could not fetch videos from YouTube API");
    err.code = "YOUTUBE_API_ERROR";
    err.status = 502;
    throw err;
  }
};

/**
 * Search YouTube using yt-search fallback
 * @param {string} query - Search query
 * @returns {Promise<Object>} - Video object with title and URL
 */
export const searchYouTubeFallback = async (query, options = {}) => {
  const normalizedOptions = normalizeSearchYouTubeOptions(options);

  try {
    const { default: yts } = await import("yt-search");
    const result = await yts(query);
    const videos = (result?.videos || []).slice(0, normalizedOptions.maxResults);
    const video = videos[0];

    if (!video) {
      throw new Error("No video found via yt-search fallback");
    }

    return {
      title: video.title,
      url: video.url || `https://www.youtube.com/watch?v=${video.videoId}`,
      videoId: video.videoId,
      alternatives: videos.map((item) => ({
        title: item.title,
        url: item.url || `https://www.youtube.com/watch?v=${item.videoId}`,
        videoId: item.videoId,
        source: "yt-search-fallback",
      })),
      nextPageToken: null,
    };
  } catch (error) {
    console.error("Error with yt-search fallback:", error.message);
    const err = new Error(error.message || "yt-search fallback error");
    err.code = "YOUTUBE_FALLBACK_ERROR";
    err.status = 502;
    throw err;
  }
};

/**
 * Search YouTube - tries API first, falls back to yt-search (Node >= 20)
 * @param {string} query - Search query
 * @returns {Promise<Object>} - Video object with title, url, and source
 */
export const searchYouTube = async (query, options = {}) => {
  const YT_API_KEY = process.env.YT_API_KEY;
  const nodeMajor = Number(process.versions?.node?.split(".")[0] || 0);
  const canUseFallback = nodeMajor >= 20;

  try {
    if (YT_API_KEY) {
      try {
        const { items, nextPageToken } = await searchYouTubeAPI(query, YT_API_KEY, options);
        const item = items?.[0];

        if (!item) {
          console.log("No results from YouTube API for query:", query);
          if (canUseFallback) {
            console.log("Falling back to yt-search (Node>=20)");
            const video = await searchYouTubeFallback(query, options);
            return { ...video, source: "yt-search-fallback" };
          }
          const err = new Error("No video found via YouTube Data API");
          err.code = "YOUTUBE_NO_RESULTS";
          err.status = 404;
          throw err;
        }

        return {
          title: item.snippet.title,
          url: `https://www.youtube.com/watch?v=${item.id.videoId}`,
          videoId: item.id.videoId,
          source: "youtube-api",
          alternatives: items.map((videoItem) => ({
            title: videoItem.snippet.title,
            url: `https://www.youtube.com/watch?v=${videoItem.id.videoId}`,
            videoId: videoItem.id.videoId,
            source: "youtube-api",
          })),
          nextPageToken,
        };
      } catch (apiError) {
        if (canUseFallback) {
          console.log("YouTube API error, falling back to yt-search (Node>=20):", apiError.message);
          const video = await searchYouTubeFallback(query, options);
          return { ...video, source: "yt-search-fallback" };
        }
        console.log(
          "YouTube API error and fallback unavailable on Node",
          process.versions?.node,
          "-> returning 502"
        );
        const err = new Error(
          "YouTube API failed and fallback requires Node 20+. Provide a valid YT_API_KEY or upgrade Node to v20+."
        );
        err.code = "YOUTUBE_FALLBACK_UNAVAILABLE";
        err.status = 502;
        throw err;
      }
    } else {
      if (canUseFallback) {
        console.log("No YouTube API key found, using yt-search (Node>=20)");
        const video = await searchYouTubeFallback(query, options);
        return { ...video, source: "yt-search-fallback" };
      }
      console.log(
        "No YouTube API key and fallback unavailable on Node",
        process.versions?.node,
        "-> returning 502"
      );
      const err = new Error(
        "Missing YT_API_KEY and fallback requires Node 20+. Set YT_API_KEY or upgrade Node to v20+."
      );
      err.code = "YOUTUBE_CONFIG_ERROR";
      err.status = 502;
      throw err;
    }
  } catch (error) {
    console.error("YouTube search error:", error.message);
    throw error;
  }
};
