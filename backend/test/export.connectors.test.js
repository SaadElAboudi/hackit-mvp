import test from 'node:test';
import assert from 'node:assert/strict';

import {
    executeWithRetry,
    shouldRetryExportError,
} from '../src/services/exportConnectors.js';

test('shouldRetryExportError returns true for transient transport and 5xx', () => {
    assert.equal(shouldRetryExportError({ code: 'ETIMEDOUT' }), true);
    assert.equal(shouldRetryExportError({ status: 503 }), true);
    assert.equal(shouldRetryExportError({ response: { status: 429 } }), true);
    assert.equal(shouldRetryExportError({ code: 'ratelimited' }), true);
});

test('shouldRetryExportError returns false for non-retryable errors', () => {
    assert.equal(shouldRetryExportError({ status: 400 }), false);
    assert.equal(shouldRetryExportError({ code: 'invalid_auth' }), false);
});

test('executeWithRetry retries transient failure then succeeds', async () => {
    let calls = 0;
    const { result, attempts } = await executeWithRetry(async () => {
        calls += 1;
        if (calls < 3) {
            const err = new Error('temporary');
            err.code = 'ETIMEDOUT';
            throw err;
        }
        return { ok: true };
    }, { maxAttempts: 3, baseDelayMs: 10 });

    assert.equal(result.ok, true);
    assert.equal(attempts, 3);
});

test('executeWithRetry stops immediately for non-retryable error', async () => {
    let calls = 0;

    await assert.rejects(
        executeWithRetry(async () => {
            calls += 1;
            const err = new Error('invalid token');
            err.status = 400;
            throw err;
        }, { maxAttempts: 3, baseDelayMs: 10 }),
        /invalid token/
    );

    assert.equal(calls, 1);
});
