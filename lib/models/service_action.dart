import 'dart:convert';

import 'timesheet_entry.dart' show SyncStatus;

/// Tipo di azione su un intervento, ciascuna con il suo endpoint BC.
enum ServiceActionKind {
  event, // POST /serviceEvents (start / finish / reschedule)
  hours, // POST /serviceHours
  material, // POST /serviceMaterials
  attachment, // POST /serviceAttachments (file letto da filePath)
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

  /// Testo breve per l'elenco delle azioni in attesa sull'intervento.
  String get summary => switch (kind) {
        ServiceActionKind.event => switch (payload['eventType']) {
            'start' => 'Inizio intervento',
            'finish' => 'Fine intervento',
            _ => 'Da riprogrammare',
          },
        ServiceActionKind.hours =>
          'Ore: ${payload['hoursService']} h Service, ${payload['hoursSalary']} h stipendio (${payload['workTypeCode']})',
        ServiceActionKind.material =>
          'Materiale: ${payload['quantity']} × ${payload['itemNo']} ${payload['_itemDescription'] ?? ''}'.trim(),
        ServiceActionKind.attachment => 'Allegato: ${payload['fileName']}',
      };

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
