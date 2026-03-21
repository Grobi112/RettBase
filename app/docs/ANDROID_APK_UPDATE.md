# Versionierung und Update (Web, iOS, Android)

> **APK ohne Play Store (Sideload):** Ein Deploy-Befehl für APK + `version.json` + Hosting:  
> **`./scripts/deploy_apk_and_hosting.sh`** – siehe **`docs/ANDROID_APK_SIDEPLOAD_UPDATE.md`**.

**Einzige Quelle:** `web/app/download/version.json` – Web (Versionscheck) und Android (Update-Check) nutzen dieselbe URL über `AppConfig.androidUpdateCheckUrl`.

**Android (Play Store):** unten beschriebener Ablauf mit separater `pubspec`-Version.

## Ablauf: Immer zuerst Web deployen

1. **Web** wird zuerst aktualisiert und deployed (`./scripts/deploy_web.sh`)
2. **Android** danach (Play Store)
3. **iOS** danach (ebenso)

## Versionserhöhung (Web)

Bei `flutter build web` (oder `./fw`, `./scripts/build_web.sh`, `./scripts/deploy_web.sh`) wird **automatisch**:
- `version` in version.json erhöht (z.B. 1.0.9 → 1.0.10)
- `index.html` (meta rettbase-version) aktualisiert

`buildNumber` bleibt unverändert – APK-Updates laufen über den Play Store. Die Version in `pubspec.yaml` wird bei nativen Builds separat gepflegt.

## version.json

Wird vom Skript `web/increment_version.js` automatisch gepflegt (bei flutter build web, ./fw, ./scripts/build_web.sh, ./scripts/deploy_web.sh).

```json
{
  "version": "1.0.1",
  "releaseNotes": ""
}
```

- **version:** fortlaufend für Web (1.0.1, 1.0.2, …)
- **releaseNotes:** optional

## Deploy-Reihenfolge

```bash
# 1. Web (erhöht Version automatisch, deployt version.json)
./scripts/deploy_web.sh

# 2. Android (Play Store)
flutter build appbundle
# … Play Console hochladen

# 3. iOS (analog)
flutter build ios
# … App Store / TestFlight
```

## Update-Check in den Apps

- **Web:** Vergleicht meta-Version mit version.json, lädt bei neuer Version neu
- **Android:** Updates über Play Store
- **iOS:** Updates über App Store
