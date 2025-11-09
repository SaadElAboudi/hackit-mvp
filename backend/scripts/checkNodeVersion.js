#!/usr/bin/env node
const semver = process.versions.node;
const major = parseInt(semver.split('.')[0], 10);
if (Number.isNaN(major)) {
    console.error(`Unable to parse Node version: ${semver}`);
    process.exit(1);
}
if (major < 20) {
    console.error(`\n[ERROR] Node ${semver} detected. This project requires Node >= 20.\n` +
        `How to upgrade on macOS:\n` +
        `  - Homebrew:  brew install node@20 && brew link --overwrite --force node@20\n` +
        `  - Volta:     curl https://get.volta.sh | bash && volta install node@20\n` +
        `  - npx temp:  npx -p node@20 node -v (temporary)\n` +
        `Then verify: node -v  (should be v20.x)\n`);
    process.exit(1);
}
console.log(`[OK] Node ${semver} detected (>=20).`);
