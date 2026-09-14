import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deflateSync } from 'node:zlib';
import { precheck } from '../src/precheck.js';
import { makeZip } from './zip.mjs';

const docXml = (t) => `<?xml version="1.0"?><w:document><w:body><w:p><w:r><w:t>${t}</w:t></w:r></w:p></w:body></w:document>`;
const hdrXml = (t) => `<?xml version="1.0"?><w:hdr><w:p><w:r><w:t>${t}</w:t></w:r></w:p></w:hdr>`;

test('docx: banner in header -> found', async () => {
  const z = makeZip({ 'word/document.xml': docXml('body'), 'word/header1.xml': hdrXml('CUI//SP-EXPT//FEDCON'), 'word/footer1.xml': hdrXml('CUI//SP-EXPT//FEDCON') });
  assert.equal((await precheck('a.docx', z)).status, 'found');
});
test('docx: banner split across runs still found', async () => {
  const z = makeZip({ 'word/document.xml': docXml('x'), 'word/header1.xml': '<w:hdr><w:p><w:r><w:t>CUI</w:t></w:r><w:r><w:t>//SP-EXPT</w:t></w:r></w:p></w:hdr>' });
  assert.equal((await precheck('a.docx', z)).status, 'found');
});
test('docx: first-page header without banner -> partial', async () => {
  const z = makeZip({ 'word/document.xml': docXml('x'), 'word/header1.xml': hdrXml('CUI'), 'word/header2.xml': hdrXml('Title page') });
  const r = await precheck('a.docx', z); assert.equal(r.status, 'partial'); assert.match(r.detail, /header2/);
});
test('docx: only body text -> partial; nothing -> missing', async () => {
  assert.equal((await precheck('a.docx', makeZip({ 'word/document.xml': docXml('CUI//PRVCY') }))).status, 'partial');
  assert.equal((await precheck('a.docx', makeZip({ 'word/document.xml': docXml('nothing') }))).status, 'missing');
  assert.equal((await precheck('a.docx', makeZip({ 'word/document.xml': docXml('CUISINE'), 'word/header1.xml': hdrXml('cuisine') }))).status, 'missing');
});
test('pptx: per-slide check and master inheritance', async () => {
  const s = (t) => `<p:sld><p:txBody><a:p><a:r><a:t>${t}</a:t></a:r></a:p></p:txBody></p:sld>`;
  const r = await precheck('d.pptx', makeZip({ 'ppt/slides/slide1.xml': s('CUI'), 'ppt/slides/slide2.xml': s('no'), 'ppt/slides/slide3.xml': s('CUI//CTI') }));
  assert.equal(r.status, 'partial'); assert.match(r.detail, /2/);
  assert.equal((await precheck('d.pptx', makeZip({ 'ppt/slides/slide1.xml': s('no'), 'ppt/slideMasters/slideMaster1.xml': s('CUI') }))).status, 'found');
});
test('xlsx: header/footer per sheet', async () => {
  const sh = (hf) => `<worksheet><sheetData/>${hf ? `<headerFooter><oddHeader>&amp;C${hf}</oddHeader></headerFooter>` : ''}</worksheet>`;
  assert.equal((await precheck('s.xlsx', makeZip({ 'xl/worksheets/sheet1.xml': sh('CUI//SP-EXPT') }))).status, 'found');
  assert.equal((await precheck('s.xlsx', makeZip({ 'xl/worksheets/sheet1.xml': sh(''), 'xl/sharedStrings.xml': '<sst><si><t>CUI</t></si></sst>' }))).status, 'partial');
});
test('pdf: text in flate stream', async () => {
  const content = deflateSync(Buffer.from('BT /F1 12 Tf (CUI//SP-EXPT//FEDCON) Tj ET'));
  const pdf = Buffer.concat([Buffer.from('%PDF-1.4\n1 0 obj<</Length 5/Filter/FlateDecode>>stream\n'), content, Buffer.from('\nendstream\nendobj\n%%EOF')]);
  assert.equal((await precheck('x.pdf', new Uint8Array(pdf))).status, 'found');
  assert.equal((await precheck('x.pdf', new TextEncoder().encode('%PDF-1.4 nothing here'))).status, 'partial');
});
test('text and unknown types', async () => {
  assert.equal((await precheck('n.txt', new TextEncoder().encode('CUI//PRVCY\nhello'))).status, 'found');
  assert.equal((await precheck('n.txt', new TextEncoder().encode('hello'))).status, 'missing');
  assert.equal((await precheck('p.png', new Uint8Array([1, 2, 3]))).status, 'unknown');
  assert.equal((await precheck('bad.docx', new Uint8Array([1, 2, 3]))).status, 'unknown');
});
