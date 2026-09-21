import 'timesheet_entry.dart' show SyncStatus;

/// Una riga di ripartizione ore: quante ore, su quale progetto e task, in
/// che giorno, con un'eventuale nota testuale. Vedi specifica funzionale,
/// sezione 6.
///
/// [hoursWorked] è le ore da caricare sullo stipendio del dipendente,
/// sempre valorizzato. [hoursBillable] è le ore da caricare sul
/// progetto/fatturare al cliente: per i progetti **Standard**
/// (Cantieri/Acquedotti) coincide sempre con [hoursWorked] (un dipendente
/// che segna 3 ore lavora 3 ore tanto sul progetto quanto sullo
/// stipendio); per i progetti **Service** è un valore distinto che
/// l'operaio inserisce esplicitamente, perché le ore fatturate al cliente
/// e le ore pagate al dipendente possono legittimamente differire.
///
/// Salvata sempre prima in locale (stesso pattern di TimesheetPunch): non
/// va persa nemmeno se inserita offline in cantiere.
class TimeEntry {
  final String localId;
  final String projectId;
  final String? taskId;
  final DateTime date; // solo la data (senza ora) del giorno lavorativo
  final double hoursWorked;
  final double? hoursBillable; // null per i progetti Standard: coincide con hoursWorked
  final String? note;
  SyncStatus status;
  String? errorMessage;

  TimeEntry({
    required this.localId,
    required this.projectId,
    required this.date,
    required this.hoursWorked,
    this.taskId,
    this.hoursBillable,
    this.note,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  /// Ore effettive da caricare sul progetto/fatturare al cliente: per i
  /// progetti Standard coincidono sempre con le ore stipendio.
  double get effectiveBillableHours => hoursBillable ?? hoursWorked;

  /// True se le due quantità differiscono (possibile solo per i progetti
  /// Service): usato dalla UI per mostrare entrambi i valori invece di uno solo.
  bool get hasDistinctBillableHours =>
      hoursBillable != null && hoursBillable != hoursWorked;

  /// Payload inviato all'API AL di Business Central.
  Map<String, dynamic> toBcJson() {
    return {
      'projectId': projectId,
      if (taskId != null) 'taskId': taskId,
      'date': _dateOnly(date),
      'hoursWorked': hoursWorked,
      'hoursBillable': effectiveBillableHours,
      if (note != null && note!.isNotEmpty) 'note': note,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'project_id': projectId,
      'task_id': taskId,
      'date': _dateOnly(date),
      'hours': hoursWorked,
      'hours_billable': hoursBillable,
      'note': note,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  factory TimeEntry.fromDbMap(Map<String, dynamic> map) {
    return TimeEntry(
      localId: map['local_id'] as String,
      projectId: map['project_id'] as String,
      taskId: map['task_id'] as String?,
      date: DateTime.parse(map['date'] as String),
      hoursWorked: (map['hours'] as num).toDouble(),
      hoursBillable: (map['hours_billable'] as num?)?.toDouble(),
      note: map['note'] as String?,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

