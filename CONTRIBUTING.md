# Contributing

Thanks for contributing to Vibe Voice OSS.

## Local development

Requirements: macOS 14+, Apple Silicon, Xcode 16+.

```bash
swift test
swift build
./scripts/build-app.sh
open "dist/Vibe Voice OSS.app"
```

You also need a local OpenAI-compatible ASR server (for example oMLX) listening on the endpoint configured in Settings. Defaults point at `http://127.0.0.1:8000`.

The HUD preview under `tools/fluid-voice-oss` is optional:

```bash
cd tools/fluid-voice-oss
pnpm install
pnpm dev
```

Do not commit `node_modules`, `.build`, or `dist`.

## Pull requests

- Keep changes focused; prefer small PRs.
- Run `swift test` before opening a PR.
- Do not commit API keys, `.env` files, certificates, or personal preference exports.
- Use conventional commits when possible (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`).

## Security

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md). Never open a public issue that includes live credentials.
