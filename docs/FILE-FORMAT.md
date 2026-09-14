# `.locked` file format (CUI Lock, version 1)

A `.locked` file is one original file, encrypted with a passphrase, plus a small authenticated header.
The same bytes are produced and read by the browser tool (`src/cuilock.js`) and by the PowerShell fallback (`fallback/Unlock.ps1`).

## Layout

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | magic | ASCII `CUIL` |
| 4 | 1 | version | `1` |
| 5 | 1 | kdf | `1` = PBKDF2-HMAC-SHA256 |
| 6 | 4 | iterations | unsigned, big-endian. Default 600,000 |
| 10 | 16 | salt | random, per file |
| 26 | 16 | iv | random, per file |
| 42 | 4 | header length | unsigned, big-endian, max 65,536 |
| 46 | n | header | UTF-8 JSON (see below) |
| 46+n | m | ciphertext | AES-256-CBC, PKCS#7 padding, `m` is a multiple of 16 |
| end-32 | 32 | tag | HMAC-SHA256 over every preceding byte |

## Keys

`PBKDF2-HMAC-SHA256(passphrase as UTF-8 after NFC normalization, salt, iterations)` produces 64 bytes.
Bytes 0-31 are the AES-256 key. Bytes 32-63 are the HMAC key. Encrypt-then-MAC: the tag is verified before any decryption is attempted, so a wrong passphrase or an altered file is reported without touching the ciphertext.

## Header JSON

```json
{"v":1,"name":"Report.docx","size":12345,"banner":"CUI//SP-EXPT//FEDCON",
 "designation":["Controlled by: NASA Johnson Space Center","CUI Category: SP-EXPT","Limited Dissemination Control: FEDCON","POC: J. Doe, 281-555-0100"],
 "created":"2026-09-14T17:00:00.000Z","tool":"CUIEmail 1.0.0-beta.1"}
```

The header is not encrypted (the banner is not itself CUI, and it lets the recipient see the marking before unlocking), but it is covered by the tag, so it cannot be altered without detection. Software must treat it as untrusted until the tag verifies.

## Why these choices

- **AES-256-CBC + HMAC-SHA256** rather than AES-GCM: Windows PowerShell 5.1 (.NET Framework) has no AES-GCM class, and the PowerShell fallback must work on a stock Windows machine with nothing installed. CBC with encrypt-then-MAC is a standard, secure construction and both primitives are FIPS 140 validated in Windows CNG and in Chromium's BoringSSL module.
- **600,000 PBKDF2 iterations**: OWASP's 2023 recommendation for PBKDF2-HMAC-SHA256. Takes well under a second in a browser.
- **Magic and version bytes**: the previous tool had none, so any format change would have been silent. This one can evolve.
- **Passphrases** default to five words from the EFF short wordlist (about 52 bits of entropy), chosen because they can be read over a phone. Combined with the slow KDF that is far beyond practical offline guessing for a per-file random salt.
- **File name**: the container is named `CUI - <original name>.locked`. The original name is restored from the header, not from the container name.
