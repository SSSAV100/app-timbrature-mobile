import 'timesheet_entry.dart' show SyncStatus;

enum ApprovalDecisionType { approved, rejected }

/// La decisione (approva/respingi) presa da un responsabile su un
/// [ApprovalItem]. Salvata sempre prima in locale: un responsabile può
/// trovarsi in cantiere con poca rete quanto un dipendente qualsiasi, la
/// decisione non deve andare persa.
class ApprovalDecision {
  final String localId;
  final String approvalItemId;
  final ApprovalDecisionType decision;
  final String? note;
  SyncStatus status;
  String? errorMessage;

  ApprovalDecision({
    required this.localId,
    required this.approvalItemId,
    required this.decision,
    this.note,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  Map<String, dynamic> toBcJson() {
    return {
      'decision': decision.name,
      if (note != null && note!.isNotEmpty) 'note': note,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'approval_item_id': approvalItemId,
      'decision': decision.name,
      'note': note,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  factory ApprovalDecision.fromDbMap(Map<String, dynamic> map) {
    return ApprovalDecision(
      localId: map['local_id'] as String,
      approvalItemId: map['approval_item_id'] as String,
      decision: ApprovalDecisionType.values.byName(map['decision'] as String),
      note: map['note'] as String?,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }
}
