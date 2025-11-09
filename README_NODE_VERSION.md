# Node.js Version Alignment

This project requires **Node.js >=20**.

## Local Setup

1. Install nvm if not present.
2. Run `nvm install 20 && nvm use 20`.
3. (Optional) Pin with Volta: `volta pin node@20`.

An `.nvmrc` file is provided (20.19.0). Most CI workflows already use Node 20 / 22.

## Why Node 20+

- Stable test runner (`node --test`) without TAP lexer issues.
- Better performance and security patches.
- Modern V8 features for async context and fetch.

## CI

GitHub Actions matrix should stay on Node 20 and 22.

## Troubleshooting

If you see errors like `ERR_TAP_LEXER_ERROR` on older Node, upgrade to Node 20.
