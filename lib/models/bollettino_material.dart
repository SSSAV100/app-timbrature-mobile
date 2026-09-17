/// Una riga di materiale/ricambio utilizzato durante l'intervento, riportata
/// nel bollettino (vedi specifica funzionale, sezione 7.1). In questa prima
/// versione la descrizione è testo libero; potrà in futuro diventare una
/// selezione da anagrafica articoli di Business Central.
class BollettinoMaterial {
  final String description;
  final double quantity;

  const BollettinoMaterial({
    required this.description,
    required this.quantity,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
      };

  factory BollettinoMaterial.fromJson(Map<String, dynamic> json) {
    return BollettinoMaterial(
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}
