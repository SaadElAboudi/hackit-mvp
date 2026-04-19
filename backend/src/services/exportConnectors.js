import { buildSlackShareText, postSlackMessage } from './slack.js';
import { createNotionPage } from './notion.js';

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

export function shouldRetryExportError(err) {
    const status = Number(err?.status || err?.statusCode || err?.response?.status || 0);
    const code = String(err?.code || '').toLowerCase();

    if ([429, 500, 502, 503, 504].includes(status)) return true;
    if (code === 'ratelimited' || code === 'rate_limited') return true;
    if (['etimedout', 'econnreset', 'ecanceled', 'enotfound', 'eai_again'].includes(code)) {
        return true;
    }
    return false;
}

export async function executeWithRetry(operation, options = {}) {
    const maxAttempts = Math.max(1, Number(options.maxAttempts || 3));
    const baseDelayMs = Math.max(50, Number(options.baseDelayMs || 200));

    let attempts = 0;
    let lastError = null;

    while (attempts < maxAttempts) {
        attempts += 1;
        try {
            const result = await operation({ attempt: attempts });
            return { result, attempts };
        } catch (err) {
            lastError = err;
            if (attempts >= maxAttempts || !shouldRetryExportError(err)) {
                break;
            }
            await sleep(baseDelayMs * attempts);
        }
    }

    if (lastError) {
        lastError.retries = Math.max(0, attempts - 1);
    }
    throw lastError;
}

async function shareToSlack({ room, integration, summary, note = '' }) {
    const text = buildSlackShareText({ roomName: room.name, summary, note });
    const sent = await postSlackMessage({
        botToken: integration.botToken,
        channelId: integration.channelId,
        text,
    });

    return {
        target: 'slack',
        externalId: String(sent.ts || ''),
        externalUrl: '',
        metadata: { channel: sent.channel || '' },
    };
}

async function shareToNotion({ integration, room, summary, note = '' }) {
    const title = `Hackit - ${String(room.name || 'Salon').slice(0, 120)}`;
    const markdown = [
        `# ${title}`,
        '',
        note ? `> Note: ${note}` : '',
        '',
        summary,
    ]
        .filter(Boolean)
        .join('\n');

    const page = await createNotionPage({
        apiToken: integration.apiToken,
        parentPageId: integration.parentPageId,
        title,
        markdown,
    });

    return {
        target: 'notion',
        externalId: String(page.pageId || ''),
        externalUrl: String(page.url || ''),
        metadata: null,
    };
}

export function getExportConnector(target) {
    const normalized = String(target || '').trim().toLowerCase();
    if (normalized === 'slack') {
        return {
            target: 'slack',
            isConfigured: (room) => {
                const slack = room?.integrations?.slack || {};
                return Boolean(slack.enabled && String(slack.botToken || '').trim());
            },
            send: ({ room, summary, note }) => {
                const slack = room?.integrations?.slack || {};
                return shareToSlack({ room, integration: slack, summary, note });
            },
        };
    }

    if (normalized === 'notion') {
        return {
            target: 'notion',
            isConfigured: (room) => {
                const notion = room?.integrations?.notion || {};
                return Boolean(notion.enabled && String(notion.apiToken || '').trim());
            },
            send: ({ room, summary, note }) => {
                const notion = room?.integrations?.notion || {};
                return shareToNotion({ room, integration: notion, summary, note });
            },
        };
    }

    return null;
}
