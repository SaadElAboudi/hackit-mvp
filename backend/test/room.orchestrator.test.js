import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

const {
  buildRoomTrustCard,
  buildTranscriptCitations,
  inferMissionAgentType,
  parseRoomCommand,
  resolveMissionAgentProfile,
  normalizeMissionAgentType,
} = await import('../src/services/roomOrchestrator.js');

await test('parseRoomCommand recognizes shared AI triggers', async () => {
  assert.deepEqual(parseRoomCommand('/doc Crée un brief').kind, 'doc');
  assert.deepEqual(parseRoomCommand('/mission Prépare une note').kind, 'mission');
  assert.deepEqual(parseRoomCommand('/search benchmark copilots').kind, 'search');
  assert.deepEqual(parseRoomCommand('/decide on tranche le scope').kind, 'decide');
  assert.deepEqual(parseRoomCommand('@ia aide-nous à cadrer').kind, 'ai');
  assert.deepEqual(parseRoomCommand('message simple').kind, 'none');
});

await test('buildTranscriptCitations converts transcript snippets to deep links', async () => {
  const citations = buildTranscriptCitations({
    videoUrl: 'https://www.youtube.com/watch?v=abc123',
    transcript: [
      { startSec: 12, text: 'Premier extrait utile pour l’équipe.' },
      { startSec: 42, text: 'Deuxième extrait utile pour vérifier une hypothèse.' },
    ],
    max: 2,
  });

  assert.equal(citations.length, 2);
  assert.equal(citations[0].startSec, 12);
  assert.match(citations[0].url, /[?&]t=12/);
  assert.equal(citations[0].endSec, 42);
  assert.ok(citations[1].quote.includes('Deuxième extrait utile'));
});

await test('normalizeMissionAgentType accepts only supported mission agents', async () => {
  assert.equal(normalizeMissionAgentType('writer'), 'writer');
  assert.equal(normalizeMissionAgentType('STRATEGIST'), 'strategist');
  assert.equal(normalizeMissionAgentType('unknown'), 'auto');
});

await test('inferMissionAgentType detects specialist from prompt intent', async () => {
  assert.equal(inferMissionAgentType('Prépare une stratégie go-to-market'), 'strategist');
  assert.equal(inferMissionAgentType('Fais un benchmark concurrentiel sourcé'), 'researcher');
  assert.equal(inferMissionAgentType('Prépare un agenda de réunion et décisions à trancher'), 'facilitator');
  assert.equal(inferMissionAgentType('Analyse les KPI de rétention'), 'analyst');
  assert.equal(inferMissionAgentType('Rédige une note de cadrage client'), 'writer');
});

await test('resolveMissionAgentProfile honors explicit agent type over inference', async () => {
  const profile = resolveMissionAgentProfile({
    prompt: 'Prépare un benchmark concurrentiel',
    agentType: 'writer',
  });

  assert.equal(profile.type, 'writer');
  assert.equal(profile.label, 'Writer');
});

await test('buildRoomTrustCard returns explainability payload with expected sections', async () => {
  const trust = buildRoomTrustCard({
    mode: 'mission',
    prompt: 'Lancer une nouvelle offre B2B',
    room: { name: 'Growth Lab', purpose: 'Go to market Q3' },
    context: {
      messages: [{}, {}, {}, {}, {}, {}],
      memories: [{}],
      artifacts: [{}],
    },
  });

  assert.equal(typeof trust.whyThisPlan, 'string');
  assert.ok(trust.whyThisPlan.length > 0);
  assert.ok(Array.isArray(trust.assumptions) && trust.assumptions.length > 0);
  assert.ok(Array.isArray(trust.limits) && trust.limits.length > 0);
  assert.equal(trust.confidence, 'eleve');
});

await test('buildRoomTrustCard lowers confidence when context is sparse', async () => {
  const trust = buildRoomTrustCard({
    mode: 'ai',
    prompt: 'Aider a prioriser',
    room: { name: 'Ops' },
    context: {
      messages: [{}, {}],
      memories: [],
      artifacts: [],
    },
  });

  assert.equal(trust.confidence, 'faible');
  assert.match(trust.whyThisPlan, /Ops|prioriser/i);
});
