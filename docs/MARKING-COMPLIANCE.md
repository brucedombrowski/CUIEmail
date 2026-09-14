# CUI marking compliance trace

Every marking behavior in CUIEmail is listed here with the rule it implements and where that rule comes from. Quotations were taken from the primary documents on 2026-09-14. Where a primary document could not be retrieved, that is stated rather than papered over.

## Sources

| Key | Document | Retrieved from |
|---|---|---|
| CFR | 32 CFR 2002.20, Marking | eCFR API, title 32 part 2002, as of 2026-09-01 |
| HB | NARA CUI Marking Handbook v1.1 (Dec 2016) | archives.gov/files/cui/20161206-cui-marking-handbook-v1-1.pdf |
| REG-LDC | CUI Registry, Limited Dissemination Controls | archives.gov/cui/registry/limited-dissemination (last reviewed July 14, 2025) |
| REG-CAT | CUI Registry category list and 128 category detail pages | archives.gov/cui/registry/category-list and category-detail/* |
| REG-TRI | Trigraph Country Codes for REL TO | archives.gov/files/cui/registry/policy-guidance/registry-documents/20161214-country-trigraph-codes.pdf |
| REG-TET | ISMCAT Tetragraph Taxonomy, Dec 1 2022 | archives.gov/files/cui/registry/policy-guidance/registry-documents/tetragraph-codes-for-coalition-or-international-organizations.pdf |
| ISOO | ISOO tip sheet "Controlled Unclassified Information, Emails, and Marking" (2018-06-05) | archives.gov/files/cui/documents/cui-email-marking-tip-20180605.pdf |
| NPR | NASA NPR 2810.7 Change 1, "Controlled Unclassified Information" | nodis3.gsfc.nasa.gov (Word source) |
| DoDI | DoD Instruction 5200.48 | **Not retrieved.** All `.mil` hosts were unreachable from the build environment. DoD-specific statements below come from secondary sources and are marked as such. |

## Rules implemented

### R1. Control marking is `CUI`
- CFR (b)(1)(i): "The CUI control marking may consist of either the word 'CONTROLLED' or the acronym 'CUI,' at the designator's discretion."
- NPR, Definitions: "'Controlled' is equivalent to the banner marking 'CUI.' Note: NASA will not use this banner marking."
- Implementation: `CONTROL_MARKING = 'CUI'` in `src/marking.js`. No option to use CONTROLLED.

### R2. Banner structure and separators
- HB p.5: the banner "may include up to three elements": control marking; category markings "separated from the CUI Control Marking by a double forward slash (//)... multiple categories... alphabetized and are separated by a single forward slash (/)"; LDC markings "preceded by a double forward slash (//)". Sample: `CUI//CATEGORIES/SUBCATEGORIES//DISSEM`.
- HB p.12 example `CUI//DISSEM-A/DISSEM-C` shows LDCs following the control marking directly when no category marking is used.
- Implementation: `buildBanner()`. Test: marking.test.mjs.

### R3. Specified categories carry `SP-` and are mandatory in the banner
- CFR (b)(2): category markings are "mandatory for CUI Specified"; (b)(2)(iii): "authorized holders must include in the CUI banner marking all CUI Specified category or subcategory markings that pertain to the information".
- HB p.9: "To make sure that it is obvious that a Category or Subcategory is Specified, the marking has 'SP-' added to the beginning of it."
- Implementation: `categoryMarking()`. A category whose Registry authorities are all Specified cannot be selected as Basic and vice versa (`validateMarking` codes NOT_BASIC / NOT_SPECIFIED). A category that can be either requires an explicit choice (KIND_REQUIRED); the tool explains how to decide and links the Registry entry.

### R4. Category ordering
- HB p.11: "CUI Specified Markings MUST precede CUI Basic Markings ... CUI Category and Subcategory Markings MUST be alphabetized within CUI type (Basic or Specified). Alphabetized Specified CUI categories and subcategories MUST precede alphabetized Basic CUI categories and subcategories."
- Implementation: `orderedCategoryMarkings()`.

### R5. Basic category markings are optional but allowed
- CFR (b)(2)(ii): "Although the CUI Program does not require agencies to use category or subcategory markings on CUI Basic, an agency's CUI SAO may establish agency policy that mandates" them.
- Implementation: selected Basic categories are always included (never harmful, more informative). If no category is selected the banner is `CUI` and a warning (NO_CATEGORY) is shown.

### R6. Limited dissemination controls
- CFR (b)(3)(i): LDC markings "align with limited dissemination controls established by the CUI EA". HB p.12: "Only Limited Dissemination Control Markings found in the CUI Registry are authorized"; multiple LDCs "MUST be alphabetized and separated from each other with a single forward slash (/)".
- REG-LDC provides the list: NOFORN, FED ONLY, FEDCON, NOCON, DL ONLY, RELIDO, REL TO, DISPLAY ONLY, Attorney-Client, Attorney-WP. NPR 2.9 lists the same set (and Deliberative, which is not on the current Registry page).
- Implementation: `src/data/ldcs.json`, `orderedLdcMarkings()`. RELIDO is intentionally omitted: REG-LDC says "Only agencies that are eligible to use RELIDO in the intelligence community (IC) classified information context may use this LDCM on CUI." Deliberative is omitted because it is not on the current Registry LDC page.

### R7. REL TO and DISPLAY ONLY list ordering
- REG-LDC: "When marking REL TO: 1) USA must always appear first. 2) Followed by trigraph country code(s), in alphabetical order. 3) Followed by tetragraph codes for coalition or international organization(s), in alphabetical order." Identical text for DISPLAY ONLY.
- Codes come from REG-TRI (275 country trigraphs) and REG-TET (43 tetragraphs).
- Implementation: `orderedReleaseList()`. Unknown codes and lists with only USA are errors.

### R8. Contradictory controls
- REG-LDC definitions: NOFORN forbids dissemination "to foreign governments, foreign nationals..."; REL TO and DISPLAY ONLY authorize it. FED ONLY excludes contractors; FEDCON includes them. NOCON excludes contractors. DL ONLY "supersedes other limited dissemination controls". Attorney-Client and Attorney-WP are "for use only with the 'Legal Privilege' category."
- Implementation: errors NOFORN_CONFLICT, FED_CONFLICT, NOCON_CONFLICT, PRIVILEGE_REQUIRED; warnings NOCON_REDUNDANT, DL_ONLY_SUPERSEDES, DL_ONLY_LIST.

### R9. One banner for the whole transmission
- CFR (c)(1): "The content of the CUI banner marking must apply to the whole document (i.e., inclusive of all CUI within the document) and must be the same on each page".
- NPR 2.2.8: "The content of the CUI banner marking will be inclusive of all CUI within the document and will be the same on each page. Banner markings will appear at the top of each page of any document that contains CUI, including email transmissions, if authorized."
- Implementation: one marking selection covers every attachment in the email; the banner is placed at the top of the email body.

### R10. Bottom banner
- HB p.6: "As an optional best practice, the CUI Banner Marking may be placed at the bottom of the document as well."
- Secondary (DoDI 5200.48 as summarized by DoD marking aids): DoD requires the banner at top and bottom of pages and of email bodies.
- Implementation: banner at top and bottom of the email body. Satisfies NARA and NASA; also satisfies the DoD practice.

### R11. Designation indicator
- CFR (d)(1): "All documents containing CUI must carry an indicator of who designated the CUI within it. This must include the designator's agency (at a minimum) ... adding a 'Controlled by' line".
- HB p.13: "Every effort should be made to identify a point of contact, branch, or division within an organization, and to include contact information."
- CFR (e)(1): "Where feasible, designating agencies must include a specific decontrolling date or event with all CUI."
- Implementation: `designationIndicator()` writes `Controlled by:` (required, error CONTROLLED_BY_REQUIRED if empty), optional second `Controlled by:` for office, `CUI Category:`, `Limited Dissemination Control:`, `POC:` (warning if empty), `Decontrol:` (optional). The lines appear in the email and are stored, authenticated, in each `.locked` header so the recipient sees them before unlocking.

### R12. Transmittal document notice
- CFR (j)(1): "When a transmittal document accompanies CUI, the transmittal document must include a CUI marking on its face ('CONTROLLED' or 'CUI'), indicating that CUI is attached or enclosed." (j)(2)(i): the instruction "When enclosure is removed, this document is Uncontrolled Unclassified Information".
- NPR 2.16 repeats this.
- Implementation: email body states "This email transmits Controlled Unclassified Information (CUI) in the encrypted attachments listed below. When the attachments are removed, this message is Uncontrolled Unclassified Information."

### R13. Subject line
- ISOO: "In addition to the banner marking, an indicator can be included in the subject line to indicate that the email also contains CUI. 'Contains CUI' can appear in the subject line".
- Secondary (DoD/DON practice, e.g. USNA privacy guidance): "The SUBJECT line must include the marking 'CUI'".
- Implementation: subject is `CUI - <topic>`. This satisfies the permissive NARA rule and the stricter DoD/DON one. The UI tells the sender not to put controlled information in the subject, because the subject is not encrypted.

### R14. Portion marking is not used
- CFR (f)(1): agencies "are permitted and encouraged to portion mark". NPR 2.2.10: "If portion markings are used in any portion of a document, then portion markings will be used throughout the entire document."
- Implementation: the email body carries no portion markings, so the throughout-the-document rule is not triggered. The body contains no CUI.

### R15. Supplemental markings stay out of the banner
- CFR (l)(4): "Authorized holders must not incorporate or include supplemental administrative markings in the CUI marking scheme". (b)(2)(iii): required warning or distribution statements "must not" be included in the banner.
- Implementation: the banner is built only from Registry markings. Distribution statements (DoD CTI) are not part of the banner; senders who need one put it in the document itself.

### R16. The attachments themselves must be marked
- CFR (c)(1) and NPR 2.2.8 (above): every page of a CUI document carries the banner. CFR (d): designation indicator on the first page or cover.
- Implementation: `src/precheck.js` inspects each Word (every header part), PowerPoint (every slide, or the master), Excel (every sheet's print header), PDF (text streams) and text file for `CUI`/`CONTROLLED` and reports found / partial / missing / unknown. A file that is not confirmed `found` requires the sender to tick an acknowledgment. The tool never modifies a document.

### R17. Passphrase out of band
- The email body states the passphrase "is sent separately by phone or text message. It is never sent by email." The UI repeats this and shows the passphrase only on the sender's screen. (NIST SP 800-63B out-of-band principle; carried over from v0 decision DM-2026-003.)

## File-name marking: finding

Question raised during design: must the attachment file name carry the CUI marking?

- CFR 2002.20: no rule about file names. The only "outside" rule is (i)(2), for physical packages: "Do not put CUI markings on the outside of an envelope or package".
- HB: no rule about file names. p.23 covers removable media labels only.
- NPR 2810.7: no rule about file names.
- Secondary: Department of the Navy / USNA guidance states that for PII attachments "the attachment file name ... must including the marking 'CUI'". That is agency policy, not a Government-wide requirement. DoDI 5200.48 could not be retrieved to confirm whether DoD itself imposes it.

Decision: not required by 32 CFR 2002 or NARA guidance. Because it costs nothing and satisfies the stricter agency practice, the encrypted container is named `CUI - <original name>.locked`. The original file name is restored unchanged from the authenticated header when unlocked; the tool never renames the sender's document.

## Data provenance

`src/data/categories.json` was generated on 2026-09-14 by fetching the Registry category list and each of the 128 linked detail pages and reading the "Category Marking" and the Basic/Specified column of each authority table. Nine linked pages (legacy DHS variants) had no marking and were dropped, leaving 119 categories. Three markings appear twice in the Registry itself (`CCI`, `FSI`, `M`); the tool keeps both entries.

## Known gaps

- DoDI 5200.48 and DoD marking aids were not verified against primary text. The tool's output (top and bottom banner, `CUI` at the start of the subject, Controlled by / Category / Dissemination Control / POC lines) matches the DoD designation-indicator practice as described by secondary sources, but a DoD user should confirm against the instruction.
- The NASA CUI Handbook (referenced by NPR 2810.7 for examples and email specifics) was not retrieved.
- PDF checking confirms that `CUI` appears somewhere as text, not that it appears on every page.
