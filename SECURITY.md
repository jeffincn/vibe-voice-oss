# Security Policy

## Supported versions

Security fixes are applied on the latest `main` branch of this repository.

## Reporting a vulnerability

Please report security issues privately (for example via GitHub Security Advisories once the repository is published, or by contacting the maintainers directly). Do not file a public issue that includes secrets or exploit details.

## Secrets and local data

- ASR and LLM API keys are stored in the macOS Keychain under service `app.vibevoice.macos`.
- Do not commit `.env`, keychain dumps, preference plists, audio samples, or signing certificates.
- Endpoints are user-configurable. Audio and transcripts are sent only to the URLs configured in Settings.

## Preferred hardening

If you change secret storage, keep keys out of UserDefaults, logs, crash reports, and exported timing reports.
