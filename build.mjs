// build.mjs - inline src/ into a single dist/CUIEmail.html with no external references.
// Each ES module is wrapped in its own function scope so private names never collide, and its
// exports are exposed on a __<name> object that replaces the import statements.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const pkg = require('./package.json');
const VERSION = process.env.SCE_VERSION || pkg.version;

const jsonInline = (p) => readFileSync('src/' + p, 'utf8').trim();

function wrapModule(name, src) {
  const exports = new Set();
  for (const m of src.matchAll(/^export\s+(?:async\s+)?(?:function|const|let|class)\s+(\w+)/gm)) exports.add(m[1]);
  for (const m of src.matchAll(/^export\s*\{([^}]*)\};?/gm)) for (const part of m[1].split(',')) { const n = part.trim().split(/\s+as\s+/).pop(); if (n) exports.add(n); }
  let body = src
    .replace(/^import\s+\*\s+as\s+(\w+)\s+from\s+'\.\/(\w+)\.js';\s*$/gm, 'const $1 = __$2;')
    .replace(/^import\s+\{([^}]*)\}\s+from\s+'\.\/(\w+)\.js';\s*$/gm, 'const {$1} = __$2;')
    .replace(/^import\s+(\w+)\s+from\s+'\.\/(data\/[\w-]+\.json)'\s+with\s+\{[^}]*\};\s*$/gm, (_, id, p) => `const ${id} = ${jsonInline(p)};`)
    .replace(/^export\s*\{[^}]*\};?\s*$/gm, '')
    .replace(/^export\s+(default\s+)?/gm, '');
  if (/^import\s/m.test(body)) throw new Error(`unhandled import in ${name}`);
  return `const __${name} = (() => {\n${body}\nreturn { ${[...exports].join(', ')} };\n})();`;
}

const js = ['wordlist', 'cuilock', 'marking', 'precheck', 'app']
  .map((n) => wrapModule(n, readFileSync(`src/${n}.js`, 'utf8')))
  .join('\n\n')
  .replace(/__VERSION__/g, VERSION);

if (js.includes('</script')) throw new Error('script content would terminate the script tag');
const css = readFileSync('src/style.css', 'utf8');
if (css.includes('</style')) throw new Error('style content would terminate the style tag');
const html = readFileSync('src/index.html', 'utf8')
  .replace('/*__CSS__*/', () => css)
  .replace('/*__JS__*/', () => js)
  .replace('<script type="module">', '<script>');
mkdirSync('dist', { recursive: true });
writeFileSync('dist/CUIEmail.html', html);
console.log(`dist/CUIEmail.html  v${VERSION}  ${(html.length / 1024).toFixed(0)} KB`);
