import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../core/work_time.dart';
import '../models/service_action.dart';
import '../models/service_assignment.dart';
import '../models/timesheet_entry.dart' show SyncStatus;
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../widgets/material_sheet.dart';
import '../widgets/sync_status_dot.dart';
import 'service_finish_screen.dart';
import 'service_list_screen.dart' show ServiceStateChip;

/// Dettaglio di un intervento: dati di cliente e ordine, azioni del tecnico
/// (inizia, ore, materiale, termina, da riprogrammare) e l'elenco di quanto
/// fatto dall'app su questo intervento, con lo stato di invio a BC.
/// Tutte le azioni vanno prima nella coda locale (funzionano offline).
class ServiceDetailScreen extends StatefulWidget {
  final ServiceAssignment assignment;
  const ServiceDetailScreen({super.key, required this.assignment});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  static const _uuid = Uuid();
  List<ServiceAction> _actions = [];

  ServiceAssignment get _a => widget.assignment;

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  Future<void> _loadActions() async {
    final actions = await LocalDbService.instance.getServiceActionsFor(_a.orderNo, _a.itemLineNo);
    if (mounted) setState(() => _actions = actions);
  }

  /// Stato mostrato: quello di BC, aggiornato dall'ultimo evento fatto
  /// dall'app (anche se non ancora inviato), così il tecnico vede subito
  /// l'effetto dei pulsanti anche offline.
  ServiceState get _state => ServiceAction.effectiveState(_a.state, _actions);

  Future<void> _queue(ServiceActionKind kind, Map<String, dynamic> payload, {String? filePath}) async {
    // Inizia / Da riprogrammare: un punto GPS (mai bloccante).
    if (kind == ServiceActionKind.event) {
      final position = await LocationService.getCurrentPositionOrNull();
      if (position != null) {
        payload = {...payload, 'latitude': position.latitude, 'longitude': position.longitude};
      }
    }
    await LocalDbService.instance.saveServiceAction(ServiceAction(
      localId: _uuid.v4(),
      createdAt: DateTime.now(),
      kind: kind,
      orderNo: _a.orderNo,
      itemLineNo: _a.itemLineNo,
      payload: {'orderNo': _a.orderNo, 'itemLineNo': _a.itemLineNo, ...payload},
      filePath: filePath,
    ));
    await _loadActions();
    SyncService.instance.syncAll().then((_) => _loadActions());
  }

  Future<void> _start() => _queue(ServiceActionKind.event, {
        'eventType': 'start',
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
      });

  /// Inizia automatico: ore, materiale e chiusura su un intervento non
  /// ancora iniziato mettono prima in coda l'inizio, così BC ha comunque
  /// l'ora di inizio e lo stato "In corso".
  Future<void> _ensureStarted() async {
    if (_state == ServiceState.toDo || _state == ServiceState.reschedule) await _start();
  }

  Future<void> _reschedule() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Da riprogrammare'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Motivo (es. manca un pezzo, cliente assente)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    if (note == null) return;
    if (note.isEmpty) {
      _snack('Indica il motivo: l\'ufficio lo vede per riprogrammare.');
      return;
    }
    await _queue(ServiceActionKind.event, {
      'eventType': 'reschedule',
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'note': note,
    });
  }

  Future<void> _addHours() async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _HoursSheet(),
    );
    if (payload == null) return;
    await _ensureStarted();
    await _queue(ServiceActionKind.hours, payload);
  }

  Future<void> _addMaterial() async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const MaterialSheet(),
    );
    if (payload == null) return;
    await _ensureStarted();
    await _queue(ServiceActionKind.material, payload);
  }

  Future<void> _finish() async {
    await _ensureStarted();
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ServiceFinishScreen(assignment: _a, actions: _actions)),
    );
    if (done == true) {
      await _loadActions();
      SyncService.instance.syncAll().then((_) => _loadActions());
    }
  }

  Future<void> _delete(ServiceAction action) async {
    await LocalDbService.instance.deleteServiceAction(action.localId);
    await _loadActions();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openMaps() async {
    final query = Uri.encodeComponent(_a.fullAddress);
    await launchUrl(Uri.parse('https://maps.apple.com/?q=$query'), mode: LaunchMode.externalApplication);
  }

  Future<void> _call() async {
    await launchUrl(Uri.parse('tel:${_a.phone.replaceAll(' ', '')}'));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final isFinished = state == ServiceState.finished;

    return Scaffold(
      appBar: AppBar(title: Text(_a.orderNo)),
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncService.instance.syncAll();
          await _loadActions();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_a.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                ServiceStateChip(state: state),
              ],
            ),
            // Stato cambiato dall'app ma non ancora confermato da BC (coda non
            // inviata, o errore: vedi le righe sotto "Registrato dall'app").
            if (state != _a.state)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('In attesa di conferma da Business Central',
                    style: TextStyle(fontSize: 11, color: Colors.orange)),
              ),
            const SizedBox(height: 8),
            if (_a.fullAddress.isNotEmpty)
              _InfoRow(icon: Icons.place_outlined, text: _a.fullAddress, onTap: _openMaps),
            if (_a.contactName.isNotEmpty) _InfoRow(icon: Icons.person_outline, text: _a.contactName),
            if (_a.phone.isNotEmpty) _InfoRow(icon: Icons.phone_outlined, text: _a.phone, onTap: _call),
            _InfoRow(
              icon: Icons.event_outlined,
              text: [
                DateFormat('EEE dd.MM.yyyy', 'it_IT').format(_a.allocationDate),
                if (_a.allocatedHours > 0) '${_a.allocatedHours.toStringAsFixed(1)} h previste',
                if (_a.zoneCode.isNotEmpty) 'zona ${_a.zoneCode}',
              ].join(' · '),
            ),
            const SizedBox(height: 12),
            if (_a.orderDescription.isNotEmpty)
              Text(_a.orderDescription, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            if (_a.itemDescription.isNotEmpty)
              Text(_a.itemDescription, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            if (_a.workDescription.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_a.workDescription, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state == ServiceState.toDo || state == ServiceState.reschedule)
                  FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow), label: const Text('Inizia')),
                OutlinedButton.icon(onPressed: _addHours, icon: const Icon(Icons.schedule), label: const Text('Ore')),
                OutlinedButton.icon(
                    onPressed: _addMaterial, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Materiale')),
                if (!isFinished)
                  FilledButton.icon(
                    onPressed: _finish,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Termina'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  ),
                if (!isFinished)
                  TextButton.icon(
                    onPressed: _reschedule,
                    icon: const Icon(Icons.event_repeat, color: AppColors.danger),
                    label: const Text('Da riprogrammare', style: TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (_actions.isNotEmpty) ...[
              const Text('Registrato dall\'app', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              for (final action in _actions) _ActionTile(action: action, onDelete: () => _delete(action)),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: onTap != null ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: onTap != null ? AppColors.primary : AppColors.textPrimary)),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

class _ActionTile extends StatelessWidget {
  final ServiceAction action;
  final VoidCallback onDelete;
  const _ActionTile({required this.action, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          SyncStatusDot(status: action.status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.summary, style: const TextStyle(fontSize: 13)),
                Text(DateFormat('dd.MM HH:mm').format(action.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                if (action.status == SyncStatus.failed && action.errorMessage != null)
                  Text(action.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: AppColors.danger),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Solo ciò che non è ancora in BC si può togliere.
          if (action.status != SyncStatus.synced)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// Ore di intervento divise come le vuole l'ufficio: ore Service (riga
/// dell'ordine, da fatturare) e ore stipendio (SwissSalary).
class _HoursSheet extends StatefulWidget {
  const _HoursSheet();

  @override
  State<_HoursSheet> createState() => _HoursSheetState();
}

class _HoursSheetState extends State<_HoursSheet> {
  // Errori mostrati dentro il pannello: uno SnackBar finirebbe dietro il
  // bottom sheet, invisibile.
  String? _error;
  void _showError(String message) => setState(() => _error = message);

  final _serviceController = TextEditingController();
  TimeOfDay? _start;
  TimeOfDay? _end;
  // Le ore Service seguono la durata finché il tecnico non le cambia.
  bool _serviceEdited = false;
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  List<WorkType> _workTypes = [];
  WorkType? _workType;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    BcApiService.instance.fetchWorkTypes().then((types) {
      if (!mounted) return;
      setState(() {
        _workTypes = types;
        _workType = types.isNotEmpty ? types.first : null;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _loadError = 'Tipi lavoro non disponibili: $e');
    });
  }

  @override
  void dispose() {
    _serviceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : double.tryParse(c.text.replaceAll(',', '.'));

  void _syncServiceHours() {
    final hours = WorkTime.hoursBetween(_start, _end);
    if (!_serviceEdited && hours != null) _serviceController.text = hours.toString();
  }

  void _save() {
    final service = _parse(_serviceController);
    // Ore stipendio = tempo lavorato Dalle-Alle (commissione paritetica).
    final salary = WorkTime.hoursBetween(_start, _end);
    if (salary == null) {
      _showError('Indica l\'orario Dalle e Alle (la fine dopo l\'inizio).');
      return;
    }
    if (_workType == null) {
      _showError('Scegli il tipo lavoro.');
      return;
    }
    if (service == null || service < 0) {
      _showError('Le ore Service devono essere un numero (0 se non si fatturano).');
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'date': DateFormat('yyyy-MM-dd').format(_date),
      'workTypeCode': _workType!.code,
      'hoursService': service,
      'hoursSalary': salary,
      'startTime': WorkTime.toBc(_start!),
      'endTime': WorkTime.toBc(_end!),
      if (_noteController.text.trim().isNotEmpty) 'note': _noteController.text.trim(),
    });
  }


  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ore intervento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Data'),
                child: Text(DateFormat('dd.MM.yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadError != null)
              Text(_loadError!, style: const TextStyle(fontSize: 12, color: AppColors.danger))
            else
              DropdownButtonFormField<WorkType>(
                initialValue: _workType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo lavoro'),
                items: _workTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text('${t.code} · ${t.description}')))
                    .toList(),
                onChanged: (t) => setState(() => _workType = t),
              ),
            const SizedBox(height: 12),
            TimeRangeFields(
              start: _start,
              end: _end,
              onStartChanged: (t) => setState(() {
                _start = t;
                _syncServiceHours();
              }),
              onEndChanged: (t) => setState(() {
                _end = t;
                _syncServiceHours();
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serviceController,
              onChanged: (_) => _serviceEdited = true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Ore Service',
                helperText: 'Da fatturare al cliente (le ore stipendio sono Dalle-Alle)',
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Nota (opzionale)'),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 13, color: Colors.red)),
              ),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('Aggiungi'))),
          ],
        ),
      ),
    );
  }
}
