import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

const {
  buildTranscriptCitations,
  parseRoomCommand,
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
