// Print only node/connection/ext_resource sections of a .tscn, truncating long lines.
const fs = require('fs');
const readline = require('readline');
const rl = readline.createInterface({ input: fs.createReadStream(process.argv[2]), crlfDelay: Infinity });
let mode = null;
const maxLen = +(process.argv[3] || 200);
rl.on('line', (l) => {
  if (l.startsWith('[')) {
    if (l.startsWith('[node') || l.startsWith('[connection') || l.startsWith('[ext_resource') || l.startsWith('[editable')) { mode = 'keep'; console.log(l.length > 400 ? l.slice(0, 400) + '…' : l); }
    else mode = null;
    return;
  }
  if (mode === 'keep' && l.trim() !== '') console.log('    ' + (l.length > maxLen ? l.slice(0, maxLen) + '…' : l));
});
