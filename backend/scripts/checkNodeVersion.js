#!/usr/bin/env node
const semver = process.versions.node;
const major = parseInt(semver.split('.')[0], 10);
if (Number.isNaN(major)) {
    console.error(`Unable to parse Node version: ${semver}`);
    process.exit(1);
}
if (major < 20) {
    if (process.env.SKIP_NODE_CHECK === '1' || process.env.ALLOW_NODE18 === 'true') {
        console.warn(`[WARN] Node ${semver} detected (<20). Continuing because SKIP_NODE_CHECK/ALLOW_NODE18 is set. Some features (yt-search fallback) may be disabled.`);
    } else {
        console.error(`\n[ERROR] Node ${semver} detected. This project requires Node >= 20 for yt-search fallback stability.\n` +
            `Options:\n` +
            `  - Use Homebrew:    brew install node@20 && brew link --overwrite --force node@20\n` +
            `  - Or install nvm:  https://github.com/nvm-sh/nvm and run: nvm install 20 && nvm use 20\n` +
            `Then verify: node -v  (should be v20.x)\n` +
            `\nTemporary bypass (not recommended):\n` +
            `  SKIP_NODE_CHECK=1 npm start\n`);
        process.exit(1);
    }
}
console.log(`[OK] Node ${semver} detected (>=20).`);
