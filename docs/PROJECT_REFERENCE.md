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
| Database locale (coda offline) | `sqflite` | Coda temporanea di ciò che va inviato; BC resta l'unica fonte di verità. Unica copia locale di dati BC: l'ultimo elenco commesse/attività (`cache/assigned_projects.json`), usato solo senza rete per poter timbrare e registrare ore offline |
| Geolocalizzazione | `geolocator` | Dal 14.11.2026: un punto GPS al salvataggio di una riga ore (`timeEntries`) e su Inizia/Termina/Da riprogrammare (`serviceEvents`). Permesso "quando in uso", mai bloccante, nessun tracciamento continuo. Non più sulla timbratura, tolta |
| Foto | `image_picker` | Fotocamera o galleria |
| Firma su schermo | `signature` | Bollettini (Service e ore di progetto) |
| PDF | `pdf` | Generato localmente per il bollettino, condiviso subito via `share_plus` |
| Connettività | `connectivity_plus` | Trigger di sincronizzazione automatica al ritorno online |
| Build/distribuzione | Codemagic (cloud, no Mac necessario per build ordinarie) | Un Mac fisico resta comunque utile per debug nativo profondo (vedi sezione 4) |

## 3. Regole di business

### 3.1 Cantieri e Service

> **Una sola app, moduli per dipendente (decisione del 28.09.2026).**
> `GET /me` restituisce i moduli (`progetti` sempre, `service` se è attivo
> "Tecnico Service" sulla scheda dipendente). Alcuni dipendenti fanno
> entrambi i lavori.
>
> - **Cantieri (progetti):** commesse Job e attività, il dipendente sceglie
>   da solo commessa e attività; ore = ore fatturabili; straordinario
>   approvato dal Capo Cantiere in app; bollettino facoltativo per singola
>   voce ore.
> - **Service:** ordini di assistenza standard di BC (Service Order
>   Allocation, Repair Status, righe Risorsa/Articolo), API proprie
>   (`serviceAssignments`, `serviceEvents`, `serviceHours`,
>   `serviceMaterials`, `serviceAttachments`).
>
> Il vecchio Service basato su commesse Job (`Tipo Commessa` = Service,
> approvazione `oreServiceProgetti`, `POST /serviceReports`) è stato
> **rimosso** il 15.11.2026 (AL 1.0.0.29, app 0.7.1+21).
>
> Analisi del modulo Service di BC (tabelle, assegnazione tecnici, stati,
> posting, allegati): `docs/SERVICE_BC_ANALYSIS.md`.
>
> **Service fase 2 (idea di Michele, 29.09.2026): riprogrammazione
> autonoma.** Con "Da riprogrammare" il tecnico vede i prossimi giorni
> liberi, calcolati come capacità della risorsa meno le ore già assegnate
> (Service Order Allocation), e in cima i giorni con interventi nella
> stessa zona o in una zona vicina. Sceglie un giorno e si riassegna
> l'intervento (`ServAllocationManagement.AllocateDate`), visibile
> all'ufficio nella Dispatch Board. Da decidere: capacità dei tecnici in BC
> (Res. Capacity), definizione delle zone vicine, limiti alla prenotazione
> (giorni massimi o conferma dell'ufficio).

### 3.2 Ferie, assenze, note spese

- **Tutto gestito in ore, mai in giorni** — ferie, malattia, infortunio.
- Malattia e infortunio: allegato (foto certificato/referto) **obbligatorio**.
- Note spese: importo sempre in **CHF**, ricevuta fotografata **obbligatoria**.
- Nessun flusso di approvazione implementato per questi tre moduli (per scelta esplicita, per ora si raccoglie e si invia).

### 3.2b Registrazione delle ore

- **Orari Dalle-Alle** (14.11.2026, richiesta della commissione paritetica):
  ogni riga ore, di progetto o Service, ha inizio e fine. Le ore si
  ricavano da lì e BC le divide in mattino/pomeriggio alle 12:00 (pagina
  BC "Ore mattino/pomeriggio", esportabile in Excel). Una giornata normale
  sono due righe (es. 07:00-12:00 e 13:00-16:30). Service: le ore stipendio
  sono Dalle-Alle, le ore Service da fatturare restano a parte.

- Ore Standard entro l'orario contrattuale giornaliero: registrate subito;
  oltre: straordinario, in approvazione al Capo Cantiere della commessa.
- Tutte le ore dall'app vanno sulla commessa con **Tipo riga = Budget e
  fatturabile** (scelta del cliente, 26.09.2026).
- Attività (Job Task) obbligatoria su ogni riga ore.
- Lato stipendio: riga nel giornale SwissSalary `APPTIMBR`, tipo salario
  da "Setup App Timbrature" (8980 per le ore lavorate).

### 3.2c Bollettino delle ore di progetto (facoltativo)

- **Uno per singola voce ore** (decisione del cliente, 14.11.2026): firma di chi
  c'era in quel momento, ogni bollettino legato a commessa, attività e Dalle-Alle.
- Idea rimandata: opzione "includi le altre voci di oggi sulla stessa commessa",
  per firmare una volta sola mattina e pomeriggio dallo stesso cliente. Da
  valutare se le due firme danno fastidio.

### 3.3 Trasferta (calcolo distanza)

> **14.11.2026: timbrature tolte dall'app su richiesta del cliente** (niente
> più "Timbra entrata/uscita" in home, niente GPS). Il calcolo della
> trasferta dei cantieri dal punto GPS qui sotto non ha più dati in
> ingresso: se servirà, va ripensato. Per il Service la trasferta è per
> zona di servizio (vedi sezione 3.1 e `SERVICE_BC_ANALYSIS.md`).
> Il GPS resta, ma su righe ore e interventi (dove si trovava il
> dipendente), non per calcolare la trasferta.

- (Storico) L'app catturava **solo un punto GPS** al momento della timbratura (non tracciamento continuo).
- Il **calcolo della distanza e la fascia di trasferta li fa Business Central**, non l'app: la sede centrale e le fasce del CCL sono configurate lato BC, così cambiano senza ricompilare l'app.
- Le fasce esatte del CCL erano ancora da ricevere dal cliente all'ultimo aggiornamento di questo documento — verificare lo stato con il team BC.

### 3.4 Ruoli e chi approva dove

| Ruolo | Approva | Dove |
|---|---|---|
| `dipendente` | — (sempre presente) | — |
| `responsabileCantiere` | Straordinario sulle commesse | **In app** (schermata Approvazioni) |

I ruoli sono letti da BC (`GET /me`) ad ogni avvio, mai calcolati o
salvati lato app.

**Chi approva è definito sulla commessa, non sul dipendente** (ogni
commessa può avere un responsabile diverso):

- Straordinario: campo `Capo Cantiere` (gruppo App Timbrature della
  scheda commessa).
- Commessa senza responsabile: si usa l'`Approvatore Predefinito` della
  scheda dipendente; se manca anche quello, la riga resta senza
  approvatore ed è decidibile solo in BC (pagina "Approvazione Ore").
- L'approvatore viene fissato sulla riga ore al momento dell'invio
  (campo `Approver User ID`): ognuno vede e decide solo le righe
  assegnate a lui.
- I ruoli (`responsabileCantiere`) si ricavano da
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
   (`SS.ServiceReportApi.Page.al`, sotto-pagina `photos`, poi rimossa) si aspettava
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
    `NSLocationWhenInUseUsageDescription` e — anche se l'app chiede solo
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

13. **Trigger delle pagine API AL: `exit(false)` se l'Insert/Modify lo fai tu.**
    In `OnInsertRecord`, dopo un `Rec.Insert(true)` manuale (necessario per
    avere l'`Entry No.` AutoIncrement prima della logica), il trigger deve
    restituire `false`: con `true` BC inserisce di nuovo lo stesso record e
    risponde 400 *"The record in table … already exists"*. Stessa regola per
    `OnModifyRecord` quando la logica salva già la riga. Senza Insert/Modify
    manuale, non mettere `exit`: il valore predefinito lascia fare a BC.

14. **Registrare sul giornale commesse da API: `Job Jnl.-Post Batch` (1013).**
    `Job Jnl.-Post` (1021) chiede sempre "Registrare le righe?" (il suo
    `SetHideDialog` nasconde solo il messaggio finale, verificato sul
    sorgente BaseApp) e da API ogni Confirm/Message è l'errore *"Client
    callbacks are not supported"*. Usare la 1013 con `SetRecFilter` sulla
    riga e `SetSuppressCommit(true)`. Inoltre, sulle commesse con "Apply
    Usage Link", il "Tipo riga" va compilato, altrimenti BC chiede conferma.

15. **Tipi salario SwissSalary: i flag del tipo salario contano.** Il
    giornale accetta solo tipi non Fittizi, non Bloccati e non bloccati per
    il codice salario del dipendente (nella Demo l'8600 Ferie era bloccato).
    Con "Debit Cost Center blocked" la riga non può avere la commessa (la
    commessa porta il centro di costo): "The cost center field is blocked
    for this salary type". Il codice AL salta commessa/testo se bloccati.

16. **Allegati via API: testo base64 decodificato in AL.** Nelle pagine
    API il campo è una variabile `Text`, convertita in `OnInsertRecord` con
    `Base64 Convert` nel Blob. Il Blob esposto direttamente non si riempiva
    (malattia e note spese rifiutate con "allegato obbligatorio").

## 5. Contratto API — endpoint implementati

Base URL: `https://api.businesscentral.dynamics.com/v2.0/{tenant}/{environment}/api/{publisher}/{group}/{version}/companies({companyId})/...`

| Metodo | Endpoint | Scopo |
|---|---|---|
| GET | `/me` | Utente corrente + ruoli (CSV) |
| GET | `/assignedProjects` + `/assignedJobTasks` | Tutte le commesse aperte (visibili a tutti, nessun filtro per dipendente); le attività di tipo Registrazione arrivano dalla seconda chiamata e l'app le abbina per `projectId` |
| POST | `/timePunches` | Timbratura (entrata/uscita/pausa). **Non più usata dall'app dal 14.11.2026** (timbrature tolte); l'API resta in BC |
| POST | `/timeEntries` | Riga ore con `startTime`/`endTime`; `hoursBillable` = `hoursWorked` |
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
- ~~Timbrature (con GPS)~~: tolte dall'app il 14.11.2026 su richiesta del cliente
- Ore su progetti (Dalle-Alle, mattino/pomeriggio)
- Ferie, Assenze, Note spese
- Ruoli e Approvazioni (schermata in app per il Capo Cantiere)
- Service sugli ordini di assistenza, bollettino facoltativo delle ore di progetto

**Verificato end-to-end (26.09.2026):**
- Ore su progetti Standard: dall'app alla commessa (movimento) e al giornale
  SwissSalary `APPTIMBR`, riga "Registrata". L'errore SwissSalary *"Journal
  is in posting."* dipendeva dallo stato del giornale in BC, non dal codice.
- Approvazione in app dello straordinario Standard (Capo Cantiere della
  commessa), con registrazione automatica dopo l'approvazione.
- Pagina BC "Righe Ore App Timbrature" con azione "Registra di nuovo" per
  le righe in "Errore Registrazione" (riparte dal passo fallito, nessuna
  doppia registrazione).
- Ferie, malattia (con certificato) e note spese (con ricevuta): allegati
  inviati in base64 e decodificati in AL nel Blob, righe SwissSalary con
  data e quantità/importo; pagine BC "Ferie e Assenze App Timbrature" e
  "Note Spese App Timbrature" con "Registra di nuovo" (28.09.2026).
- Note spese con commessa: attività obbligatoria (SwissSalary la vuole),
  importo come Quantità 1 × Tasso. Allegati visibili in BC con "Mostra
  ricevuta" / "Mostra allegato" nelle due pagine.
- Offline: timbratura e riga ore in modalità aereo, inviate da sole al
  ritorno della rete (elenco commesse dalla copia locale).
- **Service fase 1** (29.09.2026, estensione 1.0.0.18): interventi dalla
  Dispatch Board, Inizia, ore divise (Service sull'ordine, stipendio su
  SwissSalary), materiale, Termina con firma/foto/PDF allegati all'ordine e
  descrizione del lavoro. Trasferta della zona: se BC la rifiuta (es. conto
  C/G del costo di servizio senza "Cat. reg. art./serv.") la chiusura va
  avanti e resta un commento sull'ordine (Ordine > Commenti, dalla 1.0.0.21).
  14.11.2026: trasferta verificata (TRASF-Z1 30 CHF aggiunta alla chiusura,
  dopo aver messo "Cat. reg. art./serv." sul conto C/G del costo). Ore
  proposte in Termina e GPS su ore ed eventi verificati. Da verificare:
  "Da riprogrammare" nella Dispatch Board.

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
