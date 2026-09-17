import 'timesheet_entry.dart' show SyncStatus;

/// Una singola riga di ripartizione ore: quante ore, su quale progetto e
/// task, in che giorno, con un'eventuale nota testuale. Vedi specifica
/// funzionale, sezione 6.
///
/// Salvata sempre prima in locale (stesso pattern di TimesheetPunch): non
/// va persa nemmeno se inserita offline in cantiere.
class TimeEntry {
  final String localId;
  final String projectId;
  final String? taskId;
  final DateTime date; // solo la data (senza ora) del giorno lavorativo
  final double hours;
  final String? note;
  SyncStatus status;
  String? errorMessage;

  TimeEntry({
    required this.localId,
    required this.projectId,
    required this.date,
    required this.hours,
    this.taskId,
    this.note,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  /// Payload inviato all'API AL di Business Central.
  Map<String, dynamic> toBcJson() {
    return {
      'projectId': projectId,
      if (taskId != null) 'taskId': taskId,
      'date': _dateOnly(date),
      'hours': hours,
      if (note != null && note!.isNotEmpty) 'note': note,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'project_id': projectId,
      'task_id': taskId,
      'date': _dateOnly(date),
      'hours': hours,
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
      hours: (map['hours'] as num).toDouble(),
      note: map['note'] as String?,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
