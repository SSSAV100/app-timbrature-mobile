import 'timesheet_entry.dart' show SyncStatus;

/// Categoria di spesa, come da specifica funzionale sezione 9.
enum NotaSpesaCategoria { vitto, trasporto, carburante, alloggio, materiali, altro }

extension NotaSpesaCategoriaLabel on NotaSpesaCategoria {
  String get label => switch (this) {
        NotaSpesaCategoria.vitto => 'Vitto',
        NotaSpesaCategoria.trasporto => 'Trasporto',
        NotaSpesaCategoria.carburante => 'Carburante',
        NotaSpesaCategoria.alloggio => 'Alloggio',
        NotaSpesaCategoria.materiali => 'Materiali',
        NotaSpesaCategoria.altro => 'Altro',
      };
}

/// Una nota spesa, con importo in franchi svizzeri (CHF) e ricevuta
/// fotografata obbligatoria (vedi specifica funzionale, sezione 9 e 13.5).
/// Nessun flusso di approvazione gestito in questa versione dell'app: la
/// nota spesa viene raccolta e inviata a Business Central.
class NotaSpesa {
  final String localId;
  final DateTime date;
  final NotaSpesaCategoria category;
  final double amountChf;
  final String? description;
  final String? projectId; // opzionale, se la spesa è imputabile a un progetto
  final String receiptPath; // percorso locale permanente, obbligatorio
  SyncStatus status;
  String? errorMessage;

  NotaSpesa({
    required this.localId,
    required this.date,
    required this.category,
    required this.amountChf,
    required this.receiptPath,
    this.description,
    this.projectId,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'date': _dateOnly(date),
      'category': category.name,
      'amount_chf': amountChf,
      'description': description,
      'project_id': projectId,
      'receipt_path': receiptPath,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  factory NotaSpesa.fromDbMap(Map<String, dynamic> map) {
    return NotaSpesa(
      localId: map['local_id'] as String,
      date: DateTime.parse(map['date'] as String),
      category: NotaSpesaCategoria.values.byName(map['category'] as String),
      amountChf: (map['amount_chf'] as num).toDouble(),
      description: map['description'] as String?,
      projectId: map['project_id'] as String?,
      receiptPath: map['receipt_path'] as String,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
