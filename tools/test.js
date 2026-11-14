// Smoke test for Thrum without the game.
//
//   node tools/test.js [--docs <Blizzard_APIDocumentationGenerated dir>] [--fengari <fengari-web.js>]
//
// Runs the addon's real Lua (in fengari) against a mock of the WoW UI that is built from
// Blizzard's own generated API documentation, so the mock knows which widget methods, global
// functions and events exist in the client and which of them accept "secret" values. It then
// plays a fight twice (mana readable, then mana, auras, cooldowns and totems secret), runs every slash command, and
// reports Lua errors, calls to things the client does not have, and a timeline of effects.
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
};
const ROOT = path.join(__dirname, '..');
// The API docs of the build the game runs (tools/fetch_docs.py), else Chronicle's copy.
const FOREVER_DOCS = path.join(__dirname, 'forever_docs');
const DOCS = opt('docs', fs.existsSync(FOREVER_DOCS) ? FOREVER_DOCS
  : path.join(ROOT, '..', 'chronicle', 'tools', 'blizzard_ref', 'Blizzard_APIDocumentationGenerated'));
const FENGARI = opt('fengari', path.join(ROOT, '..', 'chronicle', 'emulator', 'vendor', 'fengari-web.js'));
const VERBOSE = args.includes('--verbose');
const SNAP = opt('snap', null); // write an HTML page of rendered HUD snapshots here
// write a page of polished presentation images (the README's screens) here
const SHOWCASE_OUT = opt('showcase', null);
// moments of the demo shown as presentation images: time, file name, caption
const SHOWCASE = [
  { t: 3.3, file: 'totems', title: 'DROP YOUR TOTEMS', sub: 'Four carved plaques, each on the game\'s own totem timer' },
  { t: 5.3, file: 'shock-the-heal', title: 'SHOCK THE HEAL!', sub: 'See what your target casts, and whether it is a heal' },
  { t: 5.9, file: 'broken', title: 'BROKEN!', sub: 'Earth Shock interrupts, with the shared shock cooldown counting down' },
  { t: 6.6, file: 'clearcasting', title: 'CLEARCASTING!', sub: 'Procs light up the mana trough while they last' },
  { t: 8.65, file: 'chain-lightning', title: 'CHAIN LIGHTNING!', sub: 'Your own casts, with Lightning Shield charges on the orb' },
  { t: 11.45, file: 'healing-wave', title: 'HEALING WAVE!', sub: 'Heals cast in green; the five-second rule runs out under the mana' },
  { t: 13.3, file: 'purged', title: 'PURGED!', sub: 'Flame Shock ticking, a buff torn off the target' },
];
const FONT = opt('font', path.join(ROOT, 'Thrum', 'Fonts', 'ThrumRunes.ttf'));
const SNAP_TIMES = [0.4, 1.2, 3.3, 4.6, 5.3, 5.9, 6.6, 8.65, 9.4, 11.45, 12.5, 13.3, 14.0];

// ---------------------------------------------------------------- read the API docs
const doc = { methods: {}, globals: {}, ns: {}, events: {}, enums: {} };
for (const f of fs.readdirSync(DOCS)) {
  if (!f.endsWith('.lua')) continue;
  const s = fs.readFileSync(path.join(DOCS, f), 'utf8');
  const top = s.slice(0, s.indexOf('Functions') > 0 ? s.indexOf('Functions') : 400);
  const name = (top.match(/\n\tName = "(\w+)"/) || [])[1];
  const type = (top.match(/\n\tType = "(\w+)"/) || [])[1];
  const sysNS = (top.match(/\n\tNamespace = "(\w*)"/) || [])[1] || '';
  if (type === 'ScriptObject') doc.methods[name] = doc.methods[name] || { __none: 'U' };
  const fnRe = /\t\t\{\n\t\t\tName = "(\w+)",\n\t\t\tType = "Function",([\s\S]*?)\n\t\t\},/g;
  let m;
  while ((m = fnRe.exec(s))) {
    const body = m[2];
    const sec = (body.match(/\n\t\t\tSecretArguments = "(\w+)"/) || [])[1];
    const flag = sec === 'AllowedWhenTainted' ? 'T' : sec === 'NotAllowed' ? 'N' : 'U';
    if (type === 'ScriptObject') {
      doc.methods[name][m[1]] = flag;
    } else {
      const fnNS = body.match(/\n\t\t\tNamespace = "(\w*)"/);
      const ns = fnNS ? fnNS[1] : sysNS;
      if (ns) (doc.ns[ns] = doc.ns[ns] || {})[m[1]] = flag;
      else doc.globals[m[1]] = flag;
    }
  }
  const evRe = /LiteralName = "(\w+)"/g;
  while ((m = evRe.exec(s))) doc.events[m[1]] = true;
  const enRe = /Name = "(\w+)",\n\t\t\tType = "Enumeration",[\s\S]*?Fields =\s*\{([\s\S]*?)\n\t\t\t\},/g;
  while ((m = enRe.exec(s))) {
    const e = (doc.enums[m[1]] = {});
    const fRe = /Name = "(\w+)", Type = "\w+", EnumValue = (-?\d+)/g;
    let fm;
    while ((fm = fRe.exec(m[2]))) e[fm[1]] = Number(fm[2]);
  }
}

const lua = (v) => {
  if (v === true) return 'true';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'string') return JSON.stringify(v);
  return '{' + Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${lua(x)}`).join(',') + '}';
};

// ---------------------------------------------------------------- run
global.window = global;
global.self = global;
const fengari = require(FENGARI);

const toc = fs.readFileSync(path.join(ROOT, 'Thrum', 'Thrum.toc'), 'utf8');
const files = toc.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
for (const f of fs.readdirSync(path.join(ROOT, 'Thrum', 'Art'))) {
  if (!/\.tga$/.test(f) && f !== '.DS_Store') throw new Error('unexpected art file ' + f);
}
const art = fs.readdirSync(path.join(ROOT, 'Thrum', 'Art')).filter((f) => f.endsWith('.tga')).map((f) => f.replace(/\.tga$/, ''));

let src = 'DOC = ' + lua(doc) + '\n';
src += 'ART = ' + lua(Object.fromEntries(art.map((a) => [a, true]))) + '\n';
const fontDir = path.join(ROOT, 'Thrum', 'Fonts');
const fonts = fs.existsSync(fontDir) ? fs.readdirSync(fontDir) : [];
src += 'FONTFILES = ' + lua(Object.fromEntries(fonts.map((f) => [f, true]))) + '\n';
src += 'VERBOSE = ' + (VERBOSE ? 'true' : 'false') + '\n';
if (SNAP || SHOWCASE_OUT) src += 'SNAP = {' + SNAP_TIMES.join(',') + '}\n';
src += 'FILES = {}\n';
for (const f of files) {
  const code = fs.readFileSync(path.join(ROOT, 'Thrum', f.replace(/\\/g, '/')), 'utf8');
  src += `FILES[#FILES+1] = { name = ${JSON.stringify(f)}, code = [==========[\n${code}]==========] }\n`;
}
src += fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8');

let out = fengari.load(src, 'thrum-test')();
let shots = null;
const cut = out.indexOf('\n@@SNAP@@\n');
if (cut >= 0) {
  shots = out.slice(cut + 10);
  out = out.slice(0, cut);
}
console.log('docs: ' + DOCS + (fs.existsSync(path.join(DOCS, 'VERSION')) ? ' (build ' + fs.readFileSync(path.join(DOCS, 'VERSION'), 'utf8').trim() + ')' : ''));
console.log(out);

// ---------------------------------------------------------------- paint the snapshots
if ((SNAP || SHOWCASE_OUT) && shots) {
  const zlib = require('zlib');
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (tag, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(tag), data]);
    const sum = Buffer.alloc(4);
    sum.writeUInt32BE(crc(body));
    return Buffer.concat([len, body, sum]);
  };
  const tgaToPng = (file) => {
    const t = fs.readFileSync(file);
    const w = t.readUInt16LE(12), h = t.readUInt16LE(14);
    const raw = Buffer.alloc((w * 4 + 1) * h);
    for (let y = 0; y < h; y++) {
      const srcRow = 18 + (h - 1 - y) * w * 4; // TGA rows run bottom-up
      const dst = y * (w * 4 + 1);
      for (let x = 0; x < w; x++) {
        raw[dst + 1 + x * 4] = t[srcRow + x * 4 + 2];
        raw[dst + 2 + x * 4] = t[srcRow + x * 4 + 1];
        raw[dst + 3 + x * 4] = t[srcRow + x * 4];
        raw[dst + 4 + x * 4] = t[srcRow + x * 4 + 3];
      }
    }
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0);
    ihdr.writeUInt32BE(h, 4);
    ihdr.set([8, 6, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
      chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
  };
  const images = {};
  for (const a of art) images[a] = 'data:image/png;base64,' + tgaToPng(path.join(ROOT, 'Thrum', 'Art', a + '.tga')).toString('base64');
  const font = fs.existsSync(FONT) ? fs.readFileSync(FONT).toString('base64') : null;
  const template = fs.readFileSync(path.join(__dirname, 'snap.html'), 'utf8')
    .replace('/*FONT*/', font ? `@font-face { font-family: hud; src: url(data:font/ttf;base64,${font}); }` : '')
    .replace('"@@IMAGES@@"', JSON.stringify(images))
    .replace('"@@SHOTS@@"', shots);
  if (SNAP) {
    fs.writeFileSync(SNAP, template.replace('"@@SHOWCASE@@"', '[]'));
    console.log('snapshots written to ' + SNAP);
  }
  if (SHOWCASE_OUT) {
    const picks = SHOWCASE.map((s) => {
      const index = SNAP_TIMES.indexOf(s.t);
      if (index < 0) throw new Error('showcase time ' + s.t + ' is not one of SNAP_TIMES');
      return { index, file: s.file, title: s.title, sub: s.sub };
    });
    fs.writeFileSync(SHOWCASE_OUT, template.replace('"@@SHOWCASE@@"', JSON.stringify(picks))
      .replace('<h1>Thrum: what the addon draws</h1>', '<h1>Thrum: presentation images</h1>'));
    console.log('showcase written to ' + SHOWCASE_OUT);
  }
}
process.exit(/^FAIL/m.test(out) ? 1 : 0);
