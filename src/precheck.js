// precheck.js - Best-effort check that a file already carries a CUI banner before it is locked.
// 32 CFR 2002.20(c)(1): the banner "must be the same on each page of the document that includes CUI".
// This tool cannot add markings to a document; it can only warn the sender when it finds none.
//
// Result: { status: 'found' | 'partial' | 'missing' | 'unknown', detail: string }

const td = new TextDecoder('utf-8', { fatal: false });
const BANNER_RE = /\bCUI\b|\bCONTROLLED\b/;

function stripTags(xml) {
  // Join runs before searching so "CUI" split across <w:t> elements still matches when it is whole in one run,
  // and so "CUI//SP-EXPT" written as separate runs is seen as contiguous text.
  return xml.replace(/<[^>]+>/g, '');
}

async function inflateRaw(bytes) {
  const ds = new DecompressionStream('deflate-raw');
  const stream = new Blob([bytes]).stream().pipeThrough(ds);
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Minimal ZIP central-directory reader. Returns Map name -> {method, csize, usize, offset}. */
function zipEntries(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('not a zip');
  const count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  const map = new Map();
  for (let i = 0; i < count; i++) {
    if (dv.getUint32(p, true) !== 0x02014b50) break;
    const method = dv.getUint16(p + 10, true);
    const csize = dv.getUint32(p + 20, true);
    const usize = dv.getUint32(p + 24, true);
    const nlen = dv.getUint16(p + 28, true);
    const elen = dv.getUint16(p + 30, true);
    const clen = dv.getUint16(p + 32, true);
    const offset = dv.getUint32(p + 42, true);
    const name = td.decode(bytes.subarray(p + 46, p + 46 + nlen));
    map.set(name, { method, csize, usize, offset });
    p += 46 + nlen + elen + clen;
  }
  return map;
}

async function zipRead(bytes, entry) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const p = entry.offset;
  if (dv.getUint32(p, true) !== 0x04034b50) throw new Error('bad local header');
  const nlen = dv.getUint16(p + 26, true);
  const elen = dv.getUint16(p + 28, true);
  const start = p + 30 + nlen + elen;
  const data = bytes.subarray(start, start + entry.csize);
  if (entry.method === 0) return data;
  if (entry.method === 8) return inflateRaw(data);
  throw new Error('unsupported compression');
}

async function textOf(bytes, entries, name) {
  const e = entries.get(name);
  if (!e) return null;
  return td.decode(await zipRead(bytes, e));
}

function hasBanner(text) {
  return BANNER_RE.test(stripTags(text));
}

async function checkDocx(bytes) {
  const entries = zipEntries(bytes);
  const names = [...entries.keys()];
  const headers = names.filter((n) => /^word\/(header|footer)\d*\.xml$/.test(n));
  if (headers.length === 0) {
    const doc = await textOf(bytes, entries, 'word/document.xml');
    if (doc && hasBanner(doc)) return { status: 'partial', detail: 'Found "CUI" in the body text but the document has no header or footer. The banner must appear at the top of every page; put it in the header.' };
    return { status: 'missing', detail: 'No header/footer and no "CUI" text found. Add the banner to the document header (Insert > Header in Word).' };
  }
  const missing = [];
  for (const h of headers) {
    const t = await textOf(bytes, entries, h);
    if (!hasBanner(t)) missing.push(h.replace('word/', ''));
  }
  const hdrOnly = headers.filter((h) => h.includes('header'));
  const hdrMissing = missing.filter((m) => m.startsWith('header'));
  if (hdrOnly.length && hdrMissing.length === 0) return { status: 'found', detail: 'CUI banner found in the page header.' };
  if (hdrMissing.length < hdrOnly.length) return { status: 'partial', detail: `Some headers lack the banner (${hdrMissing.join(', ')}). Word uses separate first-page/even-page headers; every one must carry the banner.` };
  if (missing.length < headers.length) return { status: 'partial', detail: 'Banner found only in the footer. Put it in the header (top of every page) as well.' };
  return { status: 'missing', detail: 'No "CUI" banner found in any header or footer.' };
}

async function checkPptx(bytes) {
  const entries = zipEntries(bytes);
  const names = [...entries.keys()];
  const slides = names.filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n)).sort((a, b) => parseInt(a.match(/\d+/)[0]) - parseInt(b.match(/\d+/)[0]));
  if (!slides.length) return { status: 'unknown', detail: 'No slides found.' };
  const masters = names.filter((n) => /^ppt\/(slideMasters|slideLayouts)\/.*\.xml$/.test(n));
  let masterHas = false;
  for (const m of masters) { if (hasBanner(await textOf(bytes, entries, m))) { masterHas = true; break; } }
  if (masterHas) return { status: 'found', detail: 'CUI banner found on the slide master/layout (applies to every slide).' };
  const missing = [];
  for (const s of slides) { if (!hasBanner(await textOf(bytes, entries, s))) missing.push(s.match(/slide(\d+)/)[1]); }
  if (missing.length === 0) return { status: 'found', detail: `CUI banner found on all ${slides.length} slides.` };
  if (missing.length === slides.length) return { status: 'missing', detail: 'No "CUI" banner found on any slide.' };
  return { status: 'partial', detail: `Slides without a banner: ${missing.join(', ')}. Every slide must carry it.` };
}

async function checkXlsx(bytes) {
  const entries = zipEntries(bytes);
  const names = [...entries.keys()];
  const sheets = names.filter((n) => /^xl\/worksheets\/sheet\d+\.xml$/.test(n)).sort();
  if (!sheets.length) return { status: 'unknown', detail: 'No worksheets found.' };
  const missing = [];
  for (const s of sheets) {
    const t = await textOf(bytes, entries, s);
    const hf = t.match(/<headerFooter[\s\S]*?<\/headerFooter>/);
    // Excel header text carries format codes such as &C (center), &"Arial,Bold", &12. Strip them before matching.
    const hfText = hf ? stripTags(hf[0]).replace(/&amp;/g, '&').replace(/&"[^"]*"/g, ' ').replace(/&\d+/g, ' ').replace(/&[A-Za-z]/g, ' ') : '';
    if (!BANNER_RE.test(hfText)) missing.push(s.match(/sheet(\d+)/)[1]);
  }
  if (missing.length === 0) return { status: 'found', detail: `CUI banner found in the print header of all ${sheets.length} sheets.` };
  const shared = await textOf(bytes, entries, 'xl/sharedStrings.xml');
  const inCells = shared && hasBanner(shared);
  if (missing.length === sheets.length) {
    return inCells
      ? { status: 'partial', detail: 'Found "CUI" in cell text but not in any sheet print header. Put the banner in Page Layout > Header/Footer on every sheet.' }
      : { status: 'missing', detail: 'No "CUI" banner found in any sheet header or cell.' };
  }
  return { status: 'partial', detail: `Sheets without a header banner: ${missing.join(', ')}.` };
}

async function checkPdf(bytes) {
  const latin = new TextDecoder('latin1').decode(bytes);
  if (/\bCUI\b/.test(latin)) return { status: 'found', detail: 'Found "CUI" text in the PDF. Could not verify that it appears on every page.' };
  // Inflate FlateDecode streams and look for text operators containing CUI.
  const re = /stream\r?\n/g;
  let m, hits = 0, streams = 0;
  while ((m = re.exec(latin)) && streams < 2000) {
    const start = m.index + m[0].length;
    const end = latin.indexOf('endstream', start);
    if (end < 0) break;
    streams++;
    let stop = end;
    while (stop > start && (bytes[stop - 1] === 0x0a || bytes[stop - 1] === 0x0d)) stop--;
    const chunk = bytes.subarray(start, stop);
    try {
      const ds = new DecompressionStream('deflate');
      const out = new Uint8Array(await new Response(new Blob([chunk]).stream().pipeThrough(ds)).arrayBuffer());
      const s = new TextDecoder('latin1').decode(out);
      if (/\bCUI\b|\(CUI|<435549/.test(s)) { hits++; break; }
    } catch { /* not flate, or damaged */ }
    re.lastIndex = end;
  }
  if (hits) return { status: 'found', detail: 'Found "CUI" text in the PDF content. Could not verify that it appears on every page.' };
  return { status: 'partial', detail: 'Could not find "CUI" as text in this PDF. It may be an image or use an unusual encoding. Confirm the banner appears on every page.' };
}

/**
 * @param {string} name
 * @param {Uint8Array} bytes
 */
export async function precheck(name, bytes) {
  const ext = (name.match(/\.([a-z0-9]+)$/i) || [, ''])[1].toLowerCase();
  try {
    if (['docx', 'docm', 'dotx'].includes(ext)) return await checkDocx(bytes);
    if (['pptx', 'pptm', 'potx'].includes(ext)) return await checkPptx(bytes);
    if (['xlsx', 'xlsm', 'xltx'].includes(ext)) return await checkXlsx(bytes);
    if (ext === 'pdf') return await checkPdf(bytes);
    if (['txt', 'md', 'csv', 'rtf', 'htm', 'html', 'xml', 'json'].includes(ext)) {
      const t = td.decode(bytes.subarray(0, 4 * 1024 * 1024));
      return BANNER_RE.test(t) ? { status: 'found', detail: 'Found "CUI" in the text.' } : { status: 'missing', detail: 'No "CUI" banner found in the text.' };
    }
    if (['doc', 'xls', 'ppt'].includes(ext)) {
      const t = new TextDecoder('utf-16le').decode(bytes) + new TextDecoder('latin1').decode(bytes);
      return /\bCUI\b/.test(t) ? { status: 'found', detail: 'Found "CUI" text in this legacy Office file. Could not verify placement.' } : { status: 'partial', detail: 'Could not verify a banner in this legacy Office format. Confirm it appears on every page.' };
    }
    return { status: 'unknown', detail: 'Cannot inspect this file type. Confirm the file is marked before sending.' };
  } catch (e) {
    return { status: 'unknown', detail: `Could not inspect this file (${e.message}). Confirm the file is marked before sending.` };
  }
}
