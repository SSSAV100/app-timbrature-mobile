# Server di login App Timbrature

Server di Salary Solution per il login con **codice azienda + utente + password** degli operai
senza account Microsoft, come il server di EasyRapport per SwissSalary. Un unico server per
tutti i clienti: controlla utente e password sulla scheda dipendente SwissSalary in BC, dà
all'app un pass personale (JWT) e inoltra le chiamate dell'app al BC del cliente con
l'identità tecnica del server (service-to-service).

Chi entra con l'account Microsoft continua a parlare direttamente con BC, senza server.

## Azure (dev), creato il 15.11.2026

Sottoscrizione **MCPP Subscription** (crediti partner: solo sviluppo e test), tenant Salary
Solution `1441bb2f-4b09-496e-ab65-29a7d321f41e`, regione **Svizzera Nord**.

| Risorsa | Nome |
|---|---|
| Gruppo di risorse | `rg-apptimbrature-dev` |
| Function App (Flex Consumption, Node 20) | `func-apptimbrature-dev` → `https://func-apptimbrature-dev.azurewebsites.net` |
| Archiviazione | `stapptimbrdeva35ta` |
| Application Insights | `appi-apptimbrature-dev` |
| Key Vault (RBAC) | `kv-apptimbr-dev-a35ta` |
| Registrazione app Entra (multi-tenant) | **App Timbrature Server (dev)**, appId `ab8f15ab-f25f-4a64-8054-f1193390eb00`, permesso applicazione *Dynamics 365 Business Central → API.ReadWrite.All*, con consenso amministratore nel tenant Salary Solution |

Segreti, solo nel Key Vault e letti dalla Function tramite la sua identità gestita
(ruolo *Key Vault Secrets User*):
- `bc-client-secret`: segreto della registrazione app, scade dopo 1 anno (rinnovo: `az ad app credential reset`);
- `jwt-signing-key`: chiave per firmare i pass dell'app.

Impostazioni della Function: `BC_CLIENT_ID`, `BC_CLIENT_SECRET` e `JWT_SIGNING_KEY` (riferimenti al
Key Vault), `CUSTOMERS` = mappa *codice azienda → tenant, ambiente, società BC* (per ora `DEMO`
→ VTE_Sandbox / Demo SwissSalary).

## Produzione

Da rifare con il suffisso `-prod` in una sottoscrizione adatta alla produzione: i crediti
partner sono per uso interno, sviluppo e demo.

## Onboarding di un cliente (verificato sulla Demo il 15.11.2026)

1. **Consenso** dell'amministratore del cliente all'app **App Timbrature Server** (multi-tenant).
2. In BC del cliente, **Applicazioni Microsoft Entra** → Nuovo:
   - ID client = appId del server; ID app = ID dell'estensione
     (`a24fe510-9d63-4690-a2f6-2a843dbe707d`); stato **Abilitato**;
   - insiemi di autorizzazioni: **SS APP TIMBR**, **D365 BUS FULL ACCESS** e l'insieme
     **SwissSalary** completo, per la società dell'app.
3. **Setup utenti SwissSalary** (pagina 3009126): aggiungere l'utente dell'app Entra con il
   filtro gruppo di allocazione che vede tutti i dipendenti. Senza questo, SwissSalary
   nasconde tutti i dipendenti al server: `appLogins` e `me` restituiscono 0 righe.
4. **Setup App Timbrature** → *ID app server di login* = appId del server (per società!).
5. Aggiungere il cliente a `CUSTOMERS` nella Function: codice azienda, tenant, ambiente, società.
6. Su ogni operaio: **Nome utente app** + **Imposta password app**. Serve anche la **Risorsa**: di norma quella della scheda dipendente BC, collegata da SwissSalary ("Resource Connection" in Setup Payroll); in alternativa il campo "Risorsa (ripiego)" della sezione App Timbrature. Senza risorsa le ore restano in "Errore Registrazione" e il Service non mostra interventi.
7. Bollettino a regia: un **account email** in BC (scenario predefinito), il **Capo Cantiere** sulle
   commesse con l'email in Setup utenti e, nelle sandbox, **"Consenti richieste HttpClient"** sull'estensione
   del connettore email (es. "Email - Outlook REST API", da Gestione estensioni → Configura). Senza, il
   bollettino arriva ma l'email resta in "Errore email" (provato il 26.11.2026).
7. Licenze BC per gli operai: da chiarire con SwissSalary o con Microsoft (multiplexing).

## Verifica rapida

```bash
curl -X POST https://func-apptimbrature-dev.azurewebsites.net/api/login \
  -H "Content-Type: application/json" \
  -d '{"company":"DEMO","username":"<utente>","password":"<password>"}'
# 200 {token, expiresAt, employeeId}; 401 credenziali errate; 502 problema verso BC
```

In sviluppo `EXPOSE_ERRORS=1` aggiunge al 502 il dettaglio dell'errore di BC: in produzione
va tolto.
