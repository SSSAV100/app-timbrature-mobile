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

## Onboarding di un cliente (bozza)

1. Consenso amministratore del cliente all'app **App Timbrature Server**.
2. In BC del cliente: scheda *Applicazioni Microsoft Entra* con l'appId e le autorizzazioni dell'app.
3. Aggiungere il cliente a `CUSTOMERS`: codice azienda, tenant, ambiente, società.
4. Licenze BC per gli operai: da chiarire con SwissSalary o con Microsoft (multiplexing).
