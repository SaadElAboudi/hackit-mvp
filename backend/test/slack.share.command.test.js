import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

import { parseRoomCommand } from '../src/services/roomOrchestrator.js';

test('parseRoomCommand recognizes /share slack', () => {
    const result = parseRoomCommand('/share slack pour l\'\u00e9quipe prod');
    assert.equal(result.kind, 'share');
    assert.ok(result.prompt.startsWith('slack'), 'prompt should start with the provider');
});

test('parseRoomCommand recognizes /share without provider', () => {
    const result = parseRoomCommand('/share');
    assert.equal(result.kind, 'share');
    assert.equal(result.prompt, '');
});

test('parseRoomCommand /share is case-insensitive', () => {
    assert.equal(parseRoomCommand('/SHARE Slack').kind, 'share');
});

test('parseRoomCommand does not change other command kinds', () => {
    assert.equal(parseRoomCommand('/doc note').kind, 'doc');
    assert.equal(parseRoomCommand('/decide sujet').kind, 'decide');
    assert.equal(parseRoomCommand('/brief').kind, 'brief');
    assert.equal(parseRoomCommand('/search query').kind, 'search');
});
