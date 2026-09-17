# App Timbrature — Moduli 1-2: Login + Timbratura + Ore su progetti

Questa versione contiene i primi due moduli funzionanti dell'app aziendale
descritta nella Specifica Funzionale (v2.0): login aziendale, selezione
del cantiere, timbratura entrata/uscita, e ripartizione delle ore
timbrate su progetti/task con controllo di coerenza — tutto con coda
offline e sincronizzazione automatica verso Business Central. Nessun
middleware esterno: l'app parla solo con Business Central e con Firebase
(per le notifiche push, non ancora attivate in questa versione).

**Cosa NON contiene ancora questa versione** (moduli successivi):
bollettino di intervento, ferie/assenze, note spese, notifiche push.
La doppia scrittura verso SwissSalary avviene interamente lato Business
Central dopo l'approvazione delle ore (vedi specifica, sezione 3.2):
l'app non parla mai direttamente con SwissSalary.

---

## 1. Prerequisiti sul tuo computer

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (canale stable)
- Android Studio (gratuito) per compilare/testare su Android
- Un account [GitHub](https://github.com) — già presente ✅
- Un account [Codemagic](https://codemagic.io) (piano gratuito) — da creare quando saremo pronti a compilare per iOS
- **Non serve un Mac**: iOS verrà compilato in cloud tramite Codemagic
- **Nota versioni**: `flutter_appauth` richiede almeno Android 7.0 (API 24)
  come `minSdk` (già confermato funzionante nella build Codemagic) e usa
  un'API leggermente diversa a seconda della versione — questo progetto è
  allineato alla versione 12.x (vedi `pubspec.yaml`).

## 2. Creare il progetto Flutter reale a partire da questi file

Questi file (`lib/`, `pubspec.yaml`) sono il cuore dell'app, ma un progetto
Flutter ha bisogno anche delle cartelle native `android/` e `ios/`, che si
generano automaticamente con un comando (non le ho incluse perché sono
migliaia di file di boilerplate standard, generati identici per tutti):

```bash
# 1. Crea un progetto Flutter vuoto con il nome e l'identificativo giusti
flutter create --org com.nomeazienda -i swift -a kotlin app_timbrature
cd app_timbrature

# 2. Sostituisci i file generati con quelli che ti ho preparato:
#    copia dentro questa cartella il contenuto di lib/, pubspec.yaml,
#    .gitignore e README.md che ti ho consegnato (sovrascrivendo quelli
#    generati automaticamente).

# 3. Installa le dipendenze
flutter pub get

# 4. Verifica che non ci siano errori
flutter analyze
```

> Sostituisci `com.nomeazienda` con l'identificativo reale che vuoi dare
> all'app (es. `com.tuaazienda`) — va scelto una volta sola, prima della
> prima pubblicazione, perché identifica l'app sugli store.

## 3. Configurazione Azure AD (obbligatoria prima di poter fare login)

1. Vai su [portal.azure.com](https://portal.azure.com) → **Azure Active
   Directory** (Microsoft Entra ID) → **Registrazioni app** → **Nuova
   registrazione**.
2. Nome: es. "App Timbrature Mobile".
3. Tipi di account supportati: **Solo account in questa organizzazione**.
4. Piattaforma di reindirizzamento: scegli **Mobile e desktop**, e come URI
   inserisci: `msauth://com.nomeazienda.timbrature/callback` (usa lo stesso
   identificativo scelto al passo 2).
5. **Non generare alcun client secret**: è un'app mobile pubblica, non ne
   serve uno (e non andrebbe mai incorporato nel codice di un'app mobile).
6. In **Autorizzazioni API** → **Aggiungi un'autorizzazione** → cerca
   "Dynamics 365 Business Central" → seleziona `user_impersonation`.
7. Copia **Application (client) ID** e **Directory (tenant) ID** dalla
   pagina "Panoramica" della registrazione.
8. Apri `assets/client_config.json` e sostituisci `azureTenantId` e
   `azureClientId` con i valori copiati, e `redirectUri` con l'URI usato al
   passo 4. **Non serve toccare nessun file .dart**: è tutto in questo
   unico file JSON.
9. **Solo Android**: apri `android/app/build.gradle.kts` (generato al punto
   2) e, dentro `defaultConfig`, aggiungi lo schema del redirect URI
   scelto al passo 4 (la parte prima di `://`, es. `msauth`):
   ```kotlin
   manifestPlaceholders["appAuthRedirectScheme"] = "msauth"
   ```
   Senza questo passaggio, il login su Android compila correttamente (una
   build verde su Codemagic non lo segnala) ma fallisce silenziosamente a
   runtime: il browser non riesce a "tornare" nell'app dopo il login. Su
   iOS non serve alcun passaggio equivalente.

## 4. API attese da Business Central (da sviluppare lato AL)

L'app si aspetta che la tua estensione AL esponga alcune API personalizzate.
Questo è il "contratto" tra app e BC — puoi implementarlo con qualunque
logica interna, purché rispetti input/output descritti qui.

### `GET /assignedProjects`

Restituisce i progetti/cantieri assegnati all'utente autenticato
(identificato dal token Azure AD ricevuto), con i relativi task/attività
annidati (usati dal modulo "Ore su progetti").

```json
{
  "value": [
    {
      "id": "CANT-001",
      "description": "Cantiere Via Stazione 12",
      "projectType": "Standard",
      "tasks": [
        { "id": "T10", "description": "Scavo e fondazioni" },
        { "id": "T20", "description": "Getto solette" }
      ]
    },
    {
      "id": "SERV-045",
      "description": "Manutenzione impianto Cliente Rossi SA",
      "projectType": "Service",
      "tasks": []
    }
  ]
}
```

`projectType` è `"Standard"` o `"Service"` (vedi specifica, sezione 5).
`tasks` può essere una lista vuota se il progetto non ha task specifici.

### `POST /timePunches`

Riceve una singola timbratura da registrare (e da cui, secondo la logica
che deciderai in AL, generare/aggiornare la riga ore del giorno).

Payload inviato dall'app:

```json
{
  "projectId": "CANT-001",
  "punchType": "entrata",
  "timestamp": "2026-09-17T07:02:15.000Z"
}
```

`punchType` può essere: `entrata`, `uscita`, `inizioPausa`, `finePausa`.
Risposta attesa: `200 OK` (o `201 Created`) in caso di successo; qualunque
altro codice viene interpretato dall'app come errore, e la timbratura resta
in coda locale per un nuovo tentativo automatico.

### `POST /timeEntries`

Riceve una singola riga di ripartizione ore su progetto/task (modulo "Ore
su progetti", vedi specifica funzionale sezione 6). Business Central, una
volta approvata la riga, si occupa internamente di propagarla sia al
modulo Progetti sia a SwissSalary — l'app non parla mai direttamente con
SwissSalary (vedi specifica, sezione 3.2).

Payload inviato dall'app:

```json
{
  "projectId": "CANT-001",
  "taskId": "T10",
  "date": "2026-09-17",
  "hours": 3.5,
  "note": "Scavo lato nord"
}
```

`taskId` e `note` sono opzionali (possono essere assenti dal payload se
non valorizzati). Stessa logica di risposta e di coda offline di
`/timePunches`.

L'URL completo che l'app compone per queste chiamate è (vedi
`lib/core/config.dart`):

```
https://api.businesscentral.dynamics.com/v2.0/<bcTenantId>/<bcEnvironment>/api/<customApiPublisher>/<customApiGroup>/<customApiVersion>/assignedProjects
https://api.businesscentral.dynamics.com/v2.0/<bcTenantId>/<bcEnvironment>/api/<customApiPublisher>/<customApiGroup>/<customApiVersion>/timePunches
https://api.businesscentral.dynamics.com/v2.0/<bcTenantId>/<bcEnvironment>/api/<customApiPublisher>/<customApiGroup>/<customApiVersion>/timeEntries
```

Aggiorna in `assets/client_config.json` i valori `bcEnvironment`,
`customApiPublisher`, `customApiGroup`, `customApiVersion` in modo che
coincidano con quelli scelti nella tua estensione AL (anche qui, nessun
file .dart da modificare).

## 5. Provare l'app in locale

```bash
flutter run
```

Va lanciato con un emulatore Android avviato (o un telefono collegato via
USB con debug abilitato). Finché i valori in `config.dart` sono ancora
placeholder, il login e le chiamate API non funzioneranno: è normale, va
completata prima la configurazione dei punti 3 e 4.

## 6. Caricare il progetto su GitHub

```bash
git init
git add .
git commit -m "Primo modulo: login e timbratura"
git branch -M main
git remote add origin https://github.com/<tuo-utente>/<nome-repo>.git
git push -u origin main
```

(Crea prima la repository vuota su github.com, senza README, per evitare
conflitti con `git push`.)

## 7. Compilare e pubblicare (quando saremo a quel punto)

Con Codemagic collegato alla repository GitHub, la pipeline gratuita può
compilare sia Android che iOS e inviarli in automatico. Preparo la
configurazione (`codemagic.yaml`) quando arriviamo alla fase di rilascio
— non è necessaria per proseguire lo sviluppo dei prossimi moduli.

**Importante — distribuzione privata, non App Store pubblico (iOS):**
questa è un'app aziendale ad uso interno di una singola azienda cliente
per volta, non un'app rivolta al pubblico generico. Le linee guida Apple
(punto 3.2.2) riservano l'App Store pubblico ad app per "una vasta gamma
di clienti esterni", e il punto 4.3 (Spam) vieta esplicitamente di
pubblicare più app quasi identiche (stesso codice, solo branding diverso)
dallo stesso account sviluppatore — è uno scenario che capita spesso ai
fornitori di soluzioni white-label e che porta al rifiuto delle app
successive alla prima.

Il canale corretto per questo caso è **Apple Business Manager – Custom
Apps** (distribuzione privata): stessa infrastruttura dell'App Store
(aggiornamenti automatici inclusi), ma l'app è visibile e installabile
solo dall'organizzazione del cliente specifico a cui viene assegnata, non
è cercabile pubblicamente. Nessun impatto sul codice: cambia solo
l'impostazione "Privata" anziché "Pubblica" in App Store Connect, più la
registrazione (gratuita) della vostra azienda su Apple Business Manager.
Per Android esiste l'equivalente (Managed Google Play, distribuzione
privata per organizzazione), anche se Google è storicamente più
permissivo su questo aspetto specifico.

## 8. Onboarding di un nuovo cliente (uso come prodotto rivendibile)

L'app è pensata fin dall'inizio per essere ricompilata per clienti diversi
senza toccare il codice. Per una nuova build cliente, la procedura è
sempre la stessa checklist:

1. **`assets/client_config.json`** — sostituire con i valori del nuovo
   cliente (nome azienda, colore del brand in esadecimale, tenant/client ID
   Azure AD del cliente, ambiente e nomi API di Business Central del
   cliente). Vedi sezioni 3 e 4 sopra per come ottenere questi valori.
2. **`assets/branding/icon.png`** — icona del cliente (1024x1024 px), poi
   lanciare `flutter pub run flutter_launcher_icons` per generare
   automaticamente tutte le icone native Android/iOS.
3. **`assets/branding/logo.png`** — logo mostrato nella schermata di login
   (opzionale in questa prima versione, che usa un'icona segnaposto).
4. **Nome pacchetto/bundle ID** — se il cliente richiede un proprio
   identificativo univoco (anziché una variante di
   `com.nomeazienda.timbrature`), va rigenerato il progetto nativo con
   `flutter create --org com.clientexyz ...` come al punto 2 di questa guida.
5. **Distribuzione** — ogni cliente ottiene una propria app assegnata alla
   propria organizzazione tramite Apple Business Manager (distribuzione
   privata, vedi sezione 7) e/o Managed Google Play, pubblicata dal vostro
   account sviluppatore: l'abbonamento annuale Apple (99 USD/anno) e quello
   una tantum Google (25 USD) coprono un numero illimitato di app, quindi
   rivendere a più clienti non moltiplica questi costi.

Nessun passaggio di questa checklist richiede di scrivere o modificare
codice Dart: è pensata per essere eseguita anche da chi segue solo la
parte Business Central/commerciale del progetto.

## 9. Prossimi moduli

Nell'ordine suggerito dalla roadmap della specifica funzionale:

1. ✅ Login + Timbratura
2. ✅ Ore su progetti/task (ripartizione ore, controllo di coerenza con le
   timbrature; la doppia scrittura verso SwissSalary avviene lato BC dopo
   l'approvazione, non è compito dell'app)
3. Bollettino di intervento digitale (progetti Service, firma cliente)
4. Ferie, Assenze (malattia/infortunio) e Note spese
5. Notifiche push (Firebase)
