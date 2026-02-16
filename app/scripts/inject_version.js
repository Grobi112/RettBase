#!/usr/bin/env node
// Beim "flutter build web": Version in version.json erhöhen (fortlaufend),
// in index.html und pubspec.yaml schreiben.
// version.json = einzige Quelle; APK/iOS holen sie beim Update-Check.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const versionPath = path.join(root, 'web', 'version.json');
const indexPath = path.join(root, 'web', 'index.html');
const pubspecPath = path.join(root, 'pubspec.yaml');

let data = JSON.parse(fs.readFileSync(versionPath, 'utf8'));
let v = (data.version || '1.0.0').trim();
let b = parseInt((data.buildNumber || '1').toString(), 10) || 1;

// Patch erhöhen: 1.0.0 → 1.0.1
const parts = v.split('.');
if (parts.length >= 3) {
  const patch = parseInt(parts[2], 10) || 0;
  parts[2] = String(patch + 1);
  v = parts.join('.');
} else {
  v = '1.0.1';
}

// Build-Nummer erhöhen
b = b + 1;

data.version = v;
data.buildNumber = String(b);
fs.writeFileSync(versionPath, JSON.stringify(data, null, 2), 'utf8');

const fullVersion = `${v}.${b}`;

// index.html
let html = fs.readFileSync(indexPath, 'utf8');
html = html.replace(
  /<meta name="rettbase-version" content="[^"]*">/,
  `<meta name="rettbase-version" content="${fullVersion}">`
);
fs.writeFileSync(indexPath, html);

// pubspec.yaml: version: X.Y.Z+BUILD
let pubspec = fs.readFileSync(pubspecPath, 'utf8');
pubspec = pubspec.replace(
  /^version:\s*[\d.]+\+\d+/m,
  `version: ${v}+${b}`
);
fs.writeFileSync(pubspecPath, pubspec);

console.log('Version:', v, 'Build:', b, '→', fullVersion);
