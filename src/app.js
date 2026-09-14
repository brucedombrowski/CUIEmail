// app.js - user interface. Vanilla DOM, no dependencies, works from file:// with no network.
import * as M from './marking.js';
import * as L from './cuilock.js';
import { precheck } from './precheck.js';
import { WORDLIST } from './wordlist.js';

const APP_VERSION = '__VERSION__';
const HOSTED_URL = 'https://brucedombrowski.github.io/CUIEmail/';
const UNLOCKER_NAME = 'CUIEmail.html';
const MAX_ATTACH_BYTES = 20 * 1024 * 1024;
const PS_ONELINER = String.raw`$f=Read-Host 'Path to the .locked file';$p=Read-Host 'Passphrase';$b=[IO.File]::ReadAllBytes($f);if([Text.Encoding]::ASCII.GetString($b,0,4) -ne 'CUIL'){throw 'Not a .locked file'};$i=[BitConverter]::ToUInt32([byte[]]($b[9],$b[8],$b[7],$b[6]),0);$n=[BitConverter]::ToUInt32([byte[]]($b[45],$b[44],$b[43],$b[42]),0);$h=[Text.Encoding]::UTF8.GetString($b,46,$n)|ConvertFrom-Json;$o=46+$n;$k=[Security.Cryptography.Rfc2898DeriveBytes]::new($p.Normalize(),[byte[]]$b[10..25],$i,[Security.Cryptography.HashAlgorithmName]::SHA256).GetBytes(64);$m=[Security.Cryptography.HMACSHA256]::new([byte[]]$k[32..63]);$t=$m.ComputeHash($b,0,$b.Length-32);if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$t,[byte[]]$b[($b.Length-32)..($b.Length-1)])){throw 'Wrong passphrase, or the file was altered'};$a=[Security.Cryptography.Aes]::Create();$a.Key=[byte[]]$k[0..31];$a.IV=[byte[]]$b[26..41];$d=$a.CreateDecryptor().TransformFinalBlock($b,$o,$b.Length-$o-32);$out=Join-Path (Split-Path -Parent $f) $h.name;[IO.File]::WriteAllBytes($out,$d);"Unlocked: $out"`;

// Captured before any change so a byte-equivalent copy of this page can be saved next to the locked files.
const PRISTINE_HTML = '<!DOCTYPE html>\n' + document.documentElement.outerHTML;

const $ = (id) => document.getElementById(id);
const el = (tag, attrs = {}, ...children) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') n.className = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else if (k === 'html') n.innerHTML = v;
    else n.setAttribute(k, v);
  }
  for (const c of children) n.append(c);
  return n;
};
const fmtSize = (n) => n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(0)} KB` : `${(n / 1048576).toFixed(1)} MB`;

const store = {
  get(k, d) { try { const v = localStorage.getItem('sce.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('sce.' + k, JSON.stringify(v)); } catch { /* ignore */ } },
};

const state = {
  files: [],          // {name, size, bytes, check}
  categories: [],     // {marking, specified}
  ldcs: [],           // {code, list?}
  designation: { controlledBy: '', controlledBy2: '', poc: '', decontrol: '' },
  subject: '',
  passphrase: '',
  custom: false,
  results: null,
};

// ---------- navigation ----------
function show(view) {
  for (const v of document.querySelectorAll('.view')) v.classList.add('hidden');
  $(`view-${view}`).classList.remove('hidden');
  $('nav-home').classList.toggle('hidden', view === 'home');
  window.scrollTo(0, 0);
}
$('go-send').onclick = () => show('send');
$('go-open').onclick = () => show('open');
$('go-help').onclick = () => show('help');
$('open-help').onclick = () => { show('help'); $('fallback').scrollIntoView(); };
$('nav-home').onclick = () => show('home');
$('version').textContent = 'v' + APP_VERSION;
$('ps-oneliner').textContent = PS_ONELINER;
$('ps-copy').onclick = () => copyText(PS_ONELINER, $('ps-copy'));
$('help-hosted').textContent = HOSTED_URL; $('help-hosted').href = HOSTED_URL;

async function copyText(text, btn) {
  try { await navigator.clipboard.writeText(text); flash(btn, 'Copied'); }
  catch { flash(btn, 'Select and copy manually'); }
}
function flash(btn, msg) { const t = btn.textContent; btn.textContent = msg; setTimeout(() => (btn.textContent = t), 1500); }
function renderMsgs(container, msgs) {
  container.replaceChildren(...msgs.map((m) => el('div', { class: `msg ${m.level}` }, m.text)));
}

// ---------- step 1: files ----------
function wireDropzone(zone, input, onFiles) {
  zone.onclick = () => input.click();
  zone.onkeydown = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.click(); } };
  zone.ondragover = (e) => { e.preventDefault(); zone.classList.add('over'); };
  zone.ondragleave = () => zone.classList.remove('over');
  zone.ondrop = (e) => { e.preventDefault(); zone.classList.remove('over'); onFiles([...e.dataTransfer.files]); };
  input.onchange = () => { onFiles([...input.files]); input.value = ''; };
}
wireDropzone($('dropzone'), $('file-input'), addFiles);

async function addFiles(files) {
  for (const f of files) {
    if (state.files.some((x) => x.name === f.name)) continue;
    const bytes = new Uint8Array(await f.arrayBuffer());
    const entry = { name: f.name, size: f.size, bytes, check: { status: 'unknown', detail: 'Checking...' } };
    state.files.push(entry);
    renderFiles();
    entry.check = await precheck(f.name, bytes);
    renderFiles();
  }
}
function renderFiles() {
  const list = $('file-list');
  list.replaceChildren(...state.files.map((f, i) => {
    const li = el('li', {},
      el('div', { class: 'file-name' }, f.name),
      el('div', { class: 'file-size' }, fmtSize(f.size)),
      el('div', { class: `file-check ${f.check.status}` }, (f.check.status === 'found' ? 'OK: ' : f.check.status === 'missing' ? 'Not found: ' : 'Check: ') + f.check.detail),
      el('button', { class: 'link file-remove', type: 'button', onclick: () => { state.files.splice(i, 1); renderFiles(); } }, 'Remove'));
    return li;
  }));
  const needAck = state.files.some((f) => f.check.status !== 'found');
  $('file-ack-wrap').classList.toggle('hidden', !needAck);
  if (!needAck) $('file-ack').checked = false;
  refreshGo();
}
$('file-ack').onchange = refreshGo;

// ---------- step 2: marking ----------
function catByMarking(m) { return M.CATEGORIES.find((c) => c.marking === m); }
function isSelected(m) { return state.categories.some((c) => c.marking === m); }
function toggleCategory(marking) {
  const i = state.categories.findIndex((c) => c.marking === marking);
  if (i >= 0) state.categories.splice(i, 1);
  else {
    const def = catByMarking(marking);
    const remembered = store.get('kind.' + marking, null);
    const specified = def.kinds.length === 1 ? def.kinds[0] === 'Specified' : (remembered ?? undefined);
    state.categories.push({ marking, specified });
  }
  renderMarking();
}
function renderCommonChips() {
  $('cat-common').replaceChildren(...M.COMMON_CATEGORY_MARKINGS.map((m) => {
    const def = catByMarking(m);
    if (!def) return el('span');
    return el('button', { class: 'chip' + (isSelected(m) ? ' on' : ''), type: 'button', title: def.desc, onclick: () => toggleCategory(m) }, `${def.name} (${m})`);
  }));
}
$('cat-search').oninput = () => {
  const q = $('cat-search').value.trim().toLowerCase();
  const box = $('cat-results');
  if (!q) { box.classList.add('hidden'); return; }
  const hits = M.CATEGORIES.filter((c) => c.name.toLowerCase().includes(q) || c.marking.toLowerCase().includes(q) || c.group.toLowerCase().includes(q)).slice(0, 30);
  box.replaceChildren(...hits.map((c) => el('button', { type: 'button', onclick: () => { toggleCategory(c.marking); $('cat-search').value = ''; box.classList.add('hidden'); } },
    el('div', {}, `${c.name} (${c.marking})${isSelected(c.marking) ? ' - selected' : ''}`), el('div', { class: 'grp' }, `${c.group} · ${c.kinds.join(' or ')}`))));
  if (!hits.length) box.replaceChildren(el('div', { class: 'grp', style: 'padding:10px 12px' }, 'No match'));
  box.classList.remove('hidden');
};
document.addEventListener('click', (e) => { if (!e.target.closest('.search-row')) $('cat-results').classList.add('hidden'); });

function renderSelectedCats() {
  $('cat-selected').replaceChildren(...state.categories.map((c) => {
    const def = catByMarking(c.marking);
    const box = el('div', { class: 'sel' },
      el('div', { class: 'title' }, `${def.name} (${def.marking}) `, el('span', { class: 'muted' }, `· ${def.group} · `), el('a', { href: def.url, target: '_blank', rel: 'noopener' }, 'Registry entry')),
      el('div', { class: 'desc' }, def.desc));
    if (def.kinds.length === 2) {
      const kind = el('div', { class: 'kind' }, el('span', {}, 'This category can be Basic or Specified. Which applies?'));
      for (const [label, val] of [['Basic', false], [`Specified (SP-${def.marking})`, true]]) {
        const r = el('input', { type: 'radio', name: 'kind-' + def.marking });
        r.checked = c.specified === val;
        r.onchange = () => { c.specified = val; store.set('kind.' + def.marking, val); renderMarking(); };
        kind.append(el('label', {}, r, label));
      }
      kind.append(el('details', { class: 'help' }, el('summary', {}, 'How do I know?'), el('p', {}, 'Open the Registry entry. Each authority (law or regulation) is listed as Basic or Specified. If the authority that applies to your information is listed as Specified, choose Specified. If you are not sure, ask your CUI program office.')));
      box.append(kind);
    } else {
      box.append(el('div', { class: 'muted' }, def.kinds[0] === 'Specified' ? `Always CUI Specified: marked SP-${def.marking}.` : 'CUI Basic.'));
    }
    box.append(el('button', { class: 'link', type: 'button', onclick: () => toggleCategory(c.marking) }, 'Remove'));
    return box;
  }));
}

function ldcSel(code) { return state.ldcs.find((l) => l.code === code); }
function renderLdcs() {
  const ALL_CODES = [...M.TRIGRAPHS.map((t) => ({ code: t[1], name: t[0] })), ...M.TETRAGRAPHS.map((t) => ({ code: t, name: t }))];
  $('ldc-list').replaceChildren(...M.LDCS.map((d) => {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = !!ldcSel(d.code);
    cb.onchange = () => {
      if (cb.checked) state.ldcs.push({ code: d.code, list: d.list ? ['USA'] : undefined });
      else state.ldcs = state.ldcs.filter((l) => l.code !== d.code);
      renderMarking();
    };
    const lab = el('label', {}, cb, ' ', el('b', {}, d.code), d.name, el('span', { class: 'desc' }, d.desc));
    const sel = ldcSel(d.code);
    if (d.list && sel) {
      const inp = el('input', { type: 'search', placeholder: 'Add a country or organization (name or code)', autocomplete: 'off' });
      const res = el('div', { class: 'search-results hidden' });
      const picked = el('div', { class: 'picked' });
      const renderPicked = () => picked.replaceChildren(...M.orderedReleaseList(sel.list).map((c) => el('span', {}, c, c === 'USA' ? '' : el('button', { class: 'link', type: 'button', style: 'margin-left:6px', onclick: () => { sel.list = sel.list.filter((x) => x !== c); renderMarking(); } }, '×'))));
      renderPicked();
      inp.oninput = () => {
        const q = inp.value.trim().toLowerCase();
        if (!q) { res.classList.add('hidden'); return; }
        const hits = ALL_CODES.filter((x) => x.code.toLowerCase().includes(q) || x.name.toLowerCase().includes(q)).slice(0, 15);
        res.replaceChildren(...hits.map((x) => el('button', { type: 'button', onclick: () => { if (!sel.list.includes(x.code)) sel.list.push(x.code); inp.value = ''; res.classList.add('hidden'); renderMarking(); } }, `${x.name} (${x.code})`)));
        res.classList.remove('hidden');
      };
      inp.onclick = (e) => e.stopPropagation();
      lab.onclick = (e) => { if (e.target !== cb && e.target.closest('.rel-list')) e.preventDefault(); };
      lab.append(el('div', { class: 'rel-list' }, el('div', { class: 'search-row' }, inp, res), picked));
    }
    return lab;
  }));
}
function currentSel() { return { categories: state.categories, ldcs: state.ldcs }; }
function renderMarking() {
  renderCommonChips();
  renderSelectedCats();
  renderLdcs();
  $('banner').textContent = M.buildBanner(currentSel());
  renderMsgs($('marking-msgs'), M.validateMarking(currentSel()));
  store.set('categories', state.categories);
  store.set('ldcs', state.ldcs);
  refreshGo();
}

// ---------- step 3: designation ----------
for (const k of ['controlledBy', 'controlledBy2', 'poc', 'decontrol']) {
  const input = $('d-' + k);
  input.value = store.get('d.' + k, '');
  state.designation[k] = input.value;
  input.oninput = () => { state.designation[k] = input.value.trim(); store.set('d.' + k, state.designation[k]); renderDesignation(); };
}
function renderDesignation() { renderMsgs($('designation-msgs'), M.validateDesignation(state.designation)); refreshGo(); }

// ---------- step 4: subject ----------
$('subject').oninput = () => { state.subject = $('subject').value; refreshGo(); };

// ---------- step 5: passphrase ----------
function randomIndex(n) { // uniform in [0, n)
  const max = Math.floor(65536 / n) * n;
  const buf = new Uint16Array(1);
  for (;;) { crypto.getRandomValues(buf); if (buf[0] < max) return buf[0] % n; }
}
function generatePassphrase() {
  const words = [];
  for (let i = 0; i < 5; i++) words.push(WORDLIST[randomIndex(WORDLIST.length)]);
  return words.join('-');
}
function setGenerated() { state.passphrase = generatePassphrase(); $('pass-display').textContent = state.passphrase; refreshGo(); }
setGenerated();
$('pass-regen').onclick = setGenerated;
$('pass-copy').onclick = () => copyText(currentPassphrase(), $('pass-copy'));
$('pass-custom-toggle').onclick = () => {
  state.custom = !state.custom;
  $('pass-custom').classList.toggle('hidden', !state.custom);
  $('pass-display').classList.toggle('hidden', state.custom);
  $('pass-regen').classList.toggle('hidden', state.custom);
  $('pass-custom-toggle').textContent = state.custom ? 'Use a generated passphrase instead' : 'Use my own passphrase instead';
  refreshGo();
};
$('pass-show').onchange = () => { const t = $('pass-show').checked ? 'text' : 'password'; $('pass-1').type = t; $('pass-2').type = t; };
$('pass-1').oninput = refreshGo; $('pass-2').oninput = refreshGo;
function currentPassphrase() { return state.custom ? $('pass-1').value : state.passphrase; }

// ---------- step 6: readiness ----------
function blockers() {
  const out = [];
  if (!state.files.length) out.push({ level: 'error', text: 'Choose at least one file (step 1).' });
  const needAck = state.files.some((f) => f.check.status !== 'found');
  if (needAck && !$('file-ack').checked) out.push({ level: 'error', text: 'Confirm that the files are marked (step 1).' });
  const big = state.files.filter((f) => f.size > MAX_ATTACH_BYTES);
  if (big.length) out.push({ level: 'warn', text: `Large file(s): ${big.map((f) => f.name).join(', ')}. Many mail systems reject attachments over 20 MB.` });
  for (const m of M.validateMarking(currentSel())) if (m.level === 'error') out.push({ level: 'error', text: m.text + ' (step 2)' });
  for (const m of M.validateDesignation(state.designation)) if (m.level === 'error') out.push({ level: 'error', text: m.text + ' (step 3)' });
  if (!state.subject.trim()) out.push({ level: 'error', text: 'Enter an email subject (step 4).' });
  if (state.custom) {
    const a = $('pass-1').value, b = $('pass-2').value;
    if (a.length < 12) out.push({ level: 'error', text: 'Passphrase must be at least 12 characters (step 5).' });
    else if (a !== b) out.push({ level: 'error', text: 'The two passphrase entries do not match (step 5).' });
  }
  return out;
}
function refreshGo() {
  const b = blockers();
  renderMsgs($('go-msgs'), b);
  $('go-lock').disabled = b.some((m) => m.level === 'error');
}

// ---------- lock & save ----------
async function saveOutputs(outputs) {
  if (window.showDirectoryPicker) {
    try {
      const dir = await window.showDirectoryPicker({ mode: 'readwrite', id: 'cuiemail-out', startIn: 'desktop' });
      for (const o of outputs) {
        const fh = await dir.getFileHandle(o.name, { create: true });
        const w = await fh.createWritable();
        await w.write(o.data);
        await w.close();
      }
      return { mode: 'folder', where: dir.name };
    } catch (e) {
      if (e.name === 'AbortError') return { mode: 'cancel' };
      // fall through to downloads
    }
  }
  for (const o of outputs) {
    const a = el('a', { href: URL.createObjectURL(new Blob([o.data])), download: o.name });
    document.body.append(a); a.click(); a.remove();
    await new Promise((r) => setTimeout(r, 400));
  }
  return { mode: 'download', where: 'your Downloads folder' };
}

$('go-lock').onclick = async () => {
  if (blockers().some((m) => m.level === 'error')) return;
  const btn = $('go-lock');
  btn.disabled = true;
  const prog = $('progress'); prog.classList.remove('hidden');
  try {
    const passphrase = currentPassphrase();
    const sel = currentSel();
    const banner = M.buildBanner(sel);
    const di = M.designationIndicator(state.designation, sel);
    const outputs = [];
    for (const f of state.files) {
      prog.textContent = `Locking ${f.name}...`;
      const header = { v: 1, name: f.name, size: f.size, banner, designation: di, created: new Date().toISOString(), tool: 'CUIEmail ' + APP_VERSION };
      const data = await L.lock(f.bytes, passphrase, header);
      outputs.push({ name: L.lockedName(f.name), data });
    }
    outputs.push({ name: UNLOCKER_NAME, data: new TextEncoder().encode(PRISTINE_HTML) });
    prog.textContent = 'Choose where to save the locked files...';
    const saved = await saveOutputs(outputs);
    if (saved.mode === 'cancel') { prog.textContent = 'Cancelled. Nothing was saved.'; btn.disabled = false; return; }
    const subject = M.emailSubject(state.subject);
    const body = M.emailBody({ banner, files: outputs.map((o) => o.name), designationLines: di, hostedUrl: HOSTED_URL, unlockerName: UNLOCKER_NAME });
    state.results = { subject, body, passphrase, outputs: outputs.map((o) => o.name), saved };
    renderDone();
    prog.textContent = '';
    prog.classList.add('hidden');
  } catch (e) {
    prog.textContent = 'Something went wrong: ' + (e.message || e);
    btn.disabled = false;
  }
};
function renderDone() {
  const r = state.results;
  $('save-summary').replaceChildren(
    el('div', {}, r.saved.mode === 'folder' ? `Saved to the folder "${r.saved.where}":` : `Saved to ${r.saved.where}:`),
    el('ul', {}, ...r.outputs.map((n) => el('li', {}, el('code', {}, n)))));
  $('email-subject').textContent = r.subject;
  $('email-body').textContent = r.body;
  $('pass-final').textContent = r.passphrase;
  $('step-done').classList.remove('hidden');
  $('step-done').scrollIntoView({ behavior: 'smooth' });
}
$('email-open').onclick = () => { window.location.href = M.mailtoUrl(state.results.subject, state.results.body); };
$('email-copy-subject').onclick = () => copyText(state.results.subject, $('email-copy-subject'));
$('email-copy-body').onclick = () => copyText(state.results.body, $('email-copy-body'));

// ---------- OPEN ----------
let openFile = null; // {name, bytes, peek}
wireDropzone($('open-dropzone'), $('open-input'), async (files) => {
  const f = files[0]; if (!f) return;
  const bytes = new Uint8Array(await f.arrayBuffer());
  $('open-result').replaceChildren();
  try {
    const p = L.peek(bytes);
    openFile = { name: f.name, bytes, peek: p };
    $('open-banner').textContent = p.header.banner || 'CUI';
    const meta = [['File', f.name], ['Contains', `${p.header.name || L.unlockedNameFromContainer(f.name)} (${fmtSize(p.header.size ?? 0)})`], ['Locked on', p.header.created ? new Date(p.header.created).toLocaleString() : 'unknown']];
    for (const line of p.header.designation || []) { const i = line.indexOf(':'); meta.push([line.slice(0, i), line.slice(i + 1).trim()]); }
    $('open-meta').replaceChildren(...meta.flatMap(([k, v]) => [el('dt', {}, k), el('dd', {}, v)]));
    $('open-info').classList.remove('hidden');
    renderMsgs($('open-msgs'), []);
    $('open-pass').focus();
  } catch (e) {
    openFile = null;
    $('open-info').classList.add('hidden');
    renderMsgs($('open-msgs'), [{ level: 'error', text: e.message }]);
  }
});
$('open-show').onchange = () => { $('open-pass').type = $('open-show').checked ? 'text' : 'password'; };
$('open-pass').onkeydown = (e) => { if (e.key === 'Enter') $('open-unlock').click(); };
$('open-unlock').onclick = async () => {
  const out = $('open-result');
  if (!openFile) { renderMsgs(out, [{ level: 'error', text: 'Pick the .locked file first.' }]); return; }
  const pass = $('open-pass').value;
  if (!pass) { renderMsgs(out, [{ level: 'error', text: 'Enter the passphrase.' }]); return; }
  $('open-unlock').disabled = true;
  renderMsgs(out, [{ level: 'ok', text: 'Checking passphrase...' }]);
  try {
    let result;
    try { result = await L.unlock(openFile.bytes, pass); }
    catch (e) {
      // Generated passphrases are lower-case words; forgive capitalization and spaces from a phone call.
      const alt = pass.trim().toLowerCase().replace(/[\s_]+/g, '-');
      if (alt !== pass) result = await L.unlock(openFile.bytes, alt); else throw e;
    }
    const name = result.header.name || L.unlockedNameFromContainer(openFile.name);
    const saved = await saveOne(name, result.plaintext);
    if (saved === 'cancel') renderMsgs(out, [{ level: 'warn', text: 'Unlocked, but saving was cancelled. Click "Unlock and save" again to choose a location.' }]);
    else renderMsgs(out, [{ level: 'ok', text: `Unlocked and saved "${name}"${saved === 'download' ? ' to your Downloads folder' : ''}. Handle it as ${result.header.banner || 'CUI'}.` }]);
  } catch (e) {
    renderMsgs(out, [{ level: 'error', text: e.message || String(e) }]);
  } finally {
    $('open-unlock').disabled = false;
  }
};
async function saveOne(name, data) {
  if (window.showSaveFilePicker) {
    try {
      const fh = await window.showSaveFilePicker({ suggestedName: name });
      const w = await fh.createWritable(); await w.write(data); await w.close();
      return 'picker';
    } catch (e) { if (e.name === 'AbortError') return 'cancel'; }
  }
  const a = el('a', { href: URL.createObjectURL(new Blob([data])), download: name });
  document.body.append(a); a.click(); a.remove();
  return 'download';
}

// ---------- init ----------
state.categories = store.get('categories', []).filter((c) => catByMarking(c.marking));
state.ldcs = store.get('ldcs', []).filter((l) => M.LDCS.some((d) => d.code === l.code));
renderMarking();
renderDesignation();
refreshGo();
if (!window.crypto?.subtle) {
  document.body.prepend(el('div', { class: 'msg error' }, 'This browser does not provide Web Crypto, so files cannot be locked or unlocked here. Use a current version of Microsoft Edge or Google Chrome.'));
}
