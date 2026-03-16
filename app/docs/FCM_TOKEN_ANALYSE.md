# FCM-Token & Zustellung – Analyse

## 1. Token-Flow (App → Firestore)

```
saveToken(companyId, uid)
    ↓
ensureInitialized() → requestPermission, setForegroundOptions
    ↓
_getFcmTokenForNative()
    ├─ iOS: getAPNSToken() (wartet ggf. 3s Retry)
    └─ getToken()
    ↓
_saveTokenToFirestore()
    ├─ kunden/{companyId}/users/{uid}  (merge: fcmToken, fcmTokenUpdatedAt)
    └─ fcmTokens/{uid}                 (merge: fcmToken, fcmTokenUpdatedAt)
```

### Aufrufer von saveToken

| Ort | companyId-Quelle |
|-----|------------------|
| main.dart (nach Login) | prefs rettbase_company_id (= docId von kundeExists) |
| main.dart (bereits angemeldet) | prefs |
| dashboard_screen _load | effectiveCompanyId = authData.companyId \|\| widget.companyId |
| login_screen | effectiveCompanyId aus resolveLoginInfo |
| App-Resume | _lastCompanyId (von letztem saveToken) |

---

## 2. Token-Lookup (Cloud Function)

```javascript
getFcmToken(companyId, uid)
  1. kunden/{companyId}/users/{uid}.fcmToken
  2. Fallback: fcmTokens/{uid}.fcmToken
```

### companyId-Quelle im Trigger

- `onNewChatMessage`: `companyId` aus `context.params` = Pfad `kunden/{companyId}/chats/...`
- Der Pfad enthält die **Firestore-Dokument-ID** des Kunden

### Mögliche Abweichung: kundenId vs. docId

- Nutzer gibt „kkg“ ein → kundeExists liefert docId z.B. „keg-luenen“
- Token wird unter `kunden/keg-luenen/users/{uid}` gespeichert
- Chat-Pfad: `kunden/{companyId}/chats/...` – companyId ist die Doc-ID im Pfad
- Wenn Chats unter `kunden/keg-luenen/` liegen → Match
- Wenn Chats unter `kunden/kkg/` liegen (andere Doc-ID) → **kein Match**, Fallback `fcmTokens/{uid}` greift

---

## 3. Zustellung (FCM → APNs)

```
admin.messaging().send(payload)
    ↓
FCM HTTP v1 API
    ↓
APNs (Sandbox/Production je nach Token)
```

### Mögliche Fehler

| Fehler | Bedeutung |
|--------|-----------|
| `messaging/invalid-registration-token` | Token ungültig/abgelaufen |
| `messaging/registration-token-not-registered` | App deinstalliert oder Token zurückgezogen |
| `messaging/mismatched-credential` | Falscher APNs-Key oder Projekt |
| Erfolg | FCM hat angenommen – APNs-Zustellung nicht garantiert |

---

## 4. Implementierte Verbesserungen

1. **companyId-Auflösung**: `getFcmToken` nutzt `_resolveToDocId(companyId)` für kundenId→docId-Mapping
2. **Fehler-Logging**: Vollständige Fehlermeldung und Code bei `messaging().send()` (z.B. `messaging/invalid-registration-token`)
3. **Token-Länge im Log**: Erfolgreiche Sends loggen Token-Länge zur Plausibilitätsprüfung
4. **Ungültige Tokens entfernen**: Bei `invalid-registration-token` oder `registration-token-not-registered` wird der Token aus `fcmTokens/{uid}` gelöscht – beim nächsten App-Start wird ein neuer gespeichert

---

## 5. Diagnose

### Cloud Function Logs prüfen

```
Firebase Console → Functions → Logs
```

Nach neuer Chat-Nachricht:

| Log | Bedeutung |
|-----|-----------|
| `FCM an uid=X erfolgreich gesendet (Token-Länge=Y)` | FCM hat angenommen; Problem liegt bei APNs/Gerät |
| `Kein FCM-Token für uid=X (companyId=Y)` | Token fehlt in Firestore – App öffnen, ins Dashboard |
| `FCM an uid=X fehlgeschlagen: messaging/invalid-registration-token` | Token abgelaufen – wurde aus Firestore entfernt, App neu öffnen |
| `FCM an uid=X fehlgeschlagen: messaging/registration-token-not-registered` | App deinstalliert oder Token zurückgezogen |

### Token manuell prüfen

```bash
cd app/functions && node scripts/check_fcm_tokens.js [companyId]
```

Zeigt fcmTokens und kunden/{companyId}/users mit Token-Status.
