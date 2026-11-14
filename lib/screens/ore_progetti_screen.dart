import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../core/work_time.dart';
import '../models/project.dart';
import '../models/project_task.dart';
import '../models/service_action.dart';
import '../models/time_entry.dart';
import '../models/timesheet_entry.dart' show SyncStatus;
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../widgets/sync_status_dot.dart';
import '../widgets/time_entry_tile.dart';
import 'project_report_screen.dart';

class OreProgettiScreen extends StatefulWidget {
  const OreProgettiScreen({super.key});

  @override
  State<OreProgettiScreen> createState() => _OreProgettiScreenState();
}

class _OreProgettiScreenState extends State<OreProgettiScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Project> _projects = [];
  List<TimeEntry> _entries = [];
  List<ServiceAction> _pendingReports = [];

  /// Voci ore che hanno già un bollettino (inviato o in coda).
  Set<String> _reportedEntryIds = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadEverything();
    // Ritenta subito le righe rimaste in coda o fallite.
    SyncService.instance.syncAll().then((_) => mounted ? _loadEverything() : null);
  }

  Future<void> _loadEverything() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        BcApiService.instance.fetchAssignedProjects(),
        LocalDbService.instance.getTimeEntriesForDate(_selectedDate),
        // Bollettini (e loro allegati) non ancora arrivati in BC.
        LocalDbService.instance.getPendingServiceActions().then((actions) => actions
            .where((a) =>
                a.kind == ServiceActionKind.projectReport ||
                a.kind == ServiceActionKind.projectMaterial ||
                a.kind == ServiceActionKind.projectAttachment)
            .toList()),
        _loadReportedEntryIds(),
      ]);

      setState(() {
        _projects = results[0] as List<Project>;
        _entries = results[1] as List<TimeEntry>;
        _pendingReports = results[2] as List<ServiceAction>;
        _reportedEntryIds = results[3] as Set<String>;
      });
    } catch (_) {
      setState(() {
        _loadError = 'Impossibile aggiornare i dati (verifica la connessione).';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  double get _totalEnteredHours =>
      _entries.fold(0.0, (sum, e) => sum + e.hoursWorked);


  Future<void> _changeDate(int deltaDays) async {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: deltaDays)));
    await _loadEverything();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadEverything();
  }

  Future<void> _openAddEntrySheet() async {
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun progetto disponibile: aggiorna e riprova.')),
      );
      return;
    }

    final result = await showModalBottomSheet<TimeEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTimeEntrySheet(
        projects: _projects,
        date: _selectedDate,
        existingEntries: _entries,
      ),
    );

    if (result == null) return;

    // Un punto GPS al salvataggio: mai bloccante (null se negato/spento).
    final position = await LocationService.getCurrentPositionOrNull();
    await LocalDbService.instance.saveTimeEntry(result.withPosition(position?.latitude, position?.longitude));
    await _loadEverything();
    SyncService.instance.syncAll().then((_) => mounted ? _loadEverything() : null);
  }

  Future<Set<String>> _loadReportedEntryIds() async {
    final ids = <String>{};
    final projectIds = (await LocalDbService.instance.getTimeEntriesForDate(_selectedDate)).map((e) => e.projectId).toSet();
    for (final projectId in projectIds) {
      final actions = await LocalDbService.instance.getServiceActionsFor(projectId, 0);
      for (final a in actions.where((a) => a.kind == ServiceActionKind.projectReport)) {
        final id = a.payload['_entryId'] as String?;
        if (id != null) ids.add(id);
      }
    }
    return ids;
  }

  /// Bollettino facoltativo della singola voce ore.
  Future<void> _openProjectReport(TimeEntry entry) async {
    final project = _projectFor(entry.projectId);
    if (project == null) return;
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ProjectReportScreen(project: project, entry: entry),
    ));
    if (sent == true) {
      await _loadEverything();
      SyncService.instance.syncAll().then((_) => mounted ? _loadEverything() : null);
    }
  }

  Future<void> _deleteEntry(TimeEntry entry) async {
    await LocalDbService.instance.deleteTimeEntry(entry.localId);
    await _loadEverything();
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(_selectedDate, DateTime.now());
    final dateLabel = isToday
        ? 'Oggi, ${DateFormat('d MMMM', 'it_IT').format(_selectedDate)}'
        : DateFormat('EEEE d MMMM', 'it_IT').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text('Ore su progetti')),
      body: RefreshIndicator(
        onRefresh: _loadEverything,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeDate(-1),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: Center(
                      child: Text(
                        dateLabel,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isToday ? null : () => _changeDate(1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            if (_loadError != null) ...[
              Text(_loadError!, style: const TextStyle(fontSize: 12, color: Colors.orange)),
              const SizedBox(height: 8),
            ],
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nessuna ora ripartita per questo giorno.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._entries.map(
                (entry) => TimeEntryTile(
                  entry: entry,
                  project: _projectFor(entry.projectId),
                  onDelete: () => _deleteEntry(entry),
                  hasReport: _reportedEntryIds.contains(entry.localId),
                  onReport: _projectFor(entry.projectId) == null ? null : () => _openProjectReport(entry),
                ),
              ),
            if (_pendingReports.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Bollettini in invio', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              for (final a in _pendingReports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SyncStatusDot(status: a.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${a.orderNo} · ${a.summary}', style: const TextStyle(fontSize: 12)),
                            if (a.status == SyncStatus.failed && a.errorMessage != null)
                              Text(a.errorMessage!,
                                  style: const TextStyle(fontSize: 11, color: AppColors.danger),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddEntrySheet,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi ore'),
      ),
    );
  }

  Project? _projectFor(String id) {
    for (final p in _projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(14),
      ),
      // Timbrature tolte su richiesta del cliente (14.11.2026): niente più
      // confronto ore timbrate / ore inserite, solo il totale del giorno.
      child: Row(
        children: [
          Expanded(
            child: Text('Ore inserite nel giorno', style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
          ),
          Text(
            '${_totalEnteredHours.toStringAsFixed(2)} h',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Foglio modale per l'inserimento di una nuova riga ore.
class _AddTimeEntrySheet extends StatefulWidget {
  final List<Project> projects;
  final DateTime date;

  /// Righe già inserite nel giorno, per non sovrapporre gli orari.
  final List<TimeEntry> existingEntries;

  const _AddTimeEntrySheet({required this.projects, required this.date, this.existingEntries = const []});

  @override
  State<_AddTimeEntrySheet> createState() => _AddTimeEntrySheetState();
}

class _AddTimeEntrySheetState extends State<_AddTimeEntrySheet> {
  // Errori mostrati dentro il pannello: uno SnackBar finirebbe dietro il
  // bottom sheet, invisibile.
  String? _error;
  void _showError(String message) => setState(() => _error = message);

  final _uuid = const Uuid();
  final _hoursBillableController = TextEditingController();
  TimeOfDay? _start;
  TimeOfDay? _end;
  final _noteController = TextEditingController();

  Project? _selectedProject;
  ProjectTask? _selectedTask;

  @override
  void initState() {
    super.initState();
    _selectProject(widget.projects.first);
  }

  // Con una sola attività registrabile la si preseleziona.
  void _selectProject(Project? project) {
    _selectedProject = project;
    final tasks = project?.tasks ?? const [];
    _selectedTask = tasks.length == 1 ? tasks.first : null;
  }

  @override
  void dispose() {
    _hoursBillableController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isService => _selectedProject?.type == ProjectType.service;

  void _save() {
    // L'attività è obbligatoria: la registrazione sul registro commesse di
    // BC richiede il "Job Task No.".
    if (_selectedTask == null) {
      _showError((_selectedProject?.tasks ?? const []).isEmpty
              ? 'Questo progetto non ha attività su cui registrare ore: contatta l\'ufficio.'
              : 'Seleziona l\'attività del progetto.');
      return;
    }

    // Orari Dalle-Alle (commissione paritetica): le ore si ricavano da qui.
    final hoursWorked = WorkTime.hoursBetween(_start, _end);
    if (_selectedProject == null || hoursWorked == null) {
      _showError('Indica l\'orario Dalle e Alle (la fine dopo l\'inizio).');
      return;
    }
    for (final other in widget.existingEntries) {
      final oStart = WorkTime.parse(other.startTime);
      final oEnd = WorkTime.parse(other.endTime);
      if (oStart != null && oEnd != null && WorkTime.overlaps(_start!, _end!, oStart, oEnd)) {
        _showError('Si sovrappone alla riga ${WorkTime.format(oStart)}-${WorkTime.format(oEnd)}.');
        return;
      }
    }

    double? hoursBillable;
    if (_isService) {
      hoursBillable = double.tryParse(_hoursBillableController.text.replaceAll(',', '.'));
      if (hoursBillable == null || hoursBillable <= 0) {
        _showError('Inserisci un numero di ore progetto/fattura valido.');
        return;
      }
    }

    final entry = TimeEntry(
      localId: _uuid.v4(),
      projectId: _selectedProject!.id,
      taskId: _selectedTask?.id,
      date: widget.date,
      hoursWorked: hoursWorked,
      hoursBillable: hoursBillable,
      startTime: WorkTime.format(_start!),
      endTime: WorkTime.format(_end!),
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      status: SyncStatus.pending,
    );

    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _selectedProject?.tasks ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuova riga ore', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            DropdownButtonFormField<Project>(
              initialValue: _selectedProject,
              decoration: const InputDecoration(labelText: 'Progetto/cantiere'),
              items: widget.projects
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.description)))
                  .toList(),
              onChanged: (p) => setState(() => _selectProject(p)),
            ),
            const SizedBox(height: 12),
            // Key legata al progetto: cambiando progetto il campo si
            // ricrea e riparte dall'attività preselezionata (o vuoto).
            DropdownButtonFormField<ProjectTask>(
              key: ValueKey(_selectedProject?.id),
              initialValue: _selectedTask,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Attività',
                errorText: tasks.isEmpty ? 'Nessuna attività registrabile su questo progetto' : null,
              ),
              items: tasks
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text('${t.id} · ${t.description}', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (t) => setState(() => _selectedTask = t),
            ),
            const SizedBox(height: 12),

            TimeRangeFields(
              start: _start,
              end: _end,
              onStartChanged: (t) => setState(() => _start = t),
              onEndChanged: (t) => setState(() => _end = t),
            ),
            if (_isService) ...[
              // Commessa di tipo Service (vecchio flusso): le ore da fatturare
              // possono differire da quelle lavorate (Dalle-Alle).
              const SizedBox(height: 12),
              TextField(
                controller: _hoursBillableController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Ore progetto/fattura cliente',
                  helperText: 'Ore da caricare sul progetto e da fatturare al cliente',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Nota (opzionale)'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 13, color: Colors.red)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Aggiungi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
