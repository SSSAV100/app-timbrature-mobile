# App Timbrature — Riferimento tecnico di progetto

> Documento di contesto per Claude Code. Riassume tutte le decisioni di
> architettura, le regole di business e le insidie tecniche già scoperte
> e risolte in questo progetto. Consultalo prima di modificare codice
> relativo ad autenticazione, API Business Central, o logica di
> approvazione — evita di far ripetere indagini già chiuse.

---

## 1. Architettura generale

- **App Flutter, nessun middleware esterno.** L'app parla direttamente
  con Business Central (via API custom AL) e con Firebase (solo per le
  notifiche push, non ancora implementate). Nessun server intermedio da
  pagare o mantenere.
- **Business Central è l'unico backend applicativo**, non solo
  l'anagrafica. La logica di business (auto-approvazione, calcolo
  trasferta, doppia scrittura verso SwissSalary) vive lato AL, non
  nell'app. L'app si limita a raccogliere dati e mostrare stato.
- **Multi-cliente fin dal principio**: tutta la configurazione
  specifica del cliente (tenant Azure, colori, nome azienda, ID società
  BC) vive in un unico file, `assets/client_config.json` — mai
  hardcoded nel codice Dart. Per una build "cliente B" si sostituisce
  solo quel file (+ icona), zero righe di codice da toccare.
- **Distribuzione**: pubblicazione dal vostro account sviluppatore
  Apple/Google (non del cliente), tramite **distribuzione privata**
  (Apple Business Manager – Custom Apps), non App Store pubblico
  generico. Motivo: le linee guida Apple (3.2.2 — l'App Store pubblico è
  per app rivolte a "una vasta gamma di clienti esterni") e il divieto
  esplicito di app quasi identiche pubblicate in serie dallo stesso
  account (4.3, Spam) rendono il canale pubblico rischioso per un
  modello white-label a più clienti.

## 2. Stack tecnico

| Componente | Scelta | Note |
|---|---|---|
| Framework | Flutter | Codebase unica iOS/Android |
| Login | `flutter_appauth` **12.x o successivo** | Vedi sezione 4: la 11.x manca del supporto UIScene, causa blocchi silenziosi |
| Storage sicuro token | `flutter_secure_storage` | Keychain iOS / Keystore Android |
| Database locale (coda offline) | `sqflite` | Solo coda temporanea, MAI anagrafica: BC resta l'unica fonte di verità |
| Geolocalizzazione | `geolocator` | Un solo punto GPS per timbratura, permesso "quando in uso", mai tracciamento continuo |
| Foto | `image_picker` | Fotocamera o galleria |
| Firma su schermo | `signature` | Solo per il bollettino Service |
| PDF | `pdf` | Generato localmente per il bollettino, condiviso subito via `share_plus` |
| Connettività | `connectivity_plus` | Trigger di sincronizzazione automatica al ritorno online |
| Build/distribuzione | Codemagic (cloud, no Mac necessario per build ordinarie) | Un Mac fisico resta comunque utile per debug nativo profondo (vedi sezione 4) |

## 3. Regole di business

### 3.1 Due tipi di progetto, comportamento diverso

| | Standard (Cantieri/Acquedotti) | Service |
|---|---|---|
| Appuntamenti | Nessuno: il dipendente sceglie da solo il progetto | Ricevuti da BC (**non ancora implementato in app**) |
| Ore | Un solo valore (`hoursWorked` = `hoursBillable` sempre) | Due valori distinti: `hoursWorked` (stipendio) e `hoursBillable` (fatturato al cliente) — possono differire |
| Bollettino | Non previsto (solo eventuale registro materiali, **non ancora implementato**) | Sì: firma cliente, materiali, foto, PDF, fatturazione diretta |
| Approvazione ore | Automatica se il totale giornaliero = orario contrattuale; altrimenti **responsabile di cantiere**, in app | Due passaggi: **responsabile Progetti** (in app) poi **responsabile Salari** (nativo in BC, non in app) |
| Cliente assente alla firma | N/A | Passa ad approvazione interna del **responsabile ufficio** (nativo in BC) |
| Ripianificazione intervento | N/A | Tecnico segnala (nota + allegato), l'ufficio ripianifica **in BC**, non in app (**segnalazione non ancora implementata**) |

### 3.2 Ferie, assenze, note spese

- **Tutto gestito in ore, mai in giorni** — ferie, malattia, infortunio.
- Malattia e infortunio: allegato (foto certificato/referto) **obbligatorio**.
- Note spese: importo sempre in **CHF**, ricevuta fotografata **obbligatoria**.
- Nessun flusso di approvazione implementato per questi tre moduli (per scelta esplicita, per ora si raccoglie e si invia).

### 3.3 Trasferta (calcolo distanza)

- L'app cattura **solo un punto GPS** al momento della timbratura (non tracciamento continuo).
- Il **calcolo della distanza e la fascia di trasferta li fa Business Central**, non l'app: la sede centrale e le fasce del CCL sono configurate lato BC, così cambiano senza ricompilare l'app.
- Le fasce esatte del CCL erano ancora da ricevere dal cliente all'ultimo aggiornamento di questo documento — verificare lo stato con il team BC.

### 3.4 Ruoli e chi approva dove

| Ruolo | Approva | Dove |
|---|---|---|
| `dipendente` | — (sempre presente) | — |
| `responsabileCantiere` | Straordinario progetti Standard | **In app** (schermata Approvazioni) |
| `responsabileProgetti` | Lato Progetti delle ore Service | **In app** (schermata Approvazioni) |
| Responsabile Salari | Lato Salari delle ore Service | **Nativo in BC** (Approvals + app ufficiale Microsoft Business Central) — nessuna schermata custom |
| Responsabile Ufficio | Bollettino senza firma cliente | **Nativo in BC** — nessuna schermata custom |

I ruoli sono letti da BC (`GET /me`) ad ogni avvio, mai calcolati o
salvati lato app.

**Chi approva è definito sulla commessa, non sul dipendente** (ogni
commessa può avere un responsabile diverso):

- Standard, straordinario: campo `Capo Cantiere` (gruppo App Timbrature
  della scheda commessa).
- Service, lato Progetti: campo standard BC `Project Manager` /
  Responsabile progetto (gruppo Generale della scheda commessa).
- Commessa senza responsabile: si usa l'`Approvatore Predefinito` della
  scheda dipendente; se manca anche quello, la riga resta senza
  approvatore ed è decidibile solo in BC (pagina "Approvazione Ore").
- L'approvatore viene fissato sulla riga ore al momento dell'invio
  (campo `Approver User ID`): ognuno vede e decide solo le righe
  assegnate a lui.
- I ruoli `responsabileCantiere` / `responsabileProgetti` si ricavano da
  lì: responsabile di almeno una commessa aperta del tipo corrispondente,
  oppure righe in sospeso assegnate. Non esistono più spunte di ruolo
  sulla scheda dipendente (tolte il 26.09.2026).

## 4. Insidie note (già scoperte e risolte — non re-indagare da zero)

Ordinate per probabilità di essere la causa di un problema simile in futuro.

1. **`flutter_appauth` deve essere 12.x o successivo.** La 11.x manca del
   supporto nativo UISceneDelegate su iOS: `authorize()` si blocca
   indefinitamente (timeout) senza errore chiaro. Warning da cercare nei
   log se ricompare: *"Plugin FlutterAppauthPlugin uses deprecated
   application lifecycle events"*.

2. **`redirectUri` deve terminare con `/`.** Microsoft Entra ID aggiunge
   sempre una barra finale al redirect effettivo
   (`...://auth/?code=...`), anche se in Azure è registrato senza. AppAuth
   confronta il path carattere per carattere e **scarta silenziosamente**
   (nessun errore) qualunque redirect non combaciante — l'app resta in
   attesa fino al timeout, mentre il browser si chiude normalmente
   (sembra tutto ok). Verificare sempre che l'URI su Azure e
   `redirectUri` in `client_config.json` terminino entrambi con `/`.

3. **Lo schema del redirect deve essere univoco per app**: formato
   `msauth.<bundle-id>` (es. `msauth.com.salarysolution.appTimbrature`),
   **mai** il generico `msauth` nudo. Apple rifiuta lo schema generico in
   revisione con l'errore ITMS-90155 "Disallowed URL schemes".

4. **Tutte le API di Business Central richiedono il segmento
   `companies(id)`** nell'URL, subito dopo la versione dell'API — sia le
   API standard sia quelle custom. Senza, BC risponde `404 Resource not
   found` cercando la risorsa alla radice (dove esiste solo l'entità
   `companies`). Un 404 qui NON è un problema di permessi (quello darebbe
   401/403): è quasi sempre l'URL sbagliato. Per trovare l'ID società:
   `GET .../api/v2.0/companies` con lo stesso token, leggere il campo
   `id`.

5. **`roles` (da `GET /me`) arriva come stringa CSV**
   (`"dipendente,responsabileCantiere"`), non come array JSON: le API
   page di BC non possono restituire un vero array per un campo scalare.
   Fare `.split(',')` lato app.

6. **Chiavi OData**: se il campo chiave AL è **Integer** (es. `Entry
   No.`), va passato **senza apici** nell'URL (`approvalDecisions(123)`).
   Se è testuale (`Code`), **con apici singoli**
   (`nomeEntita('ABC-001')`). Un apice di troppo o mancante causa un 400
   o 404 a seconda del caso.

7. **PATCH su API BC richiede l'header `If-Match`** (controllo di
   concorrenza ottimistica OData). Usare `If-Match: *` per non dover
   leggere prima l'ETag del record, salvo che serva davvero il controllo
   di concorrenza puntuale.

8. **Nome e forma dei campi devono combaciare esattamente con la pagina
   AL**, comprese le sotto-pagine (deep insert). Esempio reale: l'app
   inviava `"photosBase64": ["<b64>", ...]` ma la pagina AL
   (`SS.ServiceReportApi.Page.al`, sotto-pagina `photos`) si aspettava
   `"photos": [{"photoBase64": "<b64>"}, ...]` — un array di oggetti, non
   di stringhe, con un nome di campo diverso. BC rifiuta i campi
   sconosciuti: verificare sempre la pagina AL reale, non assumere la
   forma del payload.

9. **iOS richiede `CFBundleURLTypes` in `Info.plist`** per il redirect
   OAuth (oltre al `manifestPlaceholders["appAuthRedirectScheme"]` su
   Android, che da solo NON basta per iOS — sono due configurazioni
   native separate, entrambe necessarie).

10. **Permessi iOS da dichiarare in `Info.plist`**:
    `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
    `NSLocationWhenInUseUsageDescription`, e — anche se l'app chiede solo
    il permesso "quando in uso" — anche
    `NSLocationAlwaysAndWhenInUseUsageDescription` (il plugin
    `geolocator` referenzia l'API "Always" nel codice compilato; Apple la
    richiede comunque in revisione, avviso ITMS-90683, anche se non
    viene mai usata a runtime).

11. **Xcode riformatta `ios/Runner/Base.lproj/Main.storyboard`
    automaticamente** quando il progetto resta aperto, e lo fa anche
    `flutter build ios`. Se compare tra i
    file modificati senza che nessuno l'abbia toccato volutamente:
    `git checkout -- ios/Runner/Base.lproj/Main.storyboard`.

12. **Un Mac fisico (anche economico, es. entry-level con chip A-series)
    è prezioso per il debug nativo profondo**, nonostante l'architettura
    di questo progetto sia pensata per non richiederne uno per le build
    ordinarie (quelle restano su Codemagic). Per bug di autenticazione o
    comportamento nativo che non produce errori chiari (come i punti 1 e
    2 sopra), `flutter run` diretto su un dispositivo reale + Console.app
    è enormemente più veloce che indovinare da log parziali o build
    ripetute in cloud.

## 5. Contratto API — endpoint implementati

Base URL: `https://api.businesscentral.dynamics.com/v2.0/{tenant}/{environment}/api/{publisher}/{group}/{version}/companies({companyId})/...`

| Metodo | Endpoint | Scopo |
|---|---|---|
| GET | `/me` | Utente corrente + ruoli (CSV) |
| GET | `/assignedProjects` | Progetti assegnati, con task annidati e `projectType` (Standard/Service) |
| POST | `/timePunches` | Timbratura (entrata/uscita/pausa), con GPS opzionale |
| POST | `/timeEntries` | Riga ore: `hoursWorked` + `hoursBillable` (uguali per Standard, distinti per Service) |
| POST | `/serviceReports` | Bollettino: materiali, `photos` (array di `{photoBase64}`), firme base64 |
| GET | `/vacationBalances` | Saldo ferie in ore |
| POST | `/absenceRequests` | Ferie/malattia/infortunio, con allegato per gli ultimi due |
| POST | `/expenseReports` | Nota spesa, CHF, ricevuta base64 |
| GET | `/pendingApprovals` | Richieste in attesa dell'utente corrente |
| PATCH | `/approvalDecisions({id})` | Decisione approva/respingi (id Integer, senza apici, richiede `If-Match: *`) |

Dettaglio completo di ogni payload: vedi `README.md` del progetto
Flutter, sezione 4.

## 6. Stato moduli

**Completati e testati (almeno in parte) end-to-end:**
- Login (Azure AD, con tutte le insidie della sezione 4 risolte)
- Timbrature (con GPS)
- Ore su progetti (con split ore stipendio/fattura per Service)
- Ferie, Assenze, Note spese
- Ruoli e Approvazioni (schermata in app per responsabile Cantiere/Progetti)
- Bollettino (in fase di test dopo il fix del campo `photos`)

**Non ancora implementati:**
- Appuntamenti Service (letti da BC, mostrati al tecnico)
- Materiali per Cantieri/Acquedotti (senza firma/fatturazione, a differenza del bollettino Service)
- Segnalazione ripianificazione intervento non concluso (nota + allegato)
- Notifiche push (Firebase)
- Elenco articoli reale nel bollettino (oggi testo libero, non collegato all'anagrafica articoli BC)

## 7. Decisioni di processo/strumenti (per non ridiscuterle)

- **No FlutterFlow**: costo ricorrente non necessario dato che il codice
  viene scritto direttamente; nessun vantaggio pratico per un progetto
  con logica di integrazione complessa come questo.
- **No middleware esterno** (Azure Functions, ecc.): la logica vive in
  AL, l'app chiama BC direttamente.
- **Distribuzione privata** (non store pubblico) per i motivi della
  sezione 1.
- Per problemi di autenticazione/comportamento nativo senza errori
  chiari, preferire da subito log reali (Console.app, `flutter run`
  diretto) invece di cicli di build/ipotesi — è quasi sempre più veloce,
  anche contando il tempo di procurarsi l'accesso a un Mac.
