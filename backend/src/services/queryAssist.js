function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .map((x) => x.trim())
    .filter((x) => x.length >= 3);
}

export function analyzeQuery(query) {
  const cleaned = String(query || '').trim();
  const words = tokenize(cleaned);
  const isQuestion = /[?]|^(how|what|why|when|where|comment|pourquoi|quoi)\b/i.test(cleaned);
  const complexity = words.length >= 10 ? 'high' : words.length >= 5 ? 'medium' : 'low';
  const recommendedSummaryLength = complexity === 'high' ? 'deep' : complexity === 'low' ? 'tldr' : 'standard';
  const needsClarification = !isQuestion && words.length < 3;

  return {
    complexity,
    recommendedSummaryLength,
    needsClarification,
    hints: needsClarification
      ? ['Try describing your goal and expected outcome in one sentence.']
      : ['Include tools/context for better steps.', 'Ask as a question for more precise guidance.'],
  };
}

export function buildSearchSuggestions({ query, relatedQueries = [], recentQueries = [], max = 6 }) {
  const base = String(query || '').trim();
  const out = [];
  const pushUnique = (value) => {
    const v = String(value || '').trim();
    if (!v) return;
    if (out.some((item) => item.toLowerCase() === v.toLowerCase())) return;
    out.push(v);
  };

  relatedQueries.forEach(pushUnique);
  recentQueries.forEach(pushUnique);

  if (base) {
    pushUnique(`${base} for beginners`);
    pushUnique(`${base} checklist`);
    pushUnique(`${base} common mistakes`);
  }

  return out.slice(0, max);
}
