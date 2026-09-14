# CUIEmail

Send Controlled Unclassified Information (CUI) by email when certificate-based encryption is not available, with the markings done right.

**One file. No install. Nothing leaves your computer.**

## For senders

1. Download **`CUIEmail.html`** from the [latest release](https://github.com/brucedombrowski/CUIEmail/releases/latest) and double-click it. It opens in your browser (Edge or Chrome).
2. Choose **Send CUI files by email** and follow the numbered steps: pick files, pick the CUI category and dissemination controls, say who controls it, give the email a subject, and take the generated passphrase.
3. Click **Lock files and prepare the email**. Choose a folder. You get `CUI - <name>.locked` for each file plus a copy of `CUIEmail.html` for the recipient.
4. Click **Open email draft**, attach the files it lists, send.
5. Call or text the recipient with the passphrase. Never email it.

The tool checks each Word, PowerPoint, Excel, PDF or text file for a CUI banner before locking it and warns if it cannot find one. It does not edit your documents; the banner and designation indicator inside the file are your responsibility.

## For recipients

1. Save the attachments. Double-click `CUIEmail.html` (or open https://brucedombrowski.github.io/CUIEmail/).
2. Choose **Open a locked file I received**, pick the `.locked` file, enter the passphrase the sender gave you, save.

If the HTML page was stripped by your mail system and the web address is blocked, the page's help section (and `Unlock.ps1` in the release) gives a Windows PowerShell fallback.

## What it does

- Builds the CUI banner marking from the CUI Registry category list and limited dissemination controls, with Specified/Basic ordering, alphabetization, `SP-` prefixes, and REL TO / DISPLAY ONLY country ordering enforced. See [docs/MARKING-COMPLIANCE.md](docs/MARKING-COMPLIANCE.md) for every rule and its source.
- Writes a compliant transmittal email: banner at top and bottom, designation indicator, transmittal notice, subject beginning with `CUI`.
- Locks each file with AES-256-CBC + HMAC-SHA256, key from PBKDF2-HMAC-SHA256 (600,000 iterations), using the browser's built-in Web Crypto. See [docs/FILE-FORMAT.md](docs/FILE-FORMAT.md).
- Generates five-word passphrases that can be read over a phone.

## Development

```bash
npm test          # marking rules, crypto, document pre-check
npm run build     # -> dist/CUIEmail.html
node test/make-fixtures.mjs && pwsh -File test/interop.ps1   # PowerShell fallback against JS-locked files
```

Source is in `src/` (plain ES modules, no dependencies); `build.mjs` inlines everything into one HTML file. CI runs the tests on Linux and on Windows (including Windows PowerShell 5.1 for the fallback), deploys `main` to GitHub Pages, and attaches `CUIEmail.html` to releases tagged `v*`.

The project was called SendCUIEmail through version 0.x (a PowerShell-only tool, 2025 to January 2026) is preserved under [docs/archive/v1](docs/archive/v1/) and at tag `v0.17.3`. Its `.Locked` files are not compatible with this version.

## License

MIT
