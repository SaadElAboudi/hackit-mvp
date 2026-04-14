import test from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

import axios from 'axios';
import {
    markdownToNotionBlocks,
    validateNotionToken,
    createNotionPage,
} from '../src/services/notion.js';

// ── markdownToNotionBlocks ────────────────────────────────────────────────────

test('markdownToNotionBlocks converts h1 heading', () => {
    const blocks = markdownToNotionBlocks('# Titre principal');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, 'heading_1');
    assert.equal(blocks[0].heading_1.rich_text[0].text.content, 'Titre principal');
});

test('markdownToNotionBlocks converts h2 and h3 headings', () => {
    const blocks = markdownToNotionBlocks('## Section\n### Sous-section');
    assert.equal(blocks[0].type, 'heading_2');
    assert.equal(blocks[1].type, 'heading_3');
});

test('markdownToNotionBlocks converts bullet list items', () => {
    const blocks = markdownToNotionBlocks('- item A\n- item B');
    assert.equal(blocks.length, 2);
    assert.ok(blocks.every((b) => b.type === 'bulleted_list_item'));
    assert.equal(blocks[0].bulleted_list_item.rich_text[0].text.content, 'item A');
});

test('markdownToNotionBlocks converts numbered list items', () => {
    const blocks = markdownToNotionBlocks('1. First\n2. Second');
    assert.equal(blocks.length, 2);
    assert.ok(blocks.every((b) => b.type === 'numbered_list_item'));
});

test('markdownToNotionBlocks converts plain text as paragraph', () => {
    const blocks = markdownToNotionBlocks('Some plain text here.');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, 'paragraph');
    assert.equal(blocks[0].paragraph.rich_text[0].text.content, 'Some plain text here.');
});

test('markdownToNotionBlocks inserts divider for blank lines', () => {
    const blocks = markdownToNotionBlocks('Line A\n\nLine B');
    const types = blocks.map((b) => b.type);
    assert.ok(types.includes('divider'), 'should include a divider between paragraphs');
    assert.ok(types.includes('paragraph'));
});

test('markdownToNotionBlocks does not start or end with divider', () => {
    const blocks = markdownToNotionBlocks('\n\nContent\n\n');
    assert.notEqual(blocks[0]?.type, 'divider', 'should not start with divider');
    assert.notEqual(blocks[blocks.length - 1]?.type, 'divider', 'should not end with divider');
});

test('markdownToNotionBlocks caps output at 95 blocks', () => {
    const lines = Array.from({ length: 200 }, (_, i) => `Line ${i}`).join('\n');
    const blocks = markdownToNotionBlocks(lines);
    assert.ok(blocks.length <= 95, `expected <= 95 blocks, got ${blocks.length}`);
});

test('markdownToNotionBlocks handles empty string gracefully', () => {
    assert.deepEqual(markdownToNotionBlocks(''), []);
    assert.deepEqual(markdownToNotionBlocks(null), []);
});

// ── validateNotionToken ───────────────────────────────────────────────────────

test('validateNotionToken calls Notion search endpoint with bearer token', async (t) => {
    const originalPost = axios.post;
    let capturedHeaders;
    axios.post = async (_url, _body, config) => {
        capturedHeaders = config?.headers;
        return { data: { results: [] } };
    };
    t.after(() => { axios.post = originalPost; });

    const result = await validateNotionToken('secret_abc123');
    assert.match(capturedHeaders?.Authorization || '', /Bearer secret_abc123/);
    assert.equal(result.ok, true);
});

test('validateNotionToken throws on missing token', async () => {
    await assert.rejects(
        () => validateNotionToken(''),
        /Missing Notion API token/
    );
});

test('validateNotionToken propagates Notion API errors', async (t) => {
    const originalPost = axios.post;
    const err = Object.assign(new Error('unauthorized'), {
        response: { status: 401, data: { code: 'unauthorized', message: 'API token invalid.' } },
    });
    axios.post = async () => { throw err; };
    t.after(() => { axios.post = originalPost; });

    await assert.rejects(
        () => validateNotionToken('secret_bad'),
        /Notion token validation failed/
    );
});

// ── createNotionPage ──────────────────────────────────────────────────────────

test('createNotionPage posts correct payload to Notion API', async (t) => {
    const originalPost = axios.post;
    let capturedBody;
    let capturedHeaders;
    axios.post = async (_url, body, config) => {
        capturedBody = body;
        capturedHeaders = config?.headers;
        return { data: { id: 'page-id-xyz', url: 'https://notion.so/page-id-xyz' } };
    };
    t.after(() => { axios.post = originalPost; });

    const result = await createNotionPage({
        apiToken: 'secret_tok',
        parentPageId: 'parent-page-abc',
        title: 'Test Export',
        markdown: '# Title\n\n- Point A\n- Point B',
    });

    assert.equal(capturedBody.parent.page_id, 'parent-page-abc');
    assert.equal(capturedBody.properties.title.title[0].text.content, 'Test Export');
    assert.ok(Array.isArray(capturedBody.children), 'children should be an array of blocks');
    assert.ok(capturedBody.children.length > 0, 'children should be non-empty');
    assert.match(capturedHeaders?.Authorization || '', /Bearer secret_tok/);
    assert.equal(result.pageId, 'page-id-xyz');
    assert.equal(result.url, 'https://notion.so/page-id-xyz');
});

test('createNotionPage throws when apiToken is missing', async () => {
    await assert.rejects(
        () => createNotionPage({ apiToken: '', parentPageId: 'p', title: 't', markdown: 'm' }),
        /Missing Notion API token/
    );
});

test('createNotionPage throws when parentPageId is missing', async () => {
    await assert.rejects(
        () => createNotionPage({ apiToken: 'secret_x', parentPageId: '', title: 't', markdown: 'm' }),
        /Missing Notion parent page ID/
    );
});

test('createNotionPage propagates Notion API errors with code', async (t) => {
    const originalPost = axios.post;
    const err = Object.assign(new Error('object_not_found'), {
        response: { status: 404, data: { code: 'object_not_found', message: 'Page not found.' } },
    });
    axios.post = async () => { throw err; };
    t.after(() => { axios.post = originalPost; });

    await assert.rejects(
        () => createNotionPage({
            apiToken: 'secret_x',
            parentPageId: 'bad-page',
            title: 't',
            markdown: 'm',
        }),
        /Notion page creation failed/
    );
});
