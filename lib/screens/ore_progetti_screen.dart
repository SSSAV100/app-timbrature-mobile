import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../core/work_hours.dart';
import '../models/project.dart';
import '../models/project_task.dart';
import '../models/time_entry.dart';
import '../models/timesheet_entry.dart' show SyncStatus, TimesheetPunch;
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../widgets/time_entry_tile.dart';

class OreProgettiScreen extends StatefulWidget {
  const OreProgettiScreen({super.key});

  @override
  State<OreProgettiScreen> createState() => _OreProgettiScreenState();
}

class _OreProgettiScreenState extends State<OreProgettiScreen> {
  static const _tolerance = Duration(minutes: 5);

  DateTime _selectedDate = DateTime.now();
  List<Project> _projects = [];
  List<TimeEntry> _entries = [];
  Duration _workedDuration = Duration.zero;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadEverything();
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
        LocalDbService.instance.getPunchesForDate(_selectedDate),
      ]);

      setState(() {
        _projects = results[0] as List<Project>;
        _entries = results[1] as List<TimeEntry>;
        _workedDuration = calculateWorkedDuration(results[2] as List<TimesheetPunch>);
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
      _entries.fold(0.0, (sum, e) => sum + e.hours);

  double get _workedHours => _workedDuration.inMinutes / 60.0;

  bool get _hoursMatch =>
      (_totalEnteredHours - _workedHours).abs() * 60 <= _tolerance.inMinutes;

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
      ),
    );

    if (result == null) return;

    await LocalDbService.instance.saveTimeEntry(result);
    await _loadEverything();
    SyncService.instance.syncAll().then((_) => mounted ? _loadEverything() : null);
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
                ),
              ),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ore timbrate', style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
                Text(
                  '${_workedHours.toStringAsFixed(2)} h',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ore ripartite', style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
                Text(
                  '${_totalEnteredHours.toStringAsFixed(2)} h',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Icon(
            _hoursMatch ? Icons.check_circle : Icons.error_outline,
            color: _hoursMatch ? AppColors.success : Colors.orange,
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

  const _AddTimeEntrySheet({required this.projects, required this.date});

  @override
  State<_AddTimeEntrySheet> createState() => _AddTimeEntrySheetState();
}

class _AddTimeEntrySheetState extends State<_AddTimeEntrySheet> {
  final _uuid = const Uuid();
  final _hoursController = TextEditingController();
  final _noteController = TextEditingController();

  Project? _selectedProject;
  ProjectTask? _selectedTask;

  @override
  void initState() {
    super.initState();
    _selectedProject = widget.projects.first;
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    final hours = double.tryParse(_hoursController.text.replaceAll(',', '.'));
    if (_selectedProject == null || hours == null || hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un numero di ore valido.')),
      );
      return;
    }

    final entry = TimeEntry(
      localId: _uuid.v4(),
      projectId: _selectedProject!.id,
      taskId: _selectedTask?.id,
      date: widget.date,
      hours: hours,
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
            onChanged: (p) => setState(() {
              _selectedProject = p;
              _selectedTask = null;
            }),
          ),
          const SizedBox(height: 12),
          if (tasks.isNotEmpty)
            DropdownButtonFormField<ProjectTask>(
              initialValue: _selectedTask,
              decoration: const InputDecoration(labelText: 'Task/attività (opzionale)'),
              items: tasks
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.description)))
                  .toList(),
              onChanged: (t) => setState(() => _selectedTask = t),
            ),
          if (tasks.isNotEmpty) const SizedBox(height: 12),
          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Ore (es. 3.5)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Nota (opzionale)'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Aggiungi'),
            ),
          ),
        ],
      ),
    );
  }
}
