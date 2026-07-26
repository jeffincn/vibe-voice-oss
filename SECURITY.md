# Security Policy

## Supported versions

Security fixes are applied on the latest `main` branch of this repository.

## Reporting a vulnerability

Please report security issues privately (for example via GitHub Security Advisories once the repository is published, or by contacting the maintainers directly). Do not file a public issue that includes secrets or exploit details.

## Secrets and local data

- ASR and LLM API keys are stored in the macOS Keychain under service `app.vibevoice.oss.macos`. The pre-rename service `app.vibevoice.macos` is purged on first launch.
- Builds without a certificate-backed signature (ad-hoc `codesign --sign -`) cannot use the Keychain, because the ACL is bound to a designated requirement that changes on every rebuild and would prompt for the login password on each launch. Those builds fall back to `~/Library/Application Support/VibeVoiceOSS/credentials.json`, mode 0600 inside a mode 0700 directory and excluded from backups. **This is clear text.** Any process running as your user can read it; use a signed build if that matters to you. Settings shows a warning when the fallback is active.
- Do not commit `.env`, keychain dumps, preference plists, audio samples, or signing certificates.
- Endpoints are user-configurable. Audio and transcripts are sent only to the URLs configured in Settings.
- API keys are never attached to a remote clear-text (`http://` / `ws://`) endpoint; the request is refused instead. Loopback addresses are exempt so local model servers keep working. Endpoints that would send audio or transcripts unencrypted are flagged in Settings even when no key is configured.

## Preferred hardening

If you change secret storage, keep keys out of UserDefaults, logs, crash reports, and exported timing reports. HTTP error bodies are echoed into user-facing messages, so route any new call site through `HTTPErrorBody.summarize`, which masks credentials and caps length.
