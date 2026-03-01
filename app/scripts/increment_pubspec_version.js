#!/usr/bin/env node
// iOS/Android-Build: Version und Build-Nummer in pubspec.yaml erhöhen.
// Aufruf: node scripts/increment_pubspec_version.js  (aus app/-Verzeichnis)
// Wird von build_ipa.sh und ggf. zsh_integration verwendet.

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
