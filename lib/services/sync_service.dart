import 'package:connectivity_plus/connectivity_plus.dart';

import 'bc_api_service.dart';
import 'local_db_service.dart';

/// Coordina l'invio a Business Central di tutto ciò che viene registrato
/// offline (timbrature e righe ore), non appena la connessione torna
/// disponibile.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  bool _isSyncing = false;

  /// Sincronizza sia le timbrature sia le righe ore in coda. Da chiamare
  /// all'avvio dell'app e ogni volta che la connessione torna disponibile
  /// (vedi listener in home_screen.dart).
  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = !connectivity.contains(ConnectivityResult.none);
      if (!isOnline) return;

      await _syncPendingPunches();
      await _syncPendingTimeEntries();
      await _syncPendingBollettini();
      await _syncPendingAssenze();
      await _syncPendingNoteSpese();
      await _syncPendingApprovalDecisions();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncPendingPunches() async {
    final pending = await LocalDbService.instance.getPendingPunches();
    for (final punch in pending) {
      try {
        await BcApiService.instance.submitPunch(punch);
        await LocalDbService.instance.markSynced(punch.localId);
      } catch (e) {
        await LocalDbService.instance.markFailed(punch.localId, e.toString());
        // Si prosegue con le altre timbrature in coda anche se una fallisce.
      }
    }
  }

  Future<void> _syncPendingTimeEntries() async {
    final pending = await LocalDbService.instance.getPendingTimeEntries();
    for (final entry in pending) {
      try {
        await BcApiService.instance.submitTimeEntry(entry);
        await LocalDbService.instance.markTimeEntrySynced(entry.localId);
      } catch (e) {
        await LocalDbService.instance.markTimeEntryFailed(entry.localId, e.toString());
        // Si prosegue con le altre righe in coda anche se una fallisce.
      }
    }
  }

  Future<void> _syncPendingBollettini() async {
    final pending = await LocalDbService.instance.getPendingBollettini();
    for (final bollettino in pending) {
      try {
        await BcApiService.instance.submitBollettino(bollettino);
        await LocalDbService.instance.markBollettinoSynced(bollettino.localId);
      } catch (e) {
        await LocalDbService.instance.markBollettinoFailed(bollettino.localId, e.toString());
        // Si prosegue con gli altri bollettini in coda anche se uno fallisce.
      }
    }
  }

  Future<void> _syncPendingAssenze() async {
    final pending = await LocalDbService.instance.getPendingAssenze();
    for (final assenza in pending) {
      try {
        await BcApiService.instance.submitAssenza(assenza);
        await LocalDbService.instance.markAssenzaSynced(assenza.localId);
      } catch (e) {
        await LocalDbService.instance.markAssenzaFailed(assenza.localId, e.toString());
        // Si prosegue con le altre richieste in coda anche se una fallisce.
      }
    }
  }

  Future<void> _syncPendingNoteSpese() async {
    final pending = await LocalDbService.instance.getPendingNoteSpese();
    for (final nota in pending) {
      try {
        await BcApiService.instance.submitNotaSpesa(nota);
        await LocalDbService.instance.markNotaSpesaSynced(nota.localId);
      } catch (e) {
        await LocalDbService.instance.markNotaSpesaFailed(nota.localId, e.toString());
        // Si prosegue con le altre note spese in coda anche se una fallisce.
      }
    }
  }

  Future<void> _syncPendingApprovalDecisions() async {
    final pending = await LocalDbService.instance.getPendingApprovalDecisions();
    for (final decision in pending) {
      try {
        await BcApiService.instance.submitApprovalDecision(decision);
        await LocalDbService.instance.markApprovalDecisionSynced(decision.localId);
      } catch (e) {
        await LocalDbService.instance.markApprovalDecisionFailed(decision.localId, e.toString());
        // Si prosegue con le altre decisioni in coda anche se una fallisce.
      }
    }
  }
}
