/// Stato di un intervento, ricavato in BC dal Repair Status della riga
/// oggetto dell'ordine di assistenza (vedi SS.ServiceAssignmentApi.Page.al).
enum ServiceState { toDo, inProgress, finished, reschedule }

/// Un intervento assegnato al tecnico: una Service Order Allocation di BC
/// (ordine di assistenza + riga oggetto + giorno), con i dati di ordine e
/// cliente. Letto da GET /serviceAssignments.
class ServiceAssignment {
  final int id; // Entry No. dell'allocazione
  final String orderNo;
  final int itemLineNo;
  final DateTime allocationDate;
  final double allocatedHours;
  final ServiceState state;
  final String orderDescription;
  final String itemDescription;
  final String priority;
  final String zoneCode;
  final String customerName;
  final String address;
  final String postCode;
  final String city;
  final String contactName;
  final String phone;
  final String workDescription;

  /// Inizio effettivo registrato da BC ("Inizia"), se c'è.
  final DateTime? startedAt;

  const ServiceAssignment({
    required this.id,
    required this.orderNo,
    required this.itemLineNo,
    required this.allocationDate,
    required this.allocatedHours,
    required this.state,
    required this.orderDescription,
    required this.itemDescription,
    required this.priority,
    required this.zoneCode,
    required this.customerName,
    required this.address,
    required this.postCode,
    required this.city,
    required this.contactName,
    required this.phone,
    required this.workDescription,
    this.startedAt,
  });

  String get fullAddress => [address, '$postCode $city'.trim()].where((e) => e.isNotEmpty).join(', ');

  factory ServiceAssignment.fromJson(Map<String, dynamic> json) {
    return ServiceAssignment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      orderNo: json['orderNo'] as String? ?? '',
      itemLineNo: (json['itemLineNo'] as num?)?.toInt() ?? 0,
      allocationDate: DateTime.tryParse(json['allocationDate'] as String? ?? '') ?? DateTime.now(),
      allocatedHours: (json['allocatedHours'] as num?)?.toDouble() ?? 0,
      state: ServiceState.values.asNameMap()[json['state'] as String? ?? ''] ?? ServiceState.toDo,
      orderDescription: json['orderDescription'] as String? ?? '',
      itemDescription: json['itemDescription'] as String? ?? '',
      priority: json['priority'] as String? ?? '',
      zoneCode: json['zoneCode'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      address: json['address'] as String? ?? '',
      postCode: json['postCode'] as String? ?? '',
      city: json['city'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      workDescription: json['workDescription'] as String? ?? '',
      startedAt: _parseStartedAt(json['startedAt'] as String?),
    );
  }

  // BC restituisce "0001-01-01T00:00:00Z" per un DateTime vuoto.
  static DateTime? _parseStartedAt(String? raw) {
    final value = DateTime.tryParse(raw ?? '');
    if (value == null || value.year < 2000) return null;
    return value.toLocal();
  }
}

/// Tipo lavoro delle ore di intervento (Work Type di BC).
class WorkType {
  final String code;
  final String description;
  const WorkType({required this.code, required this.description});

  factory WorkType.fromJson(Map<String, dynamic> json) =>
      WorkType(code: json['code'] as String? ?? '', description: json['description'] as String? ?? '');
}

/// Articolo utilizzabile come materiale (Item di BC).
class MaterialItem {
  final String no;
  final String description;
  final String unitOfMeasure;
  const MaterialItem({required this.no, required this.description, required this.unitOfMeasure});

  factory MaterialItem.fromJson(Map<String, dynamic> json) => MaterialItem(
        no: json['no'] as String? ?? '',
        description: json['description'] as String? ?? '',
        unitOfMeasure: json['unitOfMeasure'] as String? ?? '',
      );
}
