#!/usr/bin/env node
// Web-Build: Version in version.json erhöhen (1.0.1 → 1.0.2), in index.html schreiben.
// buildNumber bleibt unverändert – APK kommt über Play Store, nicht über version.json.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const versionPath = path.join(root, 'web', 'version.json');
const indexPath = path.join(root, 'web', 'index.html');

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
fs.writeFileSync(versionPath, JSON.stringify(data, null, 2), 'utf8');

// index.html: nur Version (ohne buildNumber) für Web-Vergleich
let html = fs.readFileSync(indexPath, 'utf8');
html = html.replace(
  /<meta name="rettbase-version" content="[^"]*">/,
  `<meta name="rettbase-version" content="${v}">`
);
fs.writeFileSync(indexPath, html);

console.log('Version:', v);
