// marking.js - CUI banner construction, validation, designation indicator, and email text.
// Every rule here cites its source. See docs/MARKING-COMPLIANCE.md for the full trace.
//
// Sources (abbreviated in comments):
//   CFR   = 32 CFR 2002.20 (Marking)
//   HB    = NARA CUI Marking Handbook v1.1 (page numbers)
//   REG   = CUI Registry, Limited Dissemination Controls page (archives.gov/cui/registry/limited-dissemination)
//   NPR   = NASA NPR 2810.7 Change 1, section 2.2
//   ISOO  = ISOO "CUI, Emails, and Marking" tip sheet (2018-06-05)

import CATEGORIES from './data/categories.json' with { type: 'json' };
import LDCS from './data/ldcs.json' with { type: 'json' };
import TRIGRAPHS from './data/trigraphs.json' with { type: 'json' };
import TETRAGRAPHS from './data/tetragraphs.json' with { type: 'json' };

export { CATEGORIES, LDCS, TRIGRAPHS, TETRAGRAPHS };

// CFR (b)(1)(i): "CONTROLLED" or "CUI" at the designator's discretion; NPR 2810.7 definitions:
// "Controlled ... Note: NASA will not use this banner marking." DoD also uses "CUI". Fixed to "CUI".
export const CONTROL_MARKING = 'CUI';

// Categories this tool offers first. Everything else is reachable through search.
export const COMMON_CATEGORY_MARKINGS = ['EXPT', 'CTI', 'PRVCY', 'PROPIN', 'ISVI', 'OPSEC', 'PROCURE', 'SSEL', 'INTL', 'PERS', 'PHYS', 'CEII'];

export function findCategory(marking) {
  return CATEGORIES.find((c) => c.marking === marking) || null;
}

const TRIGRAPH_SET = new Set(TRIGRAPHS.map((t) => t[1]));
const TETRAGRAPH_SET = new Set(TETRAGRAPHS);

function asciiCompare(a, b) {
  const x = a.toUpperCase(), y = b.toUpperCase();
  return x < y ? -1 : x > y ? 1 : 0;
}

/**
 * Category marking as it appears in a banner. HB p.9: Specified categories carry the "SP-" prefix.
 * @param {{marking:string, specified:boolean}} c
 */
export function categoryMarking(c) {
  return (c.specified ? 'SP-' : '') + c.marking;
}

/**
 * Order the category markings for a banner.
 * HB p.11: "CUI Specified Markings MUST precede CUI Basic Markings"; "CUI Category and Subcategory
 * Markings MUST be alphabetized within CUI type (Basic or Specified)."
 */
export function orderedCategoryMarkings(categories) {
  const sp = categories.filter((c) => c.specified).map(categoryMarking).sort(asciiCompare);
  const basic = categories.filter((c) => !c.specified).map(categoryMarking).sort(asciiCompare);
  return [...sp, ...basic];
}

/**
 * Normalize a REL TO / DISPLAY ONLY list.
 * REG: "1) USA must always appear first. 2) Followed by trigraph country code(s), in alphabetical order.
 *       3) Followed by tetragraph codes for coalition or international organization(s), in alphabetical order."
 */
export function orderedReleaseList(codes) {
  const set = new Set(codes.map((c) => c.toUpperCase()).filter((c) => c !== 'USA'));
  const tri = [...set].filter((c) => TRIGRAPH_SET.has(c)).sort();
  const tet = [...set].filter((c) => TETRAGRAPH_SET.has(c)).sort();
  return ['USA', ...tri, ...tet];
}

/** Render one LDC marking string. */
export function ldcMarking(l) {
  if (l.code === 'REL TO' || l.code === 'DISPLAY ONLY') {
    return `${l.code} ${orderedReleaseList(l.list || []).join(', ')}`;
  }
  return l.code;
}

/**
 * Order LDC markings. HB p.12: "When a document contains multiple Limited Dissemination Control
 * Markings, those ... MUST be alphabetized and separated from each other with a single forward slash (/)."
 */
export function orderedLdcMarkings(ldcs) {
  return ldcs.map(ldcMarking).sort(asciiCompare);
}

/**
 * Build the CUI banner marking.
 * HB p.5: "CONTROLLED or CUI//CATEGORIES/SUBCATEGORIES//DISSEM". Categories are separated from the control
 * marking by "//", multiple categories by "/", and LDCs are preceded by "//".
 * HB p.12 example "CUI//DISSEM-A/DISSEM-C" shows LDCs may follow the control marking directly when no category is used.
 * @param {{categories:Array<{marking:string,specified:boolean}>, ldcs:Array<{code:string,list?:string[]}>}} sel
 */
export function buildBanner(sel) {
  const cats = orderedCategoryMarkings(sel.categories || []);
  const ldcs = orderedLdcMarkings(sel.ldcs || []);
  let b = CONTROL_MARKING;
  if (cats.length) b += '//' + cats.join('/');
  if (ldcs.length) b += '//' + ldcs.join('/');
  return b;
}

/**
 * Validate a marking selection. Returns [{level:'error'|'warn', code, text}].
 * Errors block sending; warnings are shown and must be acknowledged by the sender.
 */
export function validateMarking(sel) {
  const out = [];
  const cats = sel.categories || [];
  const ldcs = sel.ldcs || [];
  const codes = new Set(ldcs.map((l) => l.code));
  const catMarkings = new Set(cats.map((c) => c.marking));

  for (const c of cats) {
    const def = findCategory(c.marking);
    if (!def) { out.push({ level: 'error', code: 'UNKNOWN_CATEGORY', text: `"${c.marking}" is not a category marking in the CUI Registry.` }); continue; }
    // CFR (b)(2)(iii): all Specified categories present must appear in the banner. A category whose authorities are
    // all Specified cannot be marked Basic, and vice versa.
    if (c.specified && !def.kinds.includes('Specified')) out.push({ level: 'error', code: 'NOT_SPECIFIED', text: `${def.name} (${def.marking}) has no CUI Specified authority in the Registry; it must be marked Basic.` });
    if (!c.specified && !def.kinds.includes('Basic')) out.push({ level: 'error', code: 'NOT_BASIC', text: `${def.name} (${def.marking}) is CUI Specified only; it must be marked SP-${def.marking}.` });
    if (def.kinds.length === 2 && c.specified === undefined) out.push({ level: 'error', code: 'KIND_REQUIRED', text: `${def.name} (${def.marking}) can be Basic or Specified. Choose one.` });
  }
  if (cats.length === 0) {
    // CFR (b)(2)(ii): category markings are optional for CUI Basic. Allowed, but easy to get wrong.
    out.push({ level: 'warn', code: 'NO_CATEGORY', text: 'No CUI category selected. The banner will read "CUI" alone, which is allowed only if every file is CUI Basic and your agency does not require category markings.' });
  }

  // REG: NOFORN forbids any foreign dissemination; REL TO / DISPLAY ONLY authorize it. They contradict.
  if (codes.has('NOFORN') && (codes.has('REL TO') || codes.has('DISPLAY ONLY'))) out.push({ level: 'error', code: 'NOFORN_CONFLICT', text: 'NOFORN cannot be combined with REL TO or DISPLAY ONLY.' });
  // REG: FED ONLY excludes contractors; FEDCON includes them. They contradict.
  if (codes.has('FED ONLY') && codes.has('FEDCON')) out.push({ level: 'error', code: 'FED_CONFLICT', text: 'FED ONLY and FEDCON cannot both apply. Choose one.' });
  if (codes.has('NOCON') && codes.has('FEDCON')) out.push({ level: 'error', code: 'NOCON_CONFLICT', text: 'NOCON and FEDCON contradict each other. Choose one.' });
  if (codes.has('NOCON') && codes.has('FED ONLY')) out.push({ level: 'warn', code: 'NOCON_REDUNDANT', text: 'FED ONLY already excludes contractors; NOCON adds nothing here.' });
  // REG note on DL ONLY: "Use of this limited dissemination control supersedes other limited dissemination controls".
  if (codes.has('DL ONLY') && codes.size > 1) out.push({ level: 'warn', code: 'DL_ONLY_SUPERSEDES', text: 'DL ONLY supersedes the other dissemination controls you selected. Make sure the dissemination list is sent with the files.' });
  if (codes.has('DL ONLY')) out.push({ level: 'warn', code: 'DL_ONLY_LIST', text: 'DL ONLY requires an accompanying dissemination list. Include it in one of the locked files.' });
  // REG: Attorney-Client and Attorney-WP are "for use only with the Legal Privilege category".
  for (const code of ['Attorney-Client', 'Attorney-WP']) {
    if (codes.has(code) && !catMarkings.has('PRIVILEGE')) out.push({ level: 'error', code: 'PRIVILEGE_REQUIRED', text: `${code} may only be used with the Legal Privilege (PRIVILEGE) category.` });
  }
  for (const l of ldcs) {
    if (l.code === 'REL TO' || l.code === 'DISPLAY ONLY') {
      const list = orderedReleaseList(l.list || []);
      if (list.length < 2) out.push({ level: 'error', code: 'REL_LIST_EMPTY', text: `${l.code} needs at least one country or organization besides USA.` });
      const unknown = (l.list || []).map((c) => c.toUpperCase()).filter((c) => c !== 'USA' && !TRIGRAPH_SET.has(c) && !TETRAGRAPH_SET.has(c));
      if (unknown.length) out.push({ level: 'error', code: 'REL_UNKNOWN_CODE', text: `Unknown country/organization code(s): ${unknown.join(', ')}.` });
    }
  }
  return out;
}

/**
 * Designation indicator lines.
 * CFR (d): every document must show the designator's agency (at minimum), e.g. a "Controlled by:" line.
 * HB p.13: "Every effort should be made to identify a point of contact, branch, or division ... and to include contact information."
 * CFR (e): where feasible include a decontrol date or event.
 */
export function designationIndicator(d, sel) {
  const lines = [];
  if (d.controlledBy) lines.push(`Controlled by: ${d.controlledBy}`);
  if (d.controlledBy2) lines.push(`Controlled by: ${d.controlledBy2}`);
  const cats = orderedCategoryMarkings(sel.categories || []);
  if (cats.length) lines.push(`CUI Category${cats.length > 1 ? '(ies)' : ''}: ${cats.join(', ')}`);
  const ldcs = orderedLdcMarkings(sel.ldcs || []);
  if (ldcs.length) lines.push(`Limited Dissemination Control: ${ldcs.join(', ')}`);
  if (d.poc) lines.push(`POC: ${d.poc}`);
  if (d.decontrol) lines.push(`Decontrol: ${d.decontrol}`);
  return lines;
}

export function validateDesignation(d) {
  const out = [];
  if (!d.controlledBy || !d.controlledBy.trim()) out.push({ level: 'error', code: 'CONTROLLED_BY_REQUIRED', text: '"Controlled by" (your agency or organization) is required on every CUI document (32 CFR 2002.20(d)).' });
  if (!d.poc || !d.poc.trim()) out.push({ level: 'warn', code: 'POC_RECOMMENDED', text: 'No point of contact given. The NARA handbook says every effort should be made to include one with contact information.' });
  return out;
}

/**
 * Email subject. Begins with "CUI" so it satisfies both the ISOO tip sheet (an indicator "can" appear in the
 * subject) and DoD/DON practice (subject line begins with "CUI"). The topic must not itself contain CUI.
 */
export function emailSubject(topic) {
  const t = (topic || '').trim();
  return t ? `CUI - ${t}` : 'CUI';
}

/**
 * Plain-text email body (transmittal document).
 * NPR 2.2.8 / ISOO: banner at the top of the email body. HB p.6: bottom banner is an optional best practice
 * (DoD requires it), so it is included.
 * CFR (j): a transmittal must state that CUI is attached and carry the "When enclosure is removed..." notice.
 * CFR (d): designation indicator.
 */
export function emailBody({ banner, files, designationLines, hostedUrl, unlockerName }) {
  const lines = [];
  lines.push(banner, '');
  lines.push('This email transmits Controlled Unclassified Information (CUI) in the encrypted attachments listed below.');
  lines.push('When the attachments are removed, this message is Uncontrolled Unclassified Information.');
  lines.push('');
  lines.push('Encrypted attachments:');
  for (const f of files) lines.push(`  - ${f}`);
  lines.push('');
  lines.push('To open them:');
  lines.push(`  1. Save the attachments to your computer.`);
  lines.push(`  2. Double-click the attached ${unlockerName} (or open ${hostedUrl}).`);
  lines.push(`  3. Choose "Open a locked file", pick a .locked file, and enter the passphrase.`);
  lines.push('The passphrase is sent separately by phone or text message. It is never sent by email.');
  lines.push('');
  lines.push(...designationLines);
  lines.push('', banner);
  return lines.join('\r\n');
}

/** Build a mailto: URL (no recipient; the sender fills that in). */
export function mailtoUrl(subject, body) {
  return 'mailto:?subject=' + encodeURIComponent(subject) + '&body=' + encodeURIComponent(body);
}
