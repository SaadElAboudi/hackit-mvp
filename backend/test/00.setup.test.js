// Global test setup: silence verbose logs that can confuse TAP lexer and set consistent environment.
import test from 'node:test';

process.env.NODE_ENV = 'test';

// Replace console.* with no-op to prevent accidental leading UTF-8 characters interfering with TAP parsing.
/* eslint-disable no-console */
if (!process.env.VERBOSE_TEST_LOGS) {
    console.log = () => { };
    console.info = () => { };
    console.warn = () => { };
    console.error = () => { };
}

await test('setup initialized', () => { });
