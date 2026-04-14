import axios from 'axios';

const NOTION_API_VERSION = '2022-06-28';
const NOTION_PAGES_URL = 'https://api.notion.com/v1/pages';
const NOTION_SEARCH_URL = 'https://api.notion.com/v1/search';

// ── Markdown → Notion block helpers ──────────────────────────────────────────

function richText(content) {
    return [{ type: 'text', text: { content: String(content || '').slice(0, 2000) } }];
}

function headingBlock(level, text) {
    const type = level === 1 ? 'heading_1' : level === 2 ? 'heading_2' : 'heading_3';
    return { object: 'block', type, [type]: { rich_text: richText(text) } };
}

function paragraphBlock(text) {
    return { object: 'block', type: 'paragraph', paragraph: { rich_text: richText(text) } };
}

function bulletBlock(text) {
    return {
        object: 'block',
        type: 'bulleted_list_item',
        bulleted_list_item: { rich_text: richText(text) },
    };
}

function numberedBlock(text) {
    return {
        object: 'block',
        type: 'numbered_list_item',
        numbered_list_item: { rich_text: richText(text) },
    };
}

function dividerBlock() {
    return { object: 'block', type: 'divider', divider: {} };
}

/**
 * Convert a markdown string into Notion block objects.
 * Handles: # headings, - bullets, 1. numbered, blank lines → divider,
 * regular text → paragraph. Max 95 blocks (Notion API limit per request).
 */
export function markdownToNotionBlocks(markdown) {
    const lines = String(markdown || '').split('\n');
    const blocks = [];

    for (const raw of lines) {
        if (blocks.length >= 95) break;

        const line = raw.trimEnd();

        if (!line.trim()) {
            // Only add divider if we're not at the start or after another divider
            if (blocks.length > 0 && blocks[blocks.length - 1]?.type !== 'divider') {
                blocks.push(dividerBlock());
            }
            continue;
        }

        const h1 = line.match(/^#\s+(.+)/);
        if (h1) { blocks.push(headingBlock(1, h1[1])); continue; }

        const h2 = line.match(/^##\s+(.+)/);
        if (h2) { blocks.push(headingBlock(2, h2[1])); continue; }

        const h3 = line.match(/^###\s+(.+)/);
        if (h3) { blocks.push(headingBlock(3, h3[1])); continue; }

        const bullet = line.match(/^[-*]\s+(.+)/);
        if (bullet) { blocks.push(bulletBlock(bullet[1])); continue; }

        const numbered = line.match(/^\d+\.\s+(.+)/);
        if (numbered) { blocks.push(numberedBlock(numbered[1])); continue; }

        blocks.push(paragraphBlock(line));
    }

    // Remove trailing divider if any
    if (blocks.length > 0 && blocks[blocks.length - 1]?.type === 'divider') {
        blocks.pop();
    }

    return blocks;
}

// ── Token validation ──────────────────────────────────────────────────────────

export async function validateNotionToken(apiToken) {
    const token = String(apiToken || '').trim();
    if (!token) throw new Error('Missing Notion API token');

    try {
        const resp = await axios.post(
            NOTION_SEARCH_URL,
            { query: '', page_size: 1 },
            {
                headers: notionHeaders(token),
                timeout: 8_000,
            }
        );
        // Notion returns 200 even with no results — just need ok status
        return { ok: true, resultsCount: resp.data?.results?.length ?? 0 };
    } catch (err) {
        const status = err?.response?.status;
        const notionMsg = err?.response?.data?.message || err.message;
        const notionCode = err?.response?.data?.code || 'network_error';
        const e = new Error(`Notion token validation failed (${status ?? 'network'}): ${notionMsg}`);
        e.code = notionCode;
        throw e;
    }
}

// ── Page creation ─────────────────────────────────────────────────────────────

function notionHeaders(token) {
    return {
        Authorization: `Bearer ${token}`,
        'Notion-Version': NOTION_API_VERSION,
        'Content-Type': 'application/json',
    };
}

/**
 * Create a Notion page under parentPageId with a title and markdown body.
 * Returns { pageId, url }.
 */
export async function createNotionPage({ apiToken, parentPageId, title, markdown, emoji = '📄' }) {
    const token = String(apiToken || '').trim();
    const parent = String(parentPageId || '').trim();
    const pageTitle = String(title || 'Hackit Export').trim().slice(0, 200);

    if (!token) throw new Error('Missing Notion API token');
    if (!parent) throw new Error('Missing Notion parent page ID');

    const blocks = markdownToNotionBlocks(markdown);

    const body = {
        parent: { type: 'page_id', page_id: parent },
        icon: { type: 'emoji', emoji },
        properties: {
            title: {
                title: [{ type: 'text', text: { content: pageTitle } }],
            },
        },
        children: blocks,
    };

    let resp;
    try {
        resp = await axios.post(NOTION_PAGES_URL, body, {
            headers: notionHeaders(token),
            timeout: 15_000,
        });
    } catch (err) {
        const status = err?.response?.status;
        const notionMsg = err?.response?.data?.message || err.message;
        const notionCode = err?.response?.data?.code || 'notion_error';
        const e = new Error(`Notion page creation failed (${status ?? 'network'}): ${notionMsg}`);
        e.code = notionCode;
        throw e;
    }

    return {
        pageId: resp.data.id,
        url: resp.data.url,
    };
}
