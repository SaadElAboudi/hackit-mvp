import axios from 'axios';

const SLACK_POST_MESSAGE_URL = 'https://slack.com/api/chat.postMessage';

export function normalizeSlackChannelId(value) {
    return String(value || '').trim();
}

export function buildSlackShareText({ roomName, summary, note = '' }) {
    const room = String(roomName || 'Channel').trim();
    const body = String(summary || '').trim();
    const extra = String(note || '').trim();
    const lines = [`*${room}* — partage Hackit`];
    if (extra) lines.push(extra);
    if (body) lines.push('', body);
    return lines.join('\n').slice(0, 3900);
}

export async function postSlackMessage({ botToken, channelId, text }) {
    const token = String(botToken || '').trim();
    const channel = normalizeSlackChannelId(channelId);
    const payload = String(text || '').trim();

    if (!token) throw new Error('Missing Slack bot token');
    if (!channel) throw new Error('Missing Slack channel id');
    if (!payload) throw new Error('Missing Slack message text');

    const response = await axios.post(
        SLACK_POST_MESSAGE_URL,
        {
            channel,
            text: payload,
            mrkdwn: true,
            unfurl_links: false,
            unfurl_media: false,
        },
        {
            headers: {
                Authorization: `Bearer ${token}`,
                'Content-Type': 'application/json; charset=utf-8',
            },
            timeout: 10_000,
        }
    );

    if (!response?.data?.ok) {
        const slackError = response?.data?.error || 'unknown_slack_error';
        const err = new Error(`Slack API error: ${slackError}`);
        err.code = slackError;
        throw err;
    }

    return {
        channel: response.data.channel,
        ts: response.data.ts,
    };
}
