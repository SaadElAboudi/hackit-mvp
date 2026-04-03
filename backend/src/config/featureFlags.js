const DEFAULT_FLAGS = {
  searchStreaming: true,
  searchFeedback: true,
  recommendations: true,
  multiLengthSummary: true,
  observability: true,
};

function parseBoolean(value, fallback) {
  if (value === undefined) return fallback;
  return String(value).toLowerCase() === 'true';
}

export function getFeatureFlags() {
  return {
    searchStreaming: parseBoolean(process.env.FLAG_SEARCH_STREAMING, DEFAULT_FLAGS.searchStreaming),
    searchFeedback: parseBoolean(process.env.FLAG_SEARCH_FEEDBACK, DEFAULT_FLAGS.searchFeedback),
    recommendations: parseBoolean(process.env.FLAG_RECOMMENDATIONS, DEFAULT_FLAGS.recommendations),
    multiLengthSummary: parseBoolean(process.env.FLAG_MULTI_LENGTH_SUMMARY, DEFAULT_FLAGS.multiLengthSummary),
    observability: parseBoolean(process.env.FLAG_OBSERVABILITY, DEFAULT_FLAGS.observability),
  };
}
