// Recursively list scripts referenced by a dumped .tscn (and its sub-scenes / script preloads).
const fs = require('fs'); const path = require('path');
const root = process.argv[2]; const start = process.argv[3];
const seen = new Set(); const scripts = new Set();
function scan(res) {
  if (seen.has(res)) return; seen.add(res);
  const f = path.join(root, res.replace('res://', ''));
  if (!fs.existsSync(f)) { console.error('missing dump', res); return; }
  const fd = fs.openSync(f, 'r'); const buf = Buffer.alloc(4 * 1024 * 1024); const n = fs.readSync(fd, buf, 0, buf.length, 0); fs.closeSync(fd);
  const head = buf.slice(0, n).toString('utf8');
  for (const m of head.matchAll(/\[ext_resource type="(\w+)"[^\]]*path="([^"]+)"/g)) {
    if (m[1] === 'Script') scripts.add(m[2]);
    else if (m[1] === 'PackedScene') scan(m[2]);
  }
}
scan(start);
console.log([...scripts].sort().join('\n'));
