#!/usr/bin/env node
// Web-Build: Version in web/app/download/version.json erhöhen (1.0.1 → 1.0.2), index.html Meta.
// Aufruf: node web/increment_version.js  (aus app/-Verzeichnis)
// Wird von fw, build_web.sh, deploy_web.sh und ./flutter build web verwendet.

const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname);
const defaultApkUrl = 'https://app.rettbase.de/app/download/rettbase.apk';
const downloadDir = path.join(dir, 'app', 'download');
fs.mkdirSync(downloadDir, { recursive: true });
const versionPath = path.join(downloadDir, 'version.json');
const legacyVersionPath = path.join(dir, 'version.json');
if (!fs.existsSync(versionPath) && fs.existsSync(legacyVersionPath)) {
  fs.copyFileSync(legacyVersionPath, versionPath);
}
if (!fs.existsSync(versionPath)) {
  console.error(
    'Fehler: web/app/download/version.json fehlt. Einmal: node scripts/increment_pubspec_version.js oder ./scripts/build_apk.sh'
  );
  process.exit(1);
}
const indexPath = path.join(dir, 'index.html');

let data = JSON.parse(fs.readFileSync(versionPath, 'utf8'));
let v = (data.version || '1.0.0').trim();

// Patch erhöhen: 1.0.0 → 1.0.1 → 1.0.2
const parts = v.split('.');
if (parts.length >= 3) {
  const patch = parseInt(parts[2], 10) || 0;
  parts[2] = String(patch + 1);
  v = parts.join('.');
} else {
  v = '1.0.1';
}

data.version = v;
delete data.buildNumber;
delete data.downloadUrl;

// Android Sideload: versionCode + apkUrl MÜSSEN gesetzt sein (sonst kein APK-Update-Hinweis in der App).
const appDir = path.join(__dirname, '..');
const pubspecPath = path.join(appDir, 'pubspec.yaml');
let buildFromPubspec = null;
try {
  const pubspec = fs.readFileSync(pubspecPath, 'utf8');
  const m = pubspec.match(/^version:\s*[\d.]+\+(\d+)\s*$/m);
  if (m) {
    buildFromPubspec = parseInt(m[1], 10);
  }
} catch (e) {
  console.error('pubspec.yaml konnte nicht gelesen werden:', e.message);
  process.exit(1);
}
if (buildFromPubspec == null || !Number.isFinite(buildFromPubspec)) {
  console.error(
    'pubspec.yaml: Zeile version muss Build enthalten, z. B. version: 1.0.0+42 (für versionCode / Android-Update).'
  );
  process.exit(1);
}
data.versionCode = buildFromPubspec;

if (typeof data.apkUrl !== 'string' || !data.apkUrl.trim()) {
  data.apkUrl = defaultApkUrl;
} else if (data.apkUrl.trim() === 'https://app.rettbase.de/download/rettbase.apk') {
  data.apkUrl = defaultApkUrl;
}

fs.writeFileSync(versionPath, JSON.stringify(data, null, 2) + '\n', 'utf8');

// index.html: nur Version (ohne buildNumber) für Web-Vergleich
let html = fs.readFileSync(indexPath, 'utf8');
html = html.replace(
  /<meta name="rettbase-version" content="[^"]*">/,
  `<meta name="rettbase-version" content="${v}">`
);
fs.writeFileSync(indexPath, html);

console.log('Version:', v);
