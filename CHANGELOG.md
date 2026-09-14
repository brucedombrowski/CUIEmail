# Changelog

All notable changes to CUIEmail are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0-beta.1] - 2026-09-14

Complete rewrite. The tool is now a single HTML file that runs in the browser; PowerShell is only a fallback.

### Added
- Browser-based locking and unlocking (Web Crypto: PBKDF2-HMAC-SHA256 600k, AES-256-CBC, HMAC-SHA256 encrypt-then-MAC) with a versioned container format (`docs/FILE-FORMAT.md`).
- CUI marking engine built from the CUI Registry: all 119 categories with Basic/Specified status, all limited dissemination controls, country trigraphs and organization tetragraphs. Banner ordering, `SP-` prefixes, alphabetization, REL TO / DISPLAY ONLY list ordering, and contradictory-control checks are enforced (`docs/MARKING-COMPLIANCE.md`).
- Designation indicator (Controlled by, category, dissemination control, POC, decontrol) remembered between uses.
- Transmittal email generated with banner top and bottom, transmittal notice per 32 CFR 2002.20(j), subject beginning with `CUI`; opens as a draft in the default mail program.
- Pre-check of Word, PowerPoint, Excel, PDF and text attachments for an existing CUI banner (per header, per slide, per sheet).
- Five-word generated passphrases (EFF short wordlist) that can be read over a phone; recipient entry is forgiving of capitalization and spaces.
- `Unlock.ps1` and an embedded one-line PowerShell fallback, verified in CI on Windows PowerShell 5.1 and PowerShell 7.
- GitHub Pages hosting of the tool and automated releases.

### Removed
- All v0 PowerShell/batch scripts, the Outlook `.msg` generation, and the unauthenticated `.Locked` format. Archived under `docs/archive/v1`.
