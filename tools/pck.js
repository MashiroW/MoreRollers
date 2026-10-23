// Minimal Godot 4 PCK (format v2) reader/extractor for an embedded pck.
const fs = require('fs');
const path = require('path');
function readPck(file) {
  const fd = fs.openSync(file, 'r');
  const size = fs.fstatSync(fd).size;
  const tail = Buffer.alloc(12);
  fs.readSync(fd, tail, 0, 12, size - 12);
  let start = 0;
  if (tail.slice(8).toString('latin1') === 'GDPC') start = size - 12 - Number(tail.readBigUInt64LE(0));
  const hdr = Buffer.alloc(100);
  fs.readSync(fd, hdr, 0, hdr.length, start);
  const fileBase = Number(hdr.readBigUInt64LE(24));
  const count = hdr.readUInt32LE(96);
  let pos = start + hdr.length;
  const dirBuf = Buffer.alloc(8 * 1024 * 1024);
  fs.readSync(fd, dirBuf, 0, dirBuf.length, pos);
  let p = 0;
  const entries = [];
  for (let i = 0; i < count; i++) {
    const sl = dirBuf.readUInt32LE(p); p += 4;
    const name = dirBuf.slice(p, p + sl).toString('utf8').replace(/\0+$/, ''); p += sl;
    const ofs = Number(dirBuf.readBigUInt64LE(p)); p += 8;
    const sz = Number(dirBuf.readBigUInt64LE(p)); p += 8;
    const md5 = dirBuf.slice(p, p + 16).toString('hex'); p += 16;
    const flags = dirBuf.readUInt32LE(p); p += 4;
    entries.push({ name, ofs: fileBase + ofs, size: sz, md5, flags });
  }
  return { fd, start, fileBase, entries, header: hdr };
}
module.exports = { readPck };
if (require.main === module) {
  const [cmd, file, out, filter] = process.argv.slice(2);
  const pck = readPck(file);
  if (cmd === 'list') {
    for (const e of pck.entries) console.log(e.size.toString().padStart(10), e.flags, e.name);
  } else if (cmd === 'extract') {
    const re = filter ? new RegExp(filter) : null;
    let n = 0;
    for (const e of pck.entries) {
      if (re && !re.test(e.name)) continue;
      const dest = path.join(out, e.name.replace(/^res:\/\//, ''));
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      const buf = Buffer.alloc(e.size);
      fs.readSync(pck.fd, buf, 0, e.size, e.ofs);
      fs.writeFileSync(dest, buf);
      n++;
    }
    console.log('extracted', n);
  }
}
