# Web-Build mit Versionserhöhung

Damit `flutter build web` die Version automatisch erhöht:

```bash
cd /Users/mikefullbeck/RettBase/app
source scripts/activate.sh
flutter build web
```

**Einmal pro Terminal-Session** `source scripts/activate.sh` ausführen – danach erhöht `flutter build web` automatisch die Version.
