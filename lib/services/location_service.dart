import 'package:geolocator/geolocator.dart';

/// Cattura un singolo punto GPS al momento della timbratura, da usare lato
/// Business Central per calcolare la distanza dalla sede centrale e la
/// relativa zona/fascia di trasferta (vedi specifica funzionale).
///
/// Importante: questo NON è un tracciamento continuo della posizione.
/// Si chiede il permesso di localizzazione "quando in uso" (non "sempre"),
/// si cattura un solo punto con un timeout breve, e non si blocca mai la
/// timbratura: se il permesso è negato, il GPS è spento, o la richiesta va
/// in timeout, la timbratura procede comunque senza coordinate (vedi
/// home_screen.dart). L'affidabilità della timbratura viene prima di
/// tutto il resto.
class LocationService {
  LocationService._();

  static const _timeout = Duration(seconds: 6);

  /// Ritorna la posizione corrente, o null se non disponibile per
  /// qualunque motivo (permesso negato, GPS spento, timeout, errore).
  /// Non lancia mai eccezioni: il chiamante non deve gestire try/catch.
  static Future<Position?> getCurrentPositionOrNull() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _timeout,
        ),
      );
    } catch (_) {
      // GPS non disponibile, timeout, o qualunque altro errore della
      // piattaforma: meglio una timbratura senza coordinate che nessuna
      // timbratura.
      return null;
    }
  }
}
