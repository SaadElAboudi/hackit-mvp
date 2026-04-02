export function normalizeLearningPreferences({ tone, expertiseLevel } = {}) {
  const normalizedTone = tone === undefined ? 'practical' : String(tone).trim().toLowerCase();
  const normalizedLevel = expertiseLevel === undefined ? 'intermediate' : String(expertiseLevel).trim().toLowerCase();
  return {
    tone: ['practical', 'friendly', 'coach'].includes(normalizedTone) ? normalizedTone : 'practical',
    expertiseLevel: ['beginner', 'intermediate', 'advanced'].includes(normalizedLevel) ? normalizedLevel : 'intermediate',
  };
}

export function buildLearningPath({ steps = [], expertiseLevel = 'intermediate' } = {}) {
  const introByLevel = {
    beginner: 'Start simple and focus on fundamentals before speed.',
    intermediate: 'Focus on execution quality and consistency.',
    advanced: 'Optimize technique, efficiency, and edge cases.',
  };
  const checkpoints = steps.slice(0, 5).map((step, index) => ({
    id: `checkpoint-${index + 1}`,
    title: `Checkpoint ${index + 1}`,
    action: String(step || '').trim(),
    completed: false,
  }));
  return {
    level: expertiseLevel,
    intro: introByLevel[expertiseLevel] || introByLevel.intermediate,
    checkpoints,
  };
}

export function buildNextActions({ videoId, videoUrl, relatedQueries = [] } = {}) {
  const actions = [];
  if (videoId) {
    actions.push({ type: 'open_transcript', label: 'Open transcript', endpoint: `/api/transcript?videoId=${encodeURIComponent(videoId)}` });
    actions.push({ type: 'open_chapters', label: 'Open chapters', endpoint: `/api/chapters?videoId=${encodeURIComponent(videoId)}` });
  }
  if (videoUrl) {
    actions.push({ type: 'watch_video', label: 'Watch video', url: videoUrl });
  }
  if (relatedQueries.length > 0) {
    actions.push({ type: 'explore_related', label: 'Explore related topic', query: relatedQueries[0] });
  }
  return actions;
}
