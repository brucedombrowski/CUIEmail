import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as L from '../src/cuilock.js';

const te = new TextEncoder();
const ITER = 2000; // fast for tests; format stores the count

test('round trip with header', async () => {
  const pt = te.encode('hello CUI world');
  const locked = await L.lock(pt, 'acid-bloom-crane', { name: 'a.txt', banner: 'CUI//SP-EXPT' }, { iterations: ITER });
  assert.ok(L.looksLocked(locked));
  const p = L.peek(locked);
  assert.equal(p.iterations, ITER); assert.equal(p.header.name, 'a.txt');
  const r = await L.unlock(locked, 'acid-bloom-crane');
  assert.deepEqual(r.plaintext, pt); assert.equal(r.header.banner, 'CUI//SP-EXPT');
});

test('empty plaintext and 16-byte-multiple plaintext round trip', async () => {
  for (const n of [0, 16, 32, 1000]) {
    const pt = crypto.getRandomValues(new Uint8Array(n));
    const r = await L.unlock(await L.lock(pt, 'pw-pw-pw-pw', {}, { iterations: ITER }), 'pw-pw-pw-pw');
    assert.deepEqual(r.plaintext, pt);
  }
});

test('wrong passphrase is rejected before decryption', async () => {
  const locked = await L.lock(te.encode('x'), 'right-one-here', {}, { iterations: ITER });
  await assert.rejects(() => L.unlock(locked, 'wrong-one-here'), (e) => e.code === 'BAD_PASSPHRASE_OR_TAMPERED');
});

test('tampering with header, ciphertext, or tag is detected', async () => {
  const locked = await L.lock(te.encode('payload payload payload'), 'pw-pw-pw-pw', { name: 'n' }, { iterations: ITER });
  for (const idx of [50, locked.length - 40, locked.length - 1]) {
    const t = locked.slice(); t[idx] ^= 0x01;
    await assert.rejects(() => L.unlock(t, 'pw-pw-pw-pw'), (e) => e.code === 'BAD_PASSPHRASE_OR_TAMPERED' || e.code === 'BAD_HEADER');
  }
});

test('non-locked and truncated input give clear errors', async () => {
  assert.throws(() => L.peek(te.encode('not a locked file at all, really not')), (e) => e.code === 'NOT_CUILOCK');
  const locked = await L.lock(te.encode('abc'), 'pw-pw-pw-pw', {}, { iterations: ITER });
  assert.throws(() => L.peek(locked.subarray(0, 60)), (e) => e.code === 'TRUNCATED');
  const v = locked.slice(); v[4] = 9;
  assert.throws(() => L.peek(v), (e) => e.code === 'UNSUPPORTED_VERSION');
});

test('passphrase is NFC-normalized so composed and decomposed forms match', async () => {
  const locked = await L.lock(te.encode('é'), 'café-pass-word', {}, { iterations: ITER });
  const r = await L.unlock(locked, 'café-pass-word');
  assert.equal(new TextDecoder().decode(r.plaintext), 'é');
});

test('container naming', () => {
  assert.equal(L.lockedName('Report.docx'), 'CUI - Report.docx.locked');
  assert.equal(L.unlockedNameFromContainer('CUI - Report.docx.locked'), 'Report.docx');
  assert.equal(L.unlockedNameFromContainer('Report.docx.LOCKED'), 'Report.docx');
});

test('default iteration count is 600000', () => { assert.equal(L.DEFAULT_ITERATIONS, 600000); });
