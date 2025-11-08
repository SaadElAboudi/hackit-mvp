import { sortBy } from 'lodash';

/**
 * Rank videos based on views, likes, and relevance.
 * @param {Array} videos - Array of video objects to rank.
 * @returns {Array} - Ranked array of videos.
 */
export const rankVideos = (videos) => {
  return sortBy(videos, [
    (video) => -video.statistics.viewCount, // Sort by views descending
    (video) => -video.statistics.likeCount, // Sort by likes descending
    (video) => video.snippet.title, // Sort by title alphabetically
  ]);
};