# Service Management di Business Central: analisi per l'app

Analisi del sorgente della Base Application 28.5 (`src/Service`, `src/Projects/TimeSheet`),
29.09.2026. Serve da base per la sezione Service dell'app. Il codice Service attuale,
basato su Job/Job Task, va sostituito (vedi `PROJECT_REFERENCE.md`, sezione 3.1).

## Modello dati

| Tabella | Ruolo | Campi chiave per l'app |
|---|---|---|
| Service Header (5900) | Ordine di assistenza (Document Type = Order) | Customer No., Ship-to (indirizzo intervento), Description, Service Order Type, Priority, Status (Pending / In Process / Finished / On Hold), Response Date/Time, Starting/Finishing Date/Time, Contract No., **Work Description** (BLOB), Assigned User ID (responsabile del documento, non il tecnico) |
| Service Item Line (5901) | Oggetto dell'intervento (apparecchio/impianto) sull'ordine | Service Item No., Item No., Serial No., Description, **Repair Status Code**, Starting/Finishing Date/Time, Warranty, Contract No., codici guasto (Fault Reason/Area/Symptom/Fault/Resolution) |
| Service Line (5902) | Ore, materiali, costi dell'intervento | Type (Item / **Resource** / Cost / G/L Account), No. (= Resource No. per le ore), Quantity, Qty. to Ship / to Consume / to Invoice, **Work Type Code** (normale, trasferta, straordinario…), **Service Item Line No.**, Job No./Job Task No. (opzionali), Time Sheet No./Line/Date |
| **Service Order Allocation (5950)** | **Assegnazione del tecnico** | Resource No., Resource Group No., Document No., Service Item Line No., **Allocation Date**, Allocated Hours, Starting/Finishing Time, Status (Nonactive / Active / Finished / Canceled / Reallocation Needed), Service Started, Posted |
| Repair Status (5927) | Codici di stato dell'intervento (tabella, non enum) | flag Initial, In Process, Finished, Partly Serviced, Referred, Spare Part Ordered/Received, Waiting for Customer, Posting Allowed |
| Service Comment Line | Note | Type: General, **Fault**, **Resolution**, Accessory, Internal, Loaner. Per la riga oggetto: Table Name = Service Header, No. = ordine, Table Line No. = Service Item Line No. |
| Service Item (5940) | Anagrafica apparecchio del cliente | No., Serial No., Item No., Customer/Ship-to, Location of Service Item, garanzie Labor/Parts, Response Time, Preferred Resource, contratti attivi |
| Service Contract Header/Line (5965/5964) | Contratti | Status Signed/Cancelled, periodi, Response Time. Per il tecnico conta soprattutto: sotto contratto/garanzia sì o no |
| Fault Area/Symptom/Fault/Resolution (5915–5921) | Codici guasto | livello usato deciso da Service Mgt. Setup "Fault Reporting Level" |
| Work Type (200), Service Cost (5905), Service Order Type (5903) | Tipi lavoro, costi fissi (trasferta), tipi ordine | |

## Chi fa cosa: assegnazione al tecnico

- Ogni Service Item Line crea un'allocazione vuota (Nonactive). Il dispatcher la compila da
  **Resource Allocations** / Dispatch Board con risorsa e data: diventa **Active**.
- "Lavoro del tecnico X oggi" = Service Order Allocation con Resource No. = X, Allocation Date
  = oggi (o intervallo), Status = Active, Posted = false (chiave 6 della tabella), poi join su
  Service Item Line e Service Header.
- Tecnico dall'utente dell'app: nell'app c'è già `SwS Employee."SS Resource No."` (il campo
  che usiamo per le ore di cantiere). In alternativa lo standard è Resource."Time Sheet Owner
  User ID" = UserId().
- SwissSalary **non ha integrazione con il Service**: nessuna estensione su Resource/Service.

## Avanzamento dell'intervento

Validare **Repair Status Code** sulla Service Item Line fa già quasi tutto:
- stato con flag *In Process* → Starting Date/Time = ora, allocazione "Service Started";
- *Finished* → Finishing Date/Time, allocazioni Finished (con Fault Reason Code se obbligatorio);
- *Partly Serviced* / *Referred* → allocazione **Reallocation Needed**: è la
  "segnalazione di ripianificazione" della specifica, già prevista da BC;
- lo Status dell'ordine è vincolato dai flag "…Status Allowed" dei Repair Status.

## Registrazione (posting)

- Codeunit **5980 "Service-Post"**: `SetPostingOptions(Ship, Consume, Invoice)`,
  `SetHideValidationDialog(true)`, `SetSuppressCommit`, `SetPostingDate`, poi `Run(ServiceHeader)`
  (schema del report 6001 "Batch Post Service Orders"). Nessun Confirm proprio; la finestra di
  avanzamento solo con GuiAllowed.
- **Mai** 5981 "Service-Post (Yes/No)", Post+Print, Post and Send: StrMenu/Confirm → errore da API.
- Registrazione parziale: Qty. to Ship / to Consume sulle righe volute, 0 sulle altre.
- Cosa crea:
  - **Ship**: Service Shipment, Service Ledger Entry, Item Ledger (materiali),
    **Res. Ledger Entry Usage** (ore), Warranty Ledger se in garanzia.
  - **Consume**: se la riga ha Job No. + Job Task No. → Job Ledger Entry; altrimenti Res. Ledger a prezzo 0.
  - **Invoice**: fattura, G/L, cliente, Res. Ledger Sale.
- Ore per la busta paga: dopo la registrazione stanno in Res. Ledger Entry (Usage, Order Type =
  Service). Ma SwissSalary non le legge: il lato stipendio va alimentato da noi (come per il cantiere).
- Undo spedizione/consumo possibili (UndoServiceShipmentLine / UndoServiceConsumptionLine).

## Fogli presenze (alternativa, sconsigliata per l'app)

Time Sheet Line tipo Service (Service Order No.), Open → Submitted → Approved; con Service Mgt.
Setup "Copy Time Sheet to Order" le righe approvate diventano Service Line. Richiede Resource
"Use Time Sheet" e un Time Sheet Header per ogni periodo; se la risorsa usa i fogli presenze e
manca il foglio per la data, anche la registrazione dell'ordine va in errore. Più pesante della
Service Line diretta.

## Allegati, firma, stampa

- **Document Attachment** è supportato sulla Service Header (codeunit 6459) e segue i documenti
  registrati: firma cliente, foto e PDF del bollettino possono andare lì.
- BC **non ha** campi firma nel Service.
- Report standard: 5900 Service Order, 5913 Service - Shipment (dopo la spedizione), 5936
  Service Item Worksheet.

## API

Nessuna pagina API standard per il Service (né in Base App né in API v2): tutto custom.

## Dialoghi da evitare da API

- Allocation Date nel passato → Message; CancelAllocation → RunModal.
- Time sheet: usare Submit/Approve diretti, non le varianti *IfConfirmed.
- Eventi IsHandled disponibili su allocazione, posting, time sheet.
