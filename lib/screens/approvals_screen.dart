import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../models/approval_decision.dart';
import '../models/approval_item.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<ApprovalItem> _items = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final items = await BcApiService.instance.fetchPendingApprovals();
      setState(() => _items = items);
    } catch (_) {
      setState(() => _loadError = 'Impossibile aggiornare le approvazioni (verifica la connessione).');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openDecisionSheet(ApprovalItem item) async {
    final decided = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DecisionSheet(item: item),
    );
    if (decided == true) {
      setState(() => _items.removeWhere((e) => e.id == item.id));
      SyncService.instance.syncAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approvazioni')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  if (_loadError != null) ...[
                    Text(_loadError!, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                    const SizedBox(height: 12),
                  ],
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nessuna richiesta in attesa della tua approvazione.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._items.map((item) => _ApprovalTile(
                          item: item,
                          onTap: () => _openDecisionSheet(item),
                        )),
                ],
              ),
      ),
    );
  }
}

class _ApprovalTile extends StatelessWidget {
  final ApprovalItem item;
  final VoidCallback onTap;

  const _ApprovalTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final isCantiere = item.type == ApprovalType.oreCantiereStraordinario;

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
            Icon(
              isCantiere ? Icons.schedule_outlined : Icons.engineering_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.employeeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(
                    '${item.projectDescription} · ${dateFormat.format(item.date)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    isCantiere ? 'Straordinario' : 'Ore Service (lato progetti)',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text('${item.hours.toStringAsFixed(1)} h', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Foglio modale con il dettaglio della richiesta e i pulsanti
/// approva/respingi.
class _DecisionSheet extends StatefulWidget {
  final ApprovalItem item;
  const _DecisionSheet({required this.item});

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _uuid = const Uuid();
  final _noteController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _decide(ApprovalDecisionType decisionType) async {
    setState(() => _isSubmitting = true);

    final decision = ApprovalDecision(
      localId: _uuid.v4(),
      approvalItemId: widget.item.id,
      decision: decisionType,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    await LocalDbService.instance.saveApprovalDecision(decision);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${widget.item.projectDescription} · ${dateFormat.format(widget.item.date)} · ${widget.item.hours.toStringAsFixed(1)} h',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (widget.item.note != null && widget.item.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(widget.item.note!, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Nota per il dipendente (opzionale)'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => _decide(ApprovalDecisionType.rejected),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  child: const Text('Respingi'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _decide(ApprovalDecisionType.approved),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  child: const Text('Approva'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
