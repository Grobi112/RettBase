# Push-Flow-Simulation – Verifikation ohne Simulator

Simulation des Ablaufs auf einem **echten iPhone** (APNs funktioniert nicht im Simulator).

---

## Szenario: Nutzer öffnet App, schließt sie, erhält Chat-Nachricht

### Phase 1: App-Start (main.dart)

```
1. Firebase.initializeApp()
2. FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler)  ← registriert
3. unawaited(PushNotificationService.initialize())  ← startet im Hintergrund
4. runApp()  ← UI startet sofort
```

**Ergebnis:** Init läuft parallel, blockiert nicht.

---

### Phase 2: initialize() (im Hintergrund)

```
1. _initFuture ??= _initializeImpl()
2. _initializeImpl():
   a. await _requestPermissions()  ← iOS: Permission-Dialog erscheint
   b. Nutzer tippt "Erlauben"  ← BLOCKIERT bis Antwort
   c. setForegroundNotificationPresentationOptions(alert, badge, sound)
   d. onMessage.listen, onMessageOpenedApp.listen
   e. getInitialMessage
   f. onTokenRefresh.listen
3. initialize() abgeschlossen
```

**Ergebnis:** Sobald Nutzer erlaubt hat, ist Init fertig. iOS hat Zeit, APNs-Token zu liefern.

---

### Phase 3: saveToken wird aufgerufen (main/dashboard)

**Aufrufer:** main.dart (vor Dashboard-Navigation) + dashboard_screen.dart (_load)

```
1. unawaited(saveToken(companyId, uid))  ← läuft im Hintergrund
2. saveToken():
   a. await ensureInitialized()  ← wartet auf initialize()
      - Wenn Init noch läuft (Permission-Dialog offen): WARTET
      - Wenn Init fertig: sofort weiter
   b. await _getFcmTokenForNative()
      - iOS: getAPNSToken()  ← muss verfügbar sein
      - Wenn null: 3s warten, Retry
      - getToken()  ← FCM-Token
      - Wenn null: 3s warten, Retry
   c. await _saveTokenToFirestore(companyId, uid, token)
```

**Reihenfolge verifiziert:**
1. ensureInitialized() → Permission muss beantwortet sein ✓
2. getAPNSToken() → iOS hat Token nach Permission + registerForRemoteNotifications ✓
3. getToken() → FCM braucht APNs-Token zuerst ✓
4. _saveTokenToFirestore → Token in Firestore ✓

---

### Phase 4: App geschlossen, Nachricht kommt

```
1. Cloud Function onNewChatMessage wird getriggert
2. getFcmToken(companyId, uid)  ← liest aus kunden/{companyId}/users/{uid} oder fcmTokens/{uid}
3. Wenn Token vorhanden: admin.messaging().send(payload)
4. Payload enthält apns.payload.aps.badge = totalUnread
5. FCM → APNs → iPhone
6. iOS zeigt Benachrichtigung + setzt Badge aus aps.badge
```

**Voraussetzung:** Token muss in Firestore sein (Phase 3 erfolgreich).

---

## Verifikation der Abhängigkeiten

| Schritt | Abhängigkeit | Erfüllt? |
|---------|--------------|----------|
| getAPNSToken() | registerForRemoteNotifications() aufgerufen | ✓ AppDelegate |
| getAPNSToken() | Permission erteilt | ✓ ensureInitialized vor getToken |
| getToken() | APNs-Token vorhanden | ✓ _getFcmTokenForNative wartet darauf |
| Token in Firestore | saveToken erfolgreich | ✓ nach ensureInitialized + getToken |
| Push ankommt | Token in Firestore + APNs-Key in Firebase | Manuell prüfen |

---

## Mögliche Fehlerquellen (nicht im Code)

1. **APNs .p8 Key nicht in Firebase** → FCM kann nicht an APNs senden
2. **Echtes Gerät** → Simulator hat kein APNs
3. **Provisioning Profile** → Push-Entitlement muss enthalten sein
4. **Benachrichtigungen deaktiviert** → Einstellungen → RettBase

---

## Fazit

Die Code-Reihenfolge ist korrekt:
- saveToken wartet auf ensureInitialized (Permission)
- getAPNSToken wird vor getToken aufgerufen (iOS)
- Retries für Timing-Probleme (3s)

**Simulation bestanden.** Auf echtem Gerät mit korrekter Firebase/Apple-Konfiguration sollte der Flow funktionieren.
