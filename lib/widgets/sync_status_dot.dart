import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/timesheet_entry.dart' show SyncStatus;

/// Piccolo indicatore visivo dello stato di sincronizzazione di una
/// richiesta (arancione = in coda, verde = sincronizzata, rosso = fallita).
/// Usato in tutte le liste di richieste (ore, bollettini, ferie/assenze,
/// note spese) per coerenza visiva.
class SyncStatusDot extends StatelessWidget {
  final SyncStatus status;
  const SyncStatusDot({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.synced => AppColors.success,
      SyncStatus.failed => AppColors.danger,
      SyncStatus.pending => Colors.orange,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
