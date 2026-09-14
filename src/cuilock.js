// cuilock.js - CUI Lock container format, version 1.
// Runs unchanged in browsers (Edge/Chrome) and Node 20+ using WebCrypto.
// See docs/FILE-FORMAT.md for the byte layout and the reasons behind each choice.

export const FORMAT_VERSION = 1;
export const KDF_PBKDF2_HMAC_SHA256 = 1;
export const DEFAULT_ITERATIONS = 600000; // OWASP 2023 guidance for PBKDF2-HMAC-SHA256
export const LOCKED_SUFFIX = '.locked';
export const LOCKED_PREFIX = 'CUI - ';

const MAGIC = new Uint8Array([0x43, 0x55, 0x49, 0x4c]); // "CUIL"
const SALT_LEN = 16;
const IV_LEN = 16;
const TAG_LEN = 32;
const FIXED_LEN = 4 + 1 + 1 + 4 + SALT_LEN + IV_LEN + 4;
const MAX_HEADER_LEN = 64 * 1024;

const subtle = globalThis.crypto.subtle;
const te = new TextEncoder();
const td = new TextDecoder();

export class CuiLockError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'CuiLockError';
    this.code = code;
  }
}

async function deriveKeys(passphrase, salt, iterations) {
  const raw = te.encode(String(passphrase).normalize('NFC'));
  const base = await subtle.importKey('raw', raw, 'PBKDF2', false, ['deriveBits']);
  const bits = new Uint8Array(
    await subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, base, 512)
  );
  const encKey = await subtle.importKey('raw', bits.slice(0, 32), { name: 'AES-CBC' }, false, ['encrypt', 'decrypt']);
  const macKey = await subtle.importKey('raw', bits.slice(32, 64), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
  bits.fill(0);
  return { encKey, macKey };
}

/**
 * Lock plaintext bytes with a passphrase.
 * @param {Uint8Array} plaintext
 * @param {string} passphrase
 * @param {object} header  Plain JSON object stored in the clear but authenticated (original name, banner, ...).
 * @param {{iterations?: number}} [opts]
 * @returns {Promise<Uint8Array>} the .locked file bytes
 */
export async function lock(plaintext, passphrase, header, opts = {}) {
  if (!passphrase || String(passphrase).length === 0) throw new CuiLockError('EMPTY_PASSPHRASE', 'A passphrase is required.');
  const iterations = opts.iterations ?? DEFAULT_ITERATIONS;
  const salt = crypto.getRandomValues(new Uint8Array(SALT_LEN));
  const iv = crypto.getRandomValues(new Uint8Array(IV_LEN));
  const { encKey, macKey } = await deriveKeys(passphrase, salt, iterations);
  const hdr = te.encode(JSON.stringify(header ?? {}));
  if (hdr.length > MAX_HEADER_LEN) throw new CuiLockError('HEADER_TOO_LARGE', 'Header too large.');
  const ct = new Uint8Array(await subtle.encrypt({ name: 'AES-CBC', iv }, encKey, plaintext));

  const pre = new Uint8Array(FIXED_LEN + hdr.length + ct.length);
  const dv = new DataView(pre.buffer);
  let o = 0;
  pre.set(MAGIC, o); o += 4;
  pre[o++] = FORMAT_VERSION;
  pre[o++] = KDF_PBKDF2_HMAC_SHA256;
  dv.setUint32(o, iterations); o += 4;
  pre.set(salt, o); o += SALT_LEN;
  pre.set(iv, o); o += IV_LEN;
  dv.setUint32(o, hdr.length); o += 4;
  pre.set(hdr, o); o += hdr.length;
  pre.set(ct, o);

  const tag = new Uint8Array(await subtle.sign('HMAC', macKey, pre));
  const out = new Uint8Array(pre.length + TAG_LEN);
  out.set(pre, 0);
  out.set(tag, pre.length);
  return out;
}

/** True if the bytes start with the CUI Lock magic. */
export function looksLocked(bytes) {
  return bytes.length >= 4 && bytes[0] === MAGIC[0] && bytes[1] === MAGIC[1] && bytes[2] === MAGIC[2] && bytes[3] === MAGIC[3];
}

/**
 * Parse the unauthenticated header of a .locked file WITHOUT verifying it.
 * Callers must treat the returned header as untrusted until unlock() succeeds.
 */
export function peek(bytes) {
  if (!looksLocked(bytes)) throw new CuiLockError('NOT_CUILOCK', 'This is not a CUI Lock (.locked) file.');
  if (bytes.length < FIXED_LEN + TAG_LEN) throw new CuiLockError('TRUNCATED', 'The file is too short to be a valid .locked file.');
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const version = bytes[4];
  const kdf = bytes[5];
  if (version !== FORMAT_VERSION) throw new CuiLockError('UNSUPPORTED_VERSION', `Unsupported .locked format version ${version}. Get a newer copy of CUIEmail.`);
  if (kdf !== KDF_PBKDF2_HMAC_SHA256) throw new CuiLockError('UNSUPPORTED_KDF', `Unsupported key derivation ${kdf}.`);
  const iterations = dv.getUint32(6);
  if (iterations < 1000 || iterations > 50_000_000) throw new CuiLockError('BAD_ITERATIONS', 'Invalid iteration count.');
  const salt = bytes.slice(10, 10 + SALT_LEN);
  const iv = bytes.slice(26, 26 + IV_LEN);
  const hdrLen = dv.getUint32(42);
  if (hdrLen > MAX_HEADER_LEN || FIXED_LEN + hdrLen + TAG_LEN > bytes.length) throw new CuiLockError('TRUNCATED', 'The file is damaged or incomplete.');
  let header;
  try { header = JSON.parse(td.decode(bytes.subarray(FIXED_LEN, FIXED_LEN + hdrLen))); }
  catch { throw new CuiLockError('BAD_HEADER', 'The file header is damaged.'); }
  const ctOffset = FIXED_LEN + hdrLen;
  const ctLength = bytes.length - ctOffset - TAG_LEN;
  if (ctLength <= 0 || ctLength % 16 !== 0) throw new CuiLockError('TRUNCATED', 'The file is damaged or incomplete.');
  return { version, kdf, iterations, salt, iv, header, ctOffset, ctLength };
}

/**
 * Unlock a .locked file. Verifies the HMAC before decrypting.
 * @returns {Promise<{header: object, plaintext: Uint8Array}>}
 */
export async function unlock(bytes, passphrase) {
  const p = peek(bytes);
  const { encKey, macKey } = await deriveKeys(passphrase, p.salt, p.iterations);
  const body = bytes.subarray(0, bytes.length - TAG_LEN);
  const tag = bytes.subarray(bytes.length - TAG_LEN);
  const ok = await subtle.verify('HMAC', macKey, tag, body);
  if (!ok) throw new CuiLockError('BAD_PASSPHRASE_OR_TAMPERED', 'Wrong passphrase, or the file was altered after it was locked.');
  let plaintext;
  try {
    plaintext = new Uint8Array(await subtle.decrypt({ name: 'AES-CBC', iv: p.iv }, encKey, bytes.subarray(p.ctOffset, p.ctOffset + p.ctLength)));
  } catch {
    throw new CuiLockError('DECRYPT_FAILED', 'The file could not be decrypted.');
  }
  return { header: p.header, plaintext };
}

/** Name for the locked container: "CUI - <original>.locked". */
export function lockedName(originalName) {
  return LOCKED_PREFIX + originalName + LOCKED_SUFFIX;
}

/** Best-effort original name from a container name, used only as a fallback when the header is unusable. */
export function unlockedNameFromContainer(containerName) {
  let n = containerName;
  if (n.toLowerCase().endsWith(LOCKED_SUFFIX)) n = n.slice(0, -LOCKED_SUFFIX.length);
  if (n.startsWith(LOCKED_PREFIX)) n = n.slice(LOCKED_PREFIX.length);
  return n || 'unlocked-file';
}
