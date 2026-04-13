import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

const { buildSynthesisSuggestion } = await import('../src/services/roomOrchestrator.js');

await test('buildSynthesisSuggestion includes key sections and clipped lines', () => {
    const out = buildSynthesisSuggestion({
        roomName: 'Produit',
        lines: [
            'Le client veut un plan clair pour la semaine prochaine.',
            'On doit valider le scope et les risques avant mardi.',
            'Le budget est sensible, prioriser le MUST.',
            'Ajouter un owner par action.',
        ],
    });

    assert.match(out, /Suggestion de synth[èe]se/i);
    assert.match(out, /Points saillants détectés/);
    assert.match(out, /Prochaines actions proposées/);
    assert.match(out, /\/decide/);
    assert.match(out, /\/doc/);
});

await test('buildSynthesisSuggestion falls back gracefully with no lines', () => {
    const out = buildSynthesisSuggestion({ roomName: 'Ops', lines: [] });
    assert.match(out, /Peu de signaux exploitables/);
    assert.match(out, /Prochaines actions proposées/);
});
