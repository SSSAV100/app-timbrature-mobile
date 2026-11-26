import 'dart:convert';

import 'service_assignment.dart' show ServiceState;
import 'timesheet_entry.dart' show SyncStatus;
import '../widgets/material_sheet.dart';

/// Tipo di azione su un intervento, ciascuna con il suo endpoint BC.
enum ServiceActionKind {
  event, // POST /serviceEvents (start / finish / reschedule)
  hours, // POST /serviceHours
  material, // POST /serviceMaterials
  attachment, // POST /serviceAttachments (file letto da filePath)
  // Bollettino facoltativo delle ore di progetto: stessa coda, con
  // orderNo = commessa e itemLineNo = 0 (solo per l'ordine di invio).
  projectReport, // POST /projectReports
  projectMaterial, // POST /projectReportMaterials
  projectAttachment, // POST /projectAttachments (file letto da filePath)
  // Pausa pranzo del giorno (26.11.2026): stessa coda, orderNo vuoto.
  lunchBreak, // POST /lunchBreaks
}

/// Un'azione del tecnico su un intervento, salvata prima in locale e inviata
/// a BC appena c'è rete, nell'ordine in cui è stata fatta (ore e materiali
/// prima della chiusura). Un'unica coda per tutto il Service.
class ServiceAction {
  final String localId;
  final DateTime createdAt;
  final ServiceActionKind kind;
  final String orderNo;
  final int itemLineNo;

  /// Corpo JSON della chiamata, senza il file (per gli allegati il base64 si
  /// legge da [filePath] al momento dell'invio).
  final Map<String, dynamic> payload;
  final String? filePath;
  SyncStatus status;
  String? errorMessage;

  ServiceAction({
    required this.localId,
    required this.createdAt,
    required this.kind,
    required this.orderNo,
    required this.itemLineNo,
    required this.payload,
    this.filePath,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  /// Stato da mostrare: quello di BC, aggiornato dall'ultimo evento fatto
  /// dall'app ([actions] dalla più recente), anche se non ancora inviato.
  static ServiceState effectiveState(ServiceState bcState, List<ServiceAction> actions) {
    final lastEvent = actions.where((a) => a.kind == ServiceActionKind.event).firstOrNull;
    if (lastEvent == null) return bcState;
    return switch (lastEvent.payload['eventType']) {
      'start' => ServiceState.inProgress,
      'finish' => ServiceState.finished,
      _ => ServiceState.reschedule,
    };
  }

  /// Testo breve per l'elenco delle azioni in attesa sull'intervento.
  String get summary => switch (kind) {
        ServiceActionKind.event => switch (payload['eventType']) {
            'start' => 'Inizio intervento',
            'finish' => 'Fine intervento',
            _ => 'Da riprogrammare',
          },
        ServiceActionKind.hours =>
          'Ore${payload['dayPart'] == null ? '' : ' ${payload['dayPart']}'}${_range()}: ${payload['hoursService']} h Service, ${payload['hoursSalary']} h stipendio (${payload['workTypeCode']})',
        ServiceActionKind.material => 'Materiale: ${MaterialSheet.label(payload)}',
        ServiceActionKind.attachment || ServiceActionKind.projectAttachment => 'Allegato: ${payload['fileName']}',
        ServiceActionKind.projectReport => 'Bollettino ${payload['date']}',
        ServiceActionKind.projectMaterial => 'Materiale: ${MaterialSheet.label(payload)}',
        ServiceActionKind.lunchBreak => 'Pausa pranzo${_range()}',
      };

  // " 07:00–12:00" dagli orari "HH:mm:ss" del payload, se presenti.
  String _range() {
    final start = payload['startTime'] as String?;
    final end = payload['endTime'] as String?;
    if (start == null || end == null || start.length < 5 || end.length < 5) return '';
    return ' ${start.substring(0, 5)}–${end.substring(0, 5)}';
  }

  Map<String, dynamic> toDbMap() => {
        'local_id': localId,
        'created_at': createdAt.toIso8601String(),
        'kind': kind.name,
        'order_no': orderNo,
        'item_line_no': itemLineNo,
        'payload_json': jsonEncode(payload),
        'file_path': filePath,
        'status': status.name,
        'error_message': errorMessage,
      };

  factory ServiceAction.fromDbMap(Map<String, dynamic> map) => ServiceAction(
        localId: map['local_id'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        kind: ServiceActionKind.values.byName(map['kind'] as String),
        orderNo: map['order_no'] as String,
        itemLineNo: (map['item_line_no'] as num).toInt(),
        payload: jsonDecode(map['payload_json'] as String) as Map<String, dynamic>,
        filePath: map['file_path'] as String?,
        status: SyncStatus.values.byName(map['status'] as String),
        errorMessage: map['error_message'] as String?,
      );
}
