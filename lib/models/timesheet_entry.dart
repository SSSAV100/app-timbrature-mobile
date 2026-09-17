/// Tipo di evento di timbratura.
enum PunchType { entrata, uscita, inizioPausa, finePausa }

/// Stato di sincronizzazione di una timbratura registrata localmente.
enum SyncStatus { pending, synced, failed }

/// Una singola timbratura, salvata subito in locale (vedi LocalDbService)
/// e successivamente inviata a Business Central (vedi SyncService).
/// Salvare sempre prima in locale garantisce che nessuna timbratura vada
/// persa anche in assenza di connessione in cantiere.
class TimesheetPunch {
  final String localId; // UUID generato sul dispositivo
  final String? employeeId;
  final String projectId;
  final PunchType type;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  SyncStatus status;
  String? errorMessage;

  TimesheetPunch({
    required this.localId,
    required this.projectId,
    required this.type,
    required this.timestamp,
    this.employeeId,
    this.latitude,
    this.longitude,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  /// Payload inviato all'API AL di Business Central.
  Map<String, dynamic> toBcJson() {
    return {
      'projectId': projectId,
      'punchType': type.name,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'employee_id': employeeId,
      'project_id': projectId,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  factory TimesheetPunch.fromDbMap(Map<String, dynamic> map) {
    return TimesheetPunch(
      localId: map['local_id'] as String,
      employeeId: map['employee_id'] as String?,
      projectId: map['project_id'] as String,
      type: PunchType.values.byName(map['type'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }
}
