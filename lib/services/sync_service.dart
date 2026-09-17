import 'package:connectivity_plus/connectivity_plus.dart';

import 'bc_api_service.dart';
import 'local_db_service.dart';

/// Coordina l'invio a Business Central delle timbrature registrate offline,
/// non appena la connessione torna disponibile.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  bool _isSyncing = false;

  /// Da chiamare all'avvio dell'app e ogni volta che la connessione torna
  /// disponibile (vedi listener in home_screen.dart).
  Future<void> syncPendingPunches() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = !connectivity.contains(ConnectivityResult.none);
      if (!isOnline) return;

      final pending = await LocalDbService.instance.getPendingPunches();
      for (final punch in pending) {
        try {
          await BcApiService.instance.submitPunch(punch);
          await LocalDbService.instance.markSynced(punch.localId);
        } catch (e) {
          await LocalDbService.instance
              .markFailed(punch.localId, e.toString());
          // Si prosegue con le altre timbrature in coda anche se una fallisce.
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
