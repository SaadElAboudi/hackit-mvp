import test from 'node:test';
import assert from 'node:assert/strict';

import axios from 'axios';

import {
  normalizeSearchYouTubeOptions,
  searchYouTubeAPI,
  searchYouTube,
} from '../src/services/youtube.js';

test('normalizeSearchYouTubeOptions sanitizes maxResults and pageToken', () => {
  assert.deepEqual(normalizeSearchYouTubeOptions(), { maxResults: 5, pageToken: undefined });
  assert.deepEqual(
    normalizeSearchYouTubeOptions({ maxResults: '3', pageToken: '  next-page  ' }),
    { maxResults: 3, pageToken: 'next-page' }
  );
  assert.deepEqual(
    normalizeSearchYouTubeOptions({ maxResults: 0, pageToken: '   ' }),
    { maxResults: 1, pageToken: undefined }
  );
  assert.deepEqual(normalizeSearchYouTubeOptions({ maxResults: 999 }), { maxResults: 50, pageToken: undefined });
  assert.deepEqual(normalizeSearchYouTubeOptions({ maxResults: 'nope' }), { maxResults: 5, pageToken: undefined });
});

test('searchYouTubeAPI forwards normalized options and returns pagination metadata', async (t) => {
  const originalGet = axios.get;
  let capturedUrl;
  let capturedConfig;
  axios.get = async (url, config) => {
    capturedUrl = url;
    capturedConfig = config;
    return {
      data: {
        items: [{ id: { videoId: 'abc123' }, snippet: { title: 'Alpha' } }],
        nextPageToken: 'token-2',
      },
    };
  };
  t.after(() => {
    axios.get = originalGet;
  });

  const result = await searchYouTubeAPI('learn guitar', 'test-key', { maxResults: 99, pageToken: '  page-1 ' });

  assert.equal(capturedUrl, 'https://www.googleapis.com/youtube/v3/search');
  assert.equal(capturedConfig.params.q, 'learn guitar');
  assert.equal(capturedConfig.params.key, 'test-key');
  assert.equal(capturedConfig.params.maxResults, 50);
  assert.equal(capturedConfig.params.pageToken, 'page-1');
  assert.equal(result.nextPageToken, 'token-2');
  assert.equal(result.items.length, 1);
});

test('searchYouTube returns alternatives and nextPageToken from API results', async (t) => {
  const originalGet = axios.get;
  let capturedConfig;
  process.env.YT_API_KEY = 'test-key';
  axios.get = async (_url, config) => {
    capturedConfig = config;
    return {
      data: {
        items: [
          { id: { videoId: 'abc123' }, snippet: { title: 'Alpha' } },
          { id: { videoId: 'def456' }, snippet: { title: 'Beta' } },
        ],
        nextPageToken: 'token-2',
      },
    };
  };
  t.after(() => {
    axios.get = originalGet;
    delete process.env.YT_API_KEY;
  });

  const video = await searchYouTube('learn guitar', { maxResults: 2, pageToken: ' page-1 ' });

  assert.equal(video.title, 'Alpha');
  assert.equal(video.videoId, 'abc123');
  assert.equal(video.source, 'youtube-api');
  assert.equal(video.nextPageToken, 'token-2');
  assert.equal(video.alternatives.length, 2);
  assert.deepEqual(video.alternatives.map((item) => item.videoId), ['abc123', 'def456']);
  assert.equal(capturedConfig.params.maxResults, 2);
  assert.equal(capturedConfig.params.pageToken, 'page-1');
});
