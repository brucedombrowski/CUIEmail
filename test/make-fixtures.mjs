// Produce fixtures for the PowerShell interop test: a plaintext, its locked form, and the passphrase.
import { mkdirSync, writeFileSync } from 'node:fs';
import * as L from '../src/cuilock.js';
const dir = 'test/fixtures/out';
mkdirSync(dir, { recursive: true });
const pt = new Uint8Array(70000); for (let i = 0; i < pt.length; i++) pt[i] = (i * 7 + 3) & 0xff;
const pass = 'acid-bloom-crane-dwarf-eagle';
const header = { v: 1, name: 'Sample Report.docx', size: pt.length, banner: 'CUI//SP-EXPT//FEDCON', designation: ['Controlled by: Test Agency'], created: '2026-09-14T00:00:00Z' };
const locked = await L.lock(pt, pass, header);
writeFileSync(`${dir}/expected.bin`, pt);
writeFileSync(`${dir}/${L.lockedName('Sample Report.docx')}`, locked);
writeFileSync(`${dir}/passphrase.txt`, pass);
console.log('fixtures written to', dir);
