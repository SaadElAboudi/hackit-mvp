import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

const { buildMeetingBrief } = await import('../src/services/roomOrchestrator.js');

await test('buildMeetingBrief outputs expected pre-meeting sections', () => {
    const out = buildMeetingBrief({
        roomName: 'Produit',
        objective: 'Préparer la réunion client de lundi',
        lines: [
            'Le client veut valider le scope MVP.',
            'On doit confirmer les risques de délai.',
            'Besoin d un owner clair pour chaque action.',
        ],
    });

    assert.match(out, /Brief automatique avant réunion/i);
    assert.match(out, /Objectif du point/);
    assert.match(out, /Décisions à trancher/);
    assert.match(out, /Questions critiques/);
    assert.match(out, /\/decide/);
    assert.match(out, /\/doc/);
});

await test('buildMeetingBrief has graceful fallback when lines are empty', () => {
    const out = buildMeetingBrief({ roomName: 'Ops', lines: [], objective: '' });
    assert.match(out, /Aucun signal clair détecté/);
    assert.match(out, /Prochaine étape/);
});
