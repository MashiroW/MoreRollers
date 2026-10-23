// Writes a Godot 4.1 resource pack (PCK format v2) from a staging folder.
// Every file under <stage> is stored as res://<relative path>.
// usage: node mkpck.js <stage dir> <out.pck>
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const [stage, out] = process.argv.slice(2);
if (!stage || !out) { console.error('usage: node mkpck.js <stage> <out.pck>'); process.exit(1); }

function walk(dir, base, acc) {
  for (const name of fs.readdirSync(dir).sort()) {
    const full = path.join(dir, name);
    const rel = base ? base + '/' + name : name;
    if (fs.statSync(full).isDirectory()) walk(full, rel, acc);
    else acc.push({ res: 'res://' + rel, full });
  }
  return acc;
}

const files = walk(stage, '', []);
const ALIGN = 16;
const pad = (n, a) => (a - (n % a)) % a;

// Directory size: header (100 bytes) + entries.
const entries = files.map((f) => {
  const data = fs.readFileSync(f.full);
  const name = Buffer.from(f.res, 'utf8');
  return { ...f, data, name, namePad: pad(name.length, 4), md5: crypto.createHash('md5').update(data).digest() };
});
let dirSize = 100;
for (const e of entries) dirSize += 4 + e.name.length + e.namePad + 8 + 8 + 16 + 4;
const fileBase = dirSize + pad(dirSize, ALIGN);

const header = Buffer.alloc(100);
header.write('GDPC', 0, 'latin1');
header.writeUInt32LE(2, 4); // pack format version
header.writeUInt32LE(4, 8); // godot major
header.writeUInt32LE(1, 12); // minor
header.writeUInt32LE(1, 16); // patch
header.writeUInt32LE(0, 20); // flags
header.writeBigUInt64LE(BigInt(fileBase), 24);
header.writeUInt32LE(entries.length, 96);

const parts = [header];
let ofs = 0;
for (const e of entries) {
  const b = Buffer.alloc(4 + e.name.length + e.namePad + 8 + 8 + 16 + 4);
  let p = 0;
  b.writeUInt32LE(e.name.length + e.namePad, p); p += 4;
  e.name.copy(b, p); p += e.name.length + e.namePad;
  b.writeBigUInt64LE(BigInt(ofs), p); p += 8;
  b.writeBigUInt64LE(BigInt(e.data.length), p); p += 8;
  e.md5.copy(b, p); p += 16;
  b.writeUInt32LE(0, p); p += 4;
  parts.push(b);
  e.ofs = ofs;
  ofs += e.data.length + pad(e.data.length, ALIGN);
}
parts.push(Buffer.alloc(fileBase - dirSize));
for (const e of entries) {
  parts.push(e.data);
  parts.push(Buffer.alloc(pad(e.data.length, ALIGN)));
}
fs.writeFileSync(out, Buffer.concat(parts));
console.log(`wrote ${out}: ${entries.length} files`);
