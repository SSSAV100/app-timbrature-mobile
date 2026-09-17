import '../models/timesheet_entry.dart';

/// Calcola il tempo lavorato in una giornata a partire dalla sequenza di
/// timbrature (entrata/uscita/inizio pausa/fine pausa), secondo la stessa
/// logica usata per decidere se l'utente è "attualmente dentro" in
/// home_screen.dart.
///
/// Le timbrature vengono ordinate per orario; il tempo lavorato è la somma
/// degli intervalli tra un evento di "inizio presenza" (entrata o fine
/// pausa) e il successivo "fine presenza" (uscita o inizio pausa). Se la
/// giornata è ancora aperta (es. l'utente ha timbrato entrata e non ha
/// ancora timbrato uscita), l'intervallo aperto non viene conteggiato:
/// meglio sottostimare le ore che sovrastimarle in un controllo di
/// coerenza mostrato all'utente.
Duration calculateWorkedDuration(List<TimesheetPunch> punchesForDay) {
  final sorted = [...punchesForDay]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  Duration total = Duration.zero;
  DateTime? openSince;

  for (final punch in sorted) {
    final isStart = punch.type == PunchType.entrata || punch.type == PunchType.finePausa;
    final isEnd = punch.type == PunchType.uscita || punch.type == PunchType.inizioPausa;

    if (isStart) {
      openSince ??= punch.timestamp;
    } else if (isEnd && openSince != null) {
      total += punch.timestamp.difference(openSince);
      openSince = null;
    }
  }

  return total;
}
