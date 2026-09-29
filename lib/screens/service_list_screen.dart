import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/service_assignment.dart';
import '../services/bc_api_service.dart';
import '../services/sync_service.dart';
import 'service_detail_screen.dart';

/// Sezione Service: interventi assegnati al tecnico dall'ufficio (Dispatch
/// Board di BC), raggruppati per giorno. Offline mostra l'ultimo elenco letto.
class ServiceListScreen extends StatefulWidget {
  const ServiceListScreen({super.key});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  List<ServiceAssignment> _assignments = [];
  bool _isLoading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });
    // Prima si inviano le azioni in coda, così lo stato letto è aggiornato.
    await SyncService.instance.syncAll();
    try {
      final assignments = await BcApiService.instance.fetchServiceAssignments();
      assignments.sort((a, b) {
        final byDate = a.allocationDate.compareTo(b.allocationDate);
        return byDate != 0 ? byDate : a.orderNo.compareTo(b.orderNo);
      });
      setState(() {
        _assignments = assignments;
        if (BcApiService.instance.serviceFromCache) {
          _message = 'Offline: elenco interventi dell\'ultimo aggiornamento.';
        }
      });
    } catch (e) {
      setState(() => _message = e is BcApiException
          ? 'Impossibile caricare gli interventi. $e'
          : 'Impossibile caricare gli interventi (verifica la connessione).');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _open(ServiceAssignment assignment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServiceDetailScreen(assignment: assignment)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<ServiceAssignment>>{};
    for (final a in _assignments) {
      final day = DateTime(a.allocationDate.year, a.allocationDate.month, a.allocationDate.day);
      byDay.putIfAbsent(day, () => []).add(a);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Interventi')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_message!, style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            if (_isLoading && _assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('Nessun intervento assegnato.', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            for (final entry in byDay.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(
                  _dayLabel(entry.key),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
              for (final a in entry.value) _AssignmentTile(assignment: a, onTap: () => _open(a)),
            ],
          ],
        ),
      ),
    );
  }

  String _dayLabel(DateTime day) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final diff = day.difference(todayDate).inDays;
    final label = DateFormat('EEE dd.MM', 'it_IT').format(day);
    if (diff == 0) return 'Oggi · $label';
    if (diff == 1) return 'Domani · $label';
    if (diff == -1) return 'Ieri · $label';
    return label;
  }
}

class _AssignmentTile extends StatelessWidget {
  final ServiceAssignment assignment;
  final VoidCallback onTap;

  const _AssignmentTile({required this.assignment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignment.customerName.isEmpty ? assignment.orderNo : assignment.customerName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (assignment.orderDescription.isNotEmpty)
                    Text(assignment.orderDescription, style: const TextStyle(fontSize: 13)),
                  Text(
                    [assignment.city, if (assignment.zoneCode.isNotEmpty) 'zona ${assignment.zoneCode}', assignment.orderNo]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ServiceStateChip(state: assignment.state),
          ],
        ),
      ),
    );
  }
}

/// Etichetta colorata dello stato di un intervento.
class ServiceStateChip extends StatelessWidget {
  final ServiceState state;
  const ServiceStateChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ServiceState.toDo => ('Da fare', AppColors.primary),
      ServiceState.inProgress => ('In corso', Colors.orange),
      ServiceState.finished => ('Terminato', AppColors.success),
      ServiceState.reschedule => ('Da riprogrammare', AppColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
