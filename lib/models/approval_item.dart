/// Tipologia di elemento da approvare, come da specifica sui due flussi:
/// - [oreCantiereStraordinario]: ore Standard/Cantieri-Acquedotti che
///   superano l'orario contrattuale giornaliero (approvate automaticamente
///   da Business Central se pari all'orario contrattuale; instradate qui
///   solo quando lo superano).
/// - [oreServiceProgetti]: il lato "Progetti" delle ore Service (il lato
///   "Salari" è approvato separatamente e nativamente in Business Central,
///   non in questa app).
enum ApprovalType { oreCantiereStraordinario, oreServiceProgetti }

/// Un elemento in attesa dell'approvazione dell'utente corrente. Letto
/// live da Business Central (non c'è motivo di tenerne una copia offline:
/// una lista di approvazioni obsoleta sarebbe più dannosa che utile).
class ApprovalItem {
  final String id; // identificativo del record lato Business Central
  final ApprovalType type;
  final String employeeName;
  final String projectDescription;
  final DateTime date;
  final double hours;
  final String? note;

  const ApprovalItem({
    required this.id,
    required this.type,
    required this.employeeName,
    required this.projectDescription,
    required this.date,
    required this.hours,
    this.note,
  });

  factory ApprovalItem.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String? ?? 'oreCantiereStraordinario';
    return ApprovalItem(
      // json['id'] è l'Entry No. (Integer) della pagina AL: un cast rigido
      // a String romperebbe il parsing se BC lo serializza come numero
      // JSON. toString() funziona sia con un numero sia con una stringa.
      id: json['id']?.toString() ?? '',
      type: rawType == 'oreServiceProgetti'
          ? ApprovalType.oreServiceProgetti
          : ApprovalType.oreCantiereStraordinario,
      employeeName: json['employeeName'] as String? ?? '',
      projectDescription: json['projectDescription'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      hours: (json['hours'] as num? ?? 0).toDouble(),
      note: json['note'] as String?,
    );
  }
}
