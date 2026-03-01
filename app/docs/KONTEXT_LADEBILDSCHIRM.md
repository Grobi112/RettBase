# RettBase: Ladebildschirm-Kontext

> Stand: Commit `7e37cf0` – einheitlicher Ladevorgang mit Fortschrittsbalken, Kunden-ID erst nach Ladeabschluss.

## 1. Einheitlicher Ladebildschirm (Web)

| Phase | Beschreibung |
|-------|--------------|
| **Web** | Ein einziger HTML-Ladebildschirm (Logo + Fortschrittsbalken) bleibt von Seitenladung bis Ladeabschluss sichtbar. Flutter aktualisiert den Balken per DOM (`splash_loader_web.dart`). Kein Wechsel zwischen Platzhalter und SplashScreen. |
| **Native** | Flutter `SplashScreen` mit Fortschrittsbalken während `_initApp()`. |

**Wichtig:** Kunden-ID-Abfrage erscheint erst **nach** Ladeabschluss (wenn nötig).

## 2. Relevante Dateien

| Datei | Rolle |
|-------|-------|
| `lib/screens/splash_screen.dart` | Flutter-Ladebildschirm (nur Native) mit determinierter Fortschrittsanzeige |
| `lib/main.dart` | `RettBaseHome`, `_initApp`, `_initAppImpl` – Ladelogik, Progress-Update, Loader-Entfernung |
| `lib/utils/splash_loader_web.dart` | Web: Fortschritt aktualisieren, Loader entfernen |
| `web/index.html` | Einheitlicher HTML-Ladebildschirm (Web): Logo + Fortschrittsbalken, bleibt bis Ladeabschluss |

## 3. Ablauf

### 3.1 Company gespeichert, alles OK

1. Phase 1: HTML → Flutter lädt
2. Phase 2: Fortschrittsbalken (0 % → 10 % → 20 % → 85 % → 100 %)
3. Navigation zu Login oder Dashboard

### 3.2 Company gespeichert, Netzwerkfehler (kundeExists schlägt fehl)

- Optimistisch mit gespeicherter Company-ID fortfahren → Login/Dashboard
- Keine Kunden-ID-Abfrage

### 3.3 Keine Company gespeichert

1. Phase 1: HTML → Flutter lädt
2. Phase 2: Fortschrittsbalken läuft vollständig (0 % → 30 % → 70 % → 100 %, ca. 900 ms)
3. Danach: Kunden-ID-Formular (kein Abbruch dazwischen)

## 4. SplashScreen (Flutter)

- **Logo:** Einheitlich 120 px Höhe (identisch mit HTML-Platzhalter für nahtlosen Übergang)
- **Fortschrittsbalken:** Determiniert, füllt sich von links nach rechts
- **Kein Knight Rider / Shimmer** – einfacher Balken
- **Responsive:** Schmal (< 400 px): 180 px Breite, sonst 240 px

## 5. HTML-Ladebildschirm (web/index.html)

- Ein einziger Ladebildschirm für den gesamten Ladeprozess (kein Wechsel, kein Flackern)
- **hostElement:** Flutter rendert in `#flutter_host` (web/flutter_bootstrap.js), ersetzt nicht den body
- Loader bleibt als Overlay (z-index:9999) erhalten, bis Flutter `removeLoader()` aufruft
- Inhalt: Logo (120 px) + Fortschrittsbalken (0 % → 100 %)
- Flutter aktualisiert den Balken via `splash_loader.updateProgress()` während `_initApp()`
- Wird entfernt via `splash_loader.removeLoader()` bei Navigation oder Kunden-ID-Formular

## 6. Kunden-ID-Formular

- Wird **nur** angezeigt, wenn `!companyConfigured || companyId.isEmpty`
- Integriert in `RettBaseHome` (keine Navigation zu `CompanyIdScreen` während Init)
- Erscheint erst **nach** vollständigem Lauf des Fortschrittsbalkens
