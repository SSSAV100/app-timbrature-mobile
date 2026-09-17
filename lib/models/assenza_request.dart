import 'timesheet_entry.dart' show SyncStatus;

/// Tipologia di assenza, come da specifica funzionale sezione 8.
enum AssenzaType { ferie, malattia, infortunio }

/// Una richiesta di ferie, o una segnalazione di assenza per malattia o
/// infortunio. Coerentemente con il resto dell'app, tutto è espresso in
/// ORE (non in giorni): [hoursPerDay] si applica a ciascun giorno del
/// periodo [startDate]-[endDate] (che coincidono per un'assenza di un
/// solo giorno).
///
/// L'allegato (certificato medico per malattia, referto/dichiarazione per
/// l'assicuratore LAINF per infortunio) è obbligatorio per questi due tipi;
/// per le ferie non è richiesto. Nessun flusso di approvazione è gestito
/// in questa versione dell'app: la richiesta viene semplicemente raccolta
/// e inviata a Business Central.
class AssenzaRequest {
  final String localId;
  final AssenzaType type;
  final DateTime startDate;
  final DateTime endDate;
  final double hoursPerDay;
  final String? note;
  final String? incidentDescription; // solo infortunio
  final String? incidentLocation; // solo infortunio
  final String? attachmentPath; // percorso locale permanente
  SyncStatus status;
  String? errorMessage;

  AssenzaRequest({
    required this.localId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.hoursPerDay,
    this.note,
    this.incidentDescription,
    this.incidentLocation,
    this.attachmentPath,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  bool get requiresAttachment => type == AssenzaType.malattia || type == AssenzaType.infortunio;

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'type': type.name,
      'start_date': _dateOnly(startDate),
      'end_date': _dateOnly(endDate),
      'hours_per_day': hoursPerDay,
      'note': note,
      'incident_description': incidentDescription,
      'incident_location': incidentLocation,
      'attachment_path': attachmentPath,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  factory AssenzaRequest.fromDbMap(Map<String, dynamic> map) {
    return AssenzaRequest(
      localId: map['local_id'] as String,
      type: AssenzaType.values.byName(map['type'] as String),
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      hoursPerDay: (map['hours_per_day'] as num).toDouble(),
      note: map['note'] as String?,
      incidentDescription: map['incident_description'] as String?,
      incidentLocation: map['incident_location'] as String?,
      attachmentPath: map['attachment_path'] as String?,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
