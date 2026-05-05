import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

import axios from 'axios';

import {
    normalizeSlackChannelId,
    buildSlackShareText,
    postSlackMessage,
} from '../src/services/slack.js';

// ── normalizeSlackChannelId ───────────────────────────────────────────────────

test('normalizeSlackChannelId trims whitespace', () => {
    assert.equal(normalizeSlackChannelId('  C012AB3CD  '), 'C012AB3CD');
});

test('normalizeSlackChannelId handles empty input gracefully', () => {
    assert.equal(normalizeSlackChannelId(''), '');
    assert.equal(normalizeSlackChannelId(null), '');
    assert.equal(normalizeSlackChannelId(undefined), '');
});

// ── buildSlackShareText ───────────────────────────────────────────────────────

test('buildSlackShareText includes room name and summary', () => {
    const text = buildSlackShareText({
        roomName: 'Projet Alpha',
        summary: 'R\u00e9vision du budget approuv\u00e9e par l\'\u00e9quipe.',
    });
    assert.ok(text.includes('Projet Alpha'), 'should include room name');
    assert.ok(text.includes('Révision du budget'), 'should include summary excerpt');
});

test('buildSlackShareText includes optional note when provided', () => {
    const text = buildSlackShareText({
        roomName: 'Channel',
        summary: 'Décision prise.',
        note: 'Pour vérification avant 18h.',
    });
    assert.ok(text.includes('Pour vérification avant 18h.'), 'note should be included');
});

test('buildSlackShareText does not exceed 3900 chars for long content', () => {
    const text = buildSlackShareText({
        roomName: 'A'.repeat(80),
        summary: 'B'.repeat(4000),
    });
    assert.ok(text.length <= 3900, `expected <= 3900 chars, got ${text.length}`);
});

// ── postSlackMessage ──────────────────────────────────────────────────────────

test('postSlackMessage sends correct payload to Slack API', async (t) => {
    const originalPost = axios.post;
    let capturedUrl;
    let capturedBody;
    let capturedHeaders;

    axios.post = async (url, body, config) => {
        capturedUrl = url;
        capturedBody = body;
        capturedHeaders = config?.headers;
        return { data: { ok: true, channel: 'C012AB3CD', ts: '1714000000.001' } };
    };
    t.after(() => { axios.post = originalPost; });

    const result = await postSlackMessage({
        botToken: 'xoxb-test-token',
        channelId: 'C012AB3CD',
        text: 'Hello from Hackit',
    });

    assert.match(capturedUrl, /slack.com\/api\/chat.postMessage/);
    assert.equal(capturedBody.channel, 'C012AB3CD');
    assert.equal(capturedBody.text, 'Hello from Hackit');
    assert.match(capturedHeaders?.Authorization || '', /Bearer xoxb-test-token/);
    assert.equal(result.channel, 'C012AB3CD');
    assert.equal(result.ts, '1714000000.001');
});

test('postSlackMessage throws on Slack API ok=false', async (t) => {
    const originalPost = axios.post;
    axios.post = async () => ({ data: { ok: false, error: 'channel_not_found' } });
    t.after(() => { axios.post = originalPost; });

    await assert.rejects(
        () => postSlackMessage({ botToken: 'xoxb-x', channelId: 'C000', text: 'hi' }),
        /channel_not_found/
    );
});

test('postSlackMessage throws when botToken is missing', async () => {
    await assert.rejects(
        () => postSlackMessage({ botToken: '', channelId: 'C000', text: 'hi' }),
        /Missing Slack bot token/
    );
});

test('postSlackMessage throws when channelId is missing', async () => {
    await assert.rejects(
        () => postSlackMessage({ botToken: 'xoxb-x', channelId: '', text: 'hi' }),
        /Missing Slack channel id/
    );
});

test('postSlackMessage throws when text is empty', async () => {
    await assert.rejects(
        () => postSlackMessage({ botToken: 'xoxb-x', channelId: 'C000', text: '' }),
        /Missing Slack message text/
    );
});
