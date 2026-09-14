import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as M from '../src/marking.js';

const cat = (marking, specified) => ({ marking, specified });

test('control marking is CUI (NASA does not use CONTROLLED)', () => {
  assert.equal(M.buildBanner({ categories: [], ldcs: [] }), 'CUI');
});

test('Specified categories get SP- and precede Basic; each group alphabetized (HB p.9, p.11)', () => {
  const b = M.buildBanner({ categories: [cat('PRVCY', false), cat('EXPT', true), cat('CTI', true), cat('ISVI', false)], ldcs: [] });
  assert.equal(b, 'CUI//SP-CTI/SP-EXPT/ISVI/PRVCY');
});

test('LDCs follow // and are alphabetized with / (HB p.12)', () => {
  const b = M.buildBanner({ categories: [cat('EXPT', true)], ldcs: [{ code: 'NOFORN' }, { code: 'FED ONLY' }] });
  assert.equal(b, 'CUI//SP-EXPT//FED ONLY/NOFORN');
});

test('LDCs without categories attach directly to the control marking (HB p.12 example CUI//DISSEM-A/DISSEM-C)', () => {
  assert.equal(M.buildBanner({ categories: [], ldcs: [{ code: 'FEDCON' }] }), 'CUI//FEDCON');
});

test('REL TO: USA first, trigraphs alphabetized, then tetragraphs alphabetized (Registry LDC page)', () => {
  const l = { code: 'REL TO', list: ['NATO', 'GBR', 'USA', 'AUS', 'FVEY', 'CAN'] };
  assert.equal(M.ldcMarking(l), 'REL TO USA, AUS, CAN, GBR, FVEY, NATO');
  assert.equal(M.ldcMarking({ code: 'DISPLAY ONLY', list: ['JPN'] }), 'DISPLAY ONLY USA, JPN');
});

test('validation: contradictory LDC combinations are errors', () => {
  const codes = (r) => r.filter((m) => m.level === 'error').map((m) => m.code);
  assert.ok(codes(M.validateMarking({ categories: [cat('EXPT', true)], ldcs: [{ code: 'NOFORN' }, { code: 'REL TO', list: ['USA', 'GBR'] }] })).includes('NOFORN_CONFLICT'));
  assert.ok(codes(M.validateMarking({ categories: [cat('EXPT', true)], ldcs: [{ code: 'FED ONLY' }, { code: 'FEDCON' }] })).includes('FED_CONFLICT'));
  assert.ok(codes(M.validateMarking({ categories: [cat('EXPT', true)], ldcs: [{ code: 'NOCON' }, { code: 'FEDCON' }] })).includes('NOCON_CONFLICT'));
  assert.ok(codes(M.validateMarking({ categories: [cat('EXPT', true)], ldcs: [{ code: 'Attorney-Client' }] })).includes('PRIVILEGE_REQUIRED'));
  assert.deepEqual(codes(M.validateMarking({ categories: [cat('PRIVILEGE', false)], ldcs: [{ code: 'Attorney-Client' }] })), []);
  assert.ok(codes(M.validateMarking({ categories: [], ldcs: [{ code: 'REL TO', list: ['USA'] }] })).includes('REL_LIST_EMPTY'));
  assert.ok(codes(M.validateMarking({ categories: [], ldcs: [{ code: 'REL TO', list: ['USA', 'ZZZ'] }] })).includes('REL_UNKNOWN_CODE'));
});

test('validation: Basic/Specified must agree with the Registry authorities', () => {
  const codes = (r) => r.map((m) => m.code);
  assert.ok(codes(M.validateMarking({ categories: [cat('CTI', false)], ldcs: [] })).includes('NOT_BASIC'));
  assert.ok(codes(M.validateMarking({ categories: [cat('ISVI', true)], ldcs: [] })).includes('NOT_SPECIFIED'));
  assert.ok(codes(M.validateMarking({ categories: [cat('EXPT', undefined)], ldcs: [] })).includes('KIND_REQUIRED'));
  assert.ok(codes(M.validateMarking({ categories: [], ldcs: [] })).includes('NO_CATEGORY'));
  assert.deepEqual(M.validateMarking({ categories: [cat('EXPT', true)], ldcs: [{ code: 'FEDCON' }] }), []);
});

test('registry data sanity', () => {
  assert.ok(M.CATEGORIES.length > 100);
  for (const c of M.CATEGORIES) { assert.match(c.marking, /^[A-Z0-9-]+$/); assert.ok(c.kinds.length >= 1); assert.ok(c.url.startsWith('https://www.archives.gov/')); }
  assert.deepEqual(M.findCategory('CTI').kinds, ['Specified']);
  assert.deepEqual(M.findCategory('EXPT').kinds, ['Basic', 'Specified']);
  assert.equal(M.LDCS.length, 9);
  assert.ok(!M.TRIGRAPHS.some((t) => t[1] === 'USA'));
  assert.ok(M.TETRAGRAPHS.includes('NATO') && M.TETRAGRAPHS.includes('FVEY'));
});

test('designation indicator lines (32 CFR 2002.20(d),(e))', () => {
  const lines = M.designationIndicator({ controlledBy: 'NASA JSC', controlledBy2: 'OZ', poc: 'J. Doe, 281-555-0100', decontrol: '2036-01-01' }, { categories: [cat('EXPT', true)], ldcs: [{ code: 'FEDCON' }] });
  assert.deepEqual(lines, ['Controlled by: NASA JSC', 'Controlled by: OZ', 'CUI Category: SP-EXPT', 'Limited Dissemination Control: FEDCON', 'POC: J. Doe, 281-555-0100', 'Decontrol: 2036-01-01']);
  assert.ok(M.validateDesignation({ controlledBy: '' }).some((m) => m.code === 'CONTROLLED_BY_REQUIRED'));
});

test('email: subject begins with CUI; body has banner top and bottom, transmittal notice, no passphrase', () => {
  assert.equal(M.emailSubject('  Test plan '), 'CUI - Test plan');
  const body = M.emailBody({ banner: 'CUI//SP-EXPT//FEDCON', files: ['CUI - a.docx.locked'], designationLines: ['Controlled by: NASA'], hostedUrl: 'https://x/', unlockerName: 'CUIEmail.html' });
  const lines = body.split('\r\n');
  assert.equal(lines[0], 'CUI//SP-EXPT//FEDCON');
  assert.equal(lines[lines.length - 1], 'CUI//SP-EXPT//FEDCON');
  assert.match(body, /When the attachments are removed, this message is Uncontrolled Unclassified Information/);
  assert.match(body, /Controlled by: NASA/);
  assert.match(body, /never sent by email/);
  assert.ok(body.length < 1800, 'mailto body must stay short');
  assert.ok(M.mailtoUrl('CUI - x', body).startsWith('mailto:?subject=CUI%20-%20x&body=CUI'));
});
