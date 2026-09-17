import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/project.dart';
import '../models/time_entry.dart';
import '../models/timesheet_entry.dart' show SyncStatus;

/// Riga che mostra una singola voce di ripartizione ore (progetto, task,
/// quantità di ore, nota) con un piccolo indicatore dello stato di
/// sincronizzazione verso Business Central.
class TimeEntryTile extends StatelessWidget {
  final TimeEntry entry;
  final Project? project;
  final VoidCallback? onDelete;

  const TimeEntryTile({
    super.key,
    required this.entry,
    required this.project,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final taskDescription = project?.tasks
        .where((t) => t.id == entry.taskId)
        .map((t) => t.description)
        .firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          _StatusDot(status: entry.status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project?.description ?? entry.projectId,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                if (taskDescription != null)
                  Text(
                    taskDescription,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                if (entry.note != null && entry.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.note!,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${entry.hours.toStringAsFixed(2)} h',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (onDelete != null && entry.status == SyncStatus.pending) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              onPressed: onDelete,
              splashRadius: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final SyncStatus status;
  const _StatusDot({required this.status});

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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
