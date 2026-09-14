# AGENTS.md

Guidance for AI agents and contributors.

- The product is `dist/CUIEmail.html`, built by `node build.mjs` from `src/`. Never edit `dist/` by hand.
- `src/marking.js` encodes CUI marking rules. Every rule must cite its source in a comment and have a test in `test/marking.test.mjs`. Do not add a marking behavior from memory; fetch the primary source (32 CFR 2002.20, NARA CUI Marking Handbook, CUI Registry pages, NPR 2810.7) and quote it in `docs/MARKING-COMPLIANCE.md`.
- `src/data/*.json` is scraped from the CUI Registry (see `docs/MARKING-COMPLIANCE.md` for dates). Re-scrape rather than hand-edit.
- `src/cuilock.js` and `fallback/Unlock.ps1` implement the same format (`docs/FILE-FORMAT.md`). A change to one requires the other and a bump of the version byte if bytes change.
- The page must keep working from `file://` with no network: no external scripts, styles, fonts, or fetches.
- Target user is non-technical: double-click, answer prompts. No file editing, no command line on the primary path.
- Releases: update `CHANGELOG.md`, bump `package.json` version, `git tag vX.Y.Z && git push --tags`. CI builds and attaches the release assets.
