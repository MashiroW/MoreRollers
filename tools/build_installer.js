// Builds dist/MoreRollers-Installer.exe: installer/MoreRollersInstaller.cs compiled with the C# compiler
// that comes with Windows (.NET Framework 4), with the built mod (mod/) and the banner embedded.
// Run `node tools/build.js` first so mod/ is up to date.
//
//   node tools/build_installer.js              -> dist/MoreRollers-Installer.exe
//   node tools/build_installer.js --snapshot   -> build/installer-snapshot.exe, a test build that can
//                                                 render its window to a PNG (--snapshot=<file.png>)
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.join(__dirname, '..');
const snapshot = process.argv.includes('--snapshot');

const windir = process.env.WINDIR || 'C:\\Windows';
const csc = ['Framework64', 'Framework']
  .map(d => path.join(windir, 'Microsoft.NET', d, 'v4.0.30319', 'csc.exe'))
  .find(f => fs.existsSync(f));
if (!csc) throw new Error('csc.exe (.NET Framework 4) not found under ' + windir + '\\Microsoft.NET');

const r = p => path.join(root, p);
for (const f of ['mod/loader.gd', 'mod/splitscreen.pck', 'res/banner.png', 'installer/MoreRollers.ico', 'installer/app.manifest']) {
  if (!fs.existsSync(r(f))) throw new Error('missing ' + f + (f.startsWith('mod/') ? ' (run node tools/build.js first)' : ''));
}

// Version and description of the exe, from the mod's own version.
const version = /const MOD_VERSION := "([^"]+)"/.exec(fs.readFileSync(r('mod/loader.gd'), 'utf8'))[1];
const numeric = (version.match(/\d+/g) || []).concat(['0', '0', '0', '0']).slice(0, 4).join('.');
fs.mkdirSync(r('build'), { recursive: true });
const info = r('build/installer_info.cs');
fs.writeFileSync(info, [
  'using System.Reflection;',
  '[assembly: AssemblyTitle("MoreRollers installer")]',
  '[assembly: AssemblyDescription("Installs the MoreRollers local splitscreen mod into Buckshot Roulette")]',
  '[assembly: AssemblyProduct("MoreRollers")]',
  '[assembly: AssemblyCompany("Mash")]',
  `[assembly: AssemblyCopyright("Copyright (C) ${new Date().getFullYear()} Mash - GPL-3.0-or-later")]`,
  `[assembly: AssemblyVersion("${numeric}")]`,
  `[assembly: AssemblyFileVersion("${numeric}")]`,
  `[assembly: AssemblyInformationalVersion("${version}")]`,
  '',
].join('\n'));

const out = snapshot ? r('build/installer-snapshot.exe') : r('dist/MoreRollers-Installer.exe');
fs.mkdirSync(path.dirname(out), { recursive: true });
const args = [
  '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
  '/out:' + out,
  '/win32icon:' + r('installer/MoreRollers.ico'),
  '/win32manifest:' + r('installer/app.manifest'),
  '/resource:' + r('mod/loader.gd') + ',loader.gd',
  '/resource:' + r('mod/splitscreen.pck') + ',splitscreen.pck',
  '/resource:' + r('res/banner.png') + ',banner.png',
  '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll',
];
if (snapshot) args.push('/define:SNAPSHOT');
args.push(r('installer/MoreRollersInstaller.cs'), info);
execFileSync(csc, args, { stdio: 'inherit' });
console.log('built', path.relative(root, out), '(' + fs.statSync(out).size + ' bytes, version ' + version + ')');
