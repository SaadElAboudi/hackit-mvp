// ESM preloaded setup for Node >= 20 using --import
process.env.NODE_ENV = 'test';

// Silence all console outputs to avoid TAP parsing issues from stray output
/* eslint-disable no-console */
if (!process.env.VERBOSE_TEST_LOGS) {
    console.log = () => { };
    console.info = () => { };
    console.warn = () => { };
    console.error = () => { };
}
