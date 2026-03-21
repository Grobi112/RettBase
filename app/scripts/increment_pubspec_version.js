#!/usr/bin/env node
// iOS/Android-Build: Version und Build-Nummer in pubspec.yaml erhöhen.
// Schreibt web/app/download/version.json + aktualisiert web/index.html (meta rettbase-version).
// Aufruf: node scripts/increment_pubspec_version.js  (aus app/-Verzeichnis)
// Wird von build_aab.sh, build_ipa.sh und ggf. zsh_integration verwendet.

const fs = require('fs');
const path = require('path');

const appDir = path.join(__dirname, '..');
const pubspecPath = path.join(appDir, 'pubspec.yaml');

let content = fs.readFileSync(pubspecPath, 'utf8');

// version: 1.0.1+2  →  Version (major.minor.patch) + Build-Nummer
const match = content.match(/^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$/m);
if (!match) {
  console.error('pubspec.yaml: version-Zeile nicht gefunden (Format: 1.0.1+2)');
  process.exit(1);
}

const major = parseInt(match[1], 10);
const minor = parseInt(match[2], 10);
const patch = parseInt(match[3], 10);
const build = parseInt(match[4], 10);

// Patch und Build erhöhen (Apple verlangt höhere Build-Nr. bei jedem Upload)
const newVersion = `${major}.${minor}.${patch + 1}`;
const newBuild = build + 1;
const newVersionStr = `${newVersion}+${newBuild}`;

content = content.replace(
  /^version:\s*[\d.]+\+\d+\s*$/m,
  `version: ${newVersionStr}\n`
);

fs.writeFileSync(pubspecPath, content, 'utf8');

console.log(`Version: ${newVersion} | Build: ${newBuild} (${newVersionStr})`);

// web/app/download/version.json – gleicher Ordner wie rettbase.apk (ein FTP-Upload-Ordner)
const defaultApkUrl = 'https://app.rettbase.de/app/download/rettbase.apk';
const downloadDir = path.join(appDir, 'web', 'app', 'download');
fs.mkdirSync(downloadDir, { recursive: true });
const versionJsonPath = path.join(downloadDir, 'version.json');
const legacyVersionJsonPath = path.join(appDir, 'web', 'version.json');
const versionJsonPayload = {
  version: newVersion,
  versionCode: newBuild,
  apkUrl: defaultApkUrl,
  releaseNotes: '',
};
const prevFile =
  fs.existsSync(versionJsonPath) ? versionJsonPath : legacyVersionJsonPath;
if (fs.existsSync(prevFile)) {
  try {
    const prev = JSON.parse(fs.readFileSync(prevFile, 'utf8'));
    if (typeof prev.releaseNotes === 'string') {
      versionJsonPayload.releaseNotes = prev.releaseNotes;
    }
    if (typeof prev.apkUrl === 'string' && prev.apkUrl.trim() !== '') {
      let u = prev.apkUrl.trim();
      if (u === 'https://app.rettbase.de/download/rettbase.apk') {
        u = defaultApkUrl;
      }
      versionJsonPayload.apkUrl = u;
    }
  } catch (_) {
    /* Defaults */
  }
}
fs.writeFileSync(
  versionJsonPath,
  `${JSON.stringify(versionJsonPayload, null, 2)}\n`,
  'utf8'
);
if (
  fs.existsSync(legacyVersionJsonPath) &&
  legacyVersionJsonPath !== versionJsonPath
) {
  try {
    fs.unlinkSync(legacyVersionJsonPath);
    console.log('Alte web/version.json entfernt (jetzt nur web/app/download/version.json).');
  } catch (_) {}
}
console.log(
  `web/app/download/version.json → version ${newVersion}, versionCode ${newBuild}`
);

// Web: Meta in index.html (gleiche Anzeige-Version wie version.json; ohne web/increment_version.js)
const indexPath = path.join(appDir, 'web', 'index.html');
try {
  let html = fs.readFileSync(indexPath, 'utf8');
  const next = html.replace(
    /<meta name="rettbase-version" content="[^"]*">/,
    `<meta name="rettbase-version" content="${newVersion}">`
  );
  if (next !== html) {
    fs.writeFileSync(indexPath, next, 'utf8');
    console.log(`web/index.html → meta rettbase-version ${newVersion}`);
  }
} catch (e) {
  console.warn('web/index.html: Meta konnte nicht gesetzt werden:', e.message);
}
