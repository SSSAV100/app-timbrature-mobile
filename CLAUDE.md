# App Timbrature (Flutter)

App mobile (iOS/Android) per timbrature, ore su commessa, bollettini, ferie/assenze,
note spese e approvazioni. Parla direttamente con le API AL custom di Business Central
(nessun middleware). Il contratto delle API è in `README.md`, sezione 4.

## Dove sta cosa

- Questa repo: `~/dev/app_timbrature`, GitHub `SSSAV100/app-timbrature-mobile`, branch `main`.
- Backend AL: `~/dev/SALARY SOLUTION - App Timbrature` (Azure DevOps). Ha un suo `CLAUDE.md`.
- Si lavora **solo da questo Mac** (VS Code + Claude Code), per entrambi i progetti.
- Riferimento tecnico completo (architettura, regole di business, ruoli, insidie già
  risolte, stato moduli): `docs/PROJECT_REFERENCE.md`. Leggerlo prima di toccare login,
  API BC o approvazioni.

## Configurazione runtime

`assets/client_config.json`, letto da `lib/core/config.dart`:

- Tenant `1441bb2f-4b09-496e-ab65-29a7d321f41e`, client ID `866f42f3-3ead-490a-a931-2b9947523bfd`.
- Ambiente BC `VTE_Sandbox`, società **Demo SwissSalary** (`bcCompanyId` `9deb824e-1a8e-f011-b419-00224861978d`).
- API `api/salarysolution/timbrature/v1.0/companies({bcCompanyId})/...`: il segmento
  `companies(id)` è obbligatorio, senza BC risponde 404.
- Gli endpoint in `lib/services/bc_api_service.dart` devono coincidere con gli
  `EntitySetName` delle pagine API AL (es. `vacationBalances`, al plurale).

## Login Azure AD: cose già scoperte (non rifare il giro)

- `redirectUri` = `msauth.com.salarysolution.appTimbrature://auth/` **con slash finale**.
  Azure AD rimanda a `…://auth/?code=…`; senza slash AppAuth scarta il redirect in silenzio
  (`shouldHandleURL` fallisce sul path) e `authorize` va in timeout dopo che il browser si è
  già chiuso.
- `flutter_appauth` 12.x (supporto UIScene; la 11 non riceve il redirect con `SceneDelegate`).
- Timeout del login 3 minuti: include password + MFA dell'utente.
- Una build TestFlight e una build di sviluppo condividono il bundle ID e non possono
  convivere sul telefono: disinstallare l'una prima di installare l'altra.

## Comandi

```bash
flutter pub get
flutter analyze
flutter run -d <udid-iphone>      # debug su iPhone via USB (serve il Mac collegato)
flutter run --release             # si apre dall'icona senza Mac
```

- iOS usa **Swift Package Manager**, non CocoaPods: non c'è `Podfile`, `pod install` non serve.
- Firma: team `26QXZ9GKV3` (Salary Solution SA), firma automatica.
- In debug su iOS 14+ l'app si avvia solo da `flutter run` (toccare l'icona dà errore).
- Xcode aperto, ma anche `flutter build ios`, riformatta `ios/Runner/Base.lproj/Main.storyboard`:
  non committarlo, `git checkout -- ios/Runner/Base.lproj/Main.storyboard`.
- Installare la release sull'iPhone senza perdere login e dati locali: `flutter build ios --release`,
  poi `xcrun devicectl device install app --device <udid> build/ios/iphoneos/Runner.app`.
  `flutter install` invece disinstalla prima la versione vecchia (dati locali persi).
- Distribuzione ai colleghi via TestFlight con Codemagic (`codemagic.yaml`).

## Diagnostica

- Log temporanei con prefisso `[… DEBUG]` via `print` (visibili in `flutter run`), da
  togliere a problema risolto. Al momento non ce ne sono: gli errori restano tracciati
  con `developer.log`.
- I log nativi iOS (NSLog) non compaiono in `flutter run`: servono
  `sudo log collect --device-udid <udid>` e `log show`.
