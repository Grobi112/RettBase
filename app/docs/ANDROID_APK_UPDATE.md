# Versionierung und Update (Web, APK, iOS)

**Einzige Quelle:** `web/version.json` – alle Plattformen nutzen diese Datei.

## Ablauf: Immer zuerst Web deployen

1. **Web** wird zuerst aktualisiert und deployed (`./scripts/deploy_web.sh`)
2. **APK** danach (pubspec und version.json sind bereits aktuell)
3. **iOS** danach (ebenso)

## Automatische Versionserhöhung (Web)

Bei `./flutter build web` (oder `./fw`) wird **automatisch**:
- `version` in version.json erhöht (z.B. 1.0.1 → 1.0.2)
- `index.html` (meta rettbase-version) aktualisiert

`buildNumber` bleibt unverändert – APK-Updates laufen über den Play Store. Die Version in `pubspec.yaml` wird bei nativen Builds separat gepflegt.

## version.json

Wird vom Skript `scripts/inject_version.js` automatisch gepflegt:

```json
{
  "version": "1.0.1",
  "buildNumber": "2",
  "downloadUrl": "https://app.rettbase.de/apk/app-release.apk",
  "releaseNotes": ""
}
```

- **version:** fortlaufend für Web (1.0.1, 1.0.2, …)
- **buildNumber:** bleibt gesetzt (APK über Play Store)
- **downloadUrl:** bei Bedarf manuell anpassen

## Deploy-Reihenfolge

```bash
# 1. Web (erhöht Version automatisch, deployt version.json)
./scripts/deploy_web.sh

# 2. APK (version.json/pubspec bereits aktuell)
flutter build apk
# APK deployen (z.B. nach build/web/ oder eigener Host)

# 3. iOS (analog)
flutter build ios
# … App Store / TestFlight
```

## Update-Check in den Apps

- **Web:** Vergleicht meta-Version mit version.json
- **Android/iOS:** Rufen version.json ab, vergleichen mit gebauter Version
