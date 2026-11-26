import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/local_files.dart';
import '../core/project_report_pdf.dart';
import '../core/theme.dart';
import '../models/project.dart';
import '../models/project_task.dart';
import '../models/service_action.dart';
import '../models/timesheet_entry.dart' show SyncStatus;
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../widgets/material_sheet.dart';
import '../widgets/sync_status_dot.dart';
import 'signature_pad_screen.dart';

/// Bollettino a regia (richiesta del cliente, 26.11.2026): modulo della home.
/// Elenco dei bollettini fatti da questo telefono, con lo stato di invio, e
/// pulsante per farne uno nuovo.
class ProjectReportsScreen extends StatefulWidget {
  const ProjectReportsScreen({super.key});

  @override
  State<ProjectReportsScreen> createState() => _ProjectReportsScreenState();
}

class _ProjectReportsScreenState extends State<ProjectReportsScreen> {
  List<_ReportSummary> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    SyncService.instance.syncAll().then((_) => mounted ? _load() : null);
  }

  Future<void> _load() async {
    final reports = await _ReportSummary.loadAll();
    if (mounted) {
      setState(() {
        _reports = reports;
        _loading = false;
      });
    }
  }

  Future<void> _newReport() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ProjectReportScreen()));
    if (sent == true) {
      await _load();
      SyncService.instance.syncAll().then((_) => mounted ? _load() : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bollettini a regia')),
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncService.instance.syncAll();
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_reports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Nessun bollettino da questo telefono.\nTocca "Nuovo bollettino" per compilarne uno.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final r in _reports) _ReportTile(report: r),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newReport,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo bollettino'),
      ),
    );
  }
}

/// Un bollettino ricostruito dalla coda locale: la riga del bollettino più
/// le azioni collegate (materiale, manodopera, allegati) per lo stato.
class _ReportSummary {
  final ServiceAction report;
  final SyncStatus status;
  final String? error;

  _ReportSummary(this.report, this.status, this.error);

  static Future<List<_ReportSummary>> loadAll() async {
    final actions = await LocalDbService.instance.getServiceActionsByKinds([
      ServiceActionKind.projectReport,
      ServiceActionKind.projectMaterial,
      ServiceActionKind.projectLabor,
      ServiceActionKind.projectAttachment,
    ]);
    final byReport = <String, List<ServiceAction>>{};
    for (final a in actions) {
      final id = a.payload['reportId'] as String?;
      if (id != null) byReport.putIfAbsent(id, () => []).add(a);
    }
    final result = <_ReportSummary>[];
    for (final a in actions.where((a) => a.kind == ServiceActionKind.projectReport)) {
      final parts = byReport[a.payload['reportId']] ?? [a];
      final failed = parts.where((p) => p.status == SyncStatus.failed).firstOrNull;
      final pending = parts.any((p) => p.status == SyncStatus.pending);
      result.add(_ReportSummary(
        a,
        failed != null ? SyncStatus.failed : (pending ? SyncStatus.pending : SyncStatus.synced),
        failed?.errorMessage,
      ));
    }
    result.sort((x, y) => y.report.createdAt.compareTo(x.report.createdAt));
    return result;
  }
}

class _ReportTile extends StatelessWidget {
  final _ReportSummary report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = report.report.payload;
    final date = DateTime.tryParse(p['date'] as String? ?? '');
    final statusText = switch (report.status) {
      SyncStatus.synced => 'Inviato',
      SyncStatus.failed => 'Non inviato',
      _ => 'In attesa di invio',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: SyncStatusDot(status: report.status)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date == null ? '' : DateFormat('EEE dd.MM.yyyy', 'it_IT').format(date)} · ${p['projectId']}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if ((p['_projectDescription'] as String?)?.isNotEmpty == true)
                  Text(p['_projectDescription'] as String, style: const TextStyle(fontSize: 13)),
                Text(
                  (p['workDescription'] as String? ?? '').replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(statusText,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: report.status == SyncStatus.failed ? AppColors.danger : AppColors.textSecondary)),
                if (report.error != null)
                  Text(report.error!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compilazione del bollettino a regia: progetto, WBS (attività), giorno,
/// descrizione intervento, materiale e manodopera a testo libero, foto e
/// firma del cliente. Genera il PDF (condiviso subito) e mette in coda verso
/// BC: bollettino, materiale, manodopera, firma, foto e per ultimo il PDF,
/// che BC salva sul bollettino e manda per email al Capo Cantiere.
class ProjectReportScreen extends StatefulWidget {
  const ProjectReportScreen({super.key});

  @override
  State<ProjectReportScreen> createState() => _ProjectReportScreenState();
}

class _ProjectReportScreenState extends State<ProjectReportScreen> {
  static const _uuid = Uuid();
  final _workDoneController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<String> _photoPaths = [];
  final List<Map<String, dynamic>> _materials = [];
  final List<Map<String, dynamic>> _labor = [];
  List<Project> _projects = [];
  Project? _project;
  ProjectTask? _task;
  DateTime _date = DateTime.now();
  Uint8List? _signature;
  bool _isSaving = false;
  String? _loadError;
  DateTime _queueTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    BcApiService.instance.fetchAssignedProjects().then((projects) {
      if (mounted) setState(() => _projects = projects);
    }).catchError((Object e) {
      if (mounted) setState(() => _loadError = 'Progetti non disponibili: $e');
    });
  }

  @override
  void dispose() {
    _workDoneController.dispose();
    _clientNameController.dispose();
    super.dispose();
  }

  void _selectProject(Project? project) {
    setState(() {
      _project = project;
      final tasks = project?.tasks ?? const [];
      _task = tasks.length == 1 ? tasks.first : null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addMaterial() async {
    final material = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const MaterialSheet(),
    );
    if (material != null) setState(() => _materials.add(material));
  }

  Future<void> _addLabor() async {
    final labor = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _LaborSheet(),
    );
    if (labor != null) setState(() => _labor.add(labor));
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80, maxWidth: 1920);
    if (picked == null) return;
    final path = await LocalFiles.copyToPermanentStorage(picked.path, 'foto_${_uuid.v4()}.jpg');
    setState(() => _photoPaths.add(path));
  }

  Future<void> _sign() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignaturePadScreen(title: 'Firma del cliente')),
    );
    if (bytes != null) setState(() => _signature = bytes);
  }

  // Coda in ordine: il bollettino prima di materiale, manodopera e allegati;
  // il PDF per ultimo (quando arriva, BC manda l'email al Capo Cantiere).
  Future<void> _queue(ServiceActionKind kind, Map<String, dynamic> payload, {String? filePath}) {
    final now = DateTime.now();
    _queueTime = now.isAfter(_queueTime) ? now : _queueTime.add(const Duration(milliseconds: 1));
    return LocalDbService.instance.saveServiceAction(ServiceAction(
      localId: _uuid.v4(),
      createdAt: _queueTime,
      kind: kind,
      orderNo: _project!.id,
      itemLineNo: 0,
      payload: {'projectId': _project!.id, ...payload},
      filePath: filePath,
    ));
  }

  String get _taskLabel => _task == null ? '' : '${_task!.id} · ${_task!.description}';

  Future<void> _send() async {
    final workDone = _workDoneController.text.trim();
    final clientName = _clientNameController.text.trim();
    if (_project == null) return _snack('Scegli il progetto.');
    if (_task == null) return _snack('Scegli la WBS.');
    if (workDone.isEmpty) return _snack('Scrivi la descrizione dell\'intervento.');
    if (_signature == null) return _snack('Serve la firma del cliente.');

    setState(() => _isSaving = true);
    try {
      final reportId = _uuid.v4();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final day = DateFormat('yyyy-MM-dd').format(_date);
      final pdf = await ProjectReportPdf.generate(
        project: _project!,
        taskLabel: _taskLabel,
        date: _date,
        materials: _materials,
        labor: _labor,
        workDone: workDone,
        clientName: clientName,
        signaturePng: _signature!,
      );
      final signaturePath = await LocalFiles.saveBytes(_signature!, 'firma_${_project!.id}_$stamp.png');

      await _queue(ServiceActionKind.projectReport, {
        'reportId': reportId,
        // Solo per l'elenco nell'app ("_" non va a BC).
        '_projectDescription': _project!.description,
        'taskId': _task!.id,
        'date': day,
        'workDescription': workDone,
        'clientName': clientName,
      });
      for (final m in _materials) {
        await _queue(ServiceActionKind.projectMaterial, {'reportId': reportId, ...m});
      }
      for (final l in _labor) {
        await _queue(ServiceActionKind.projectLabor, {'reportId': reportId, ...l});
      }
      await _queue(ServiceActionKind.projectAttachment, {'reportId': reportId, 'fileName': 'firma_${day}_$stamp.png'},
          filePath: signaturePath);
      for (var i = 0; i < _photoPaths.length; i++) {
        await _queue(ServiceActionKind.projectAttachment,
            {'reportId': reportId, 'fileName': 'foto_${day}_${i + 1}_$stamp.jpg'},
            filePath: _photoPaths[i]);
      }
      await _queue(ServiceActionKind.projectAttachment, {'reportId': reportId, 'fileName': 'bollettino_${day}_$stamp.pdf'},
          filePath: pdf.path);
      SyncService.instance.syncAll();

      await SharePlus.instance
          .share(ShareParams(files: [XFile(pdf.path)], subject: 'Bollettino a regia ${_project!.description}'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Errore nel bollettino: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _sectionHeader(String title, VoidCallback onAdd) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Aggiungi')),
        ],
      );

  Widget _removableRow(String text, VoidCallback onRemove) => Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final tasks = _project?.tasks ?? const <ProjectTask>[];
    final laborTotal = _labor.fold(0.0, (sum, l) => sum + (l['hours'] as double));
    return Scaffold(
      appBar: AppBar(title: const Text('Bollettino a regia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (_loadError != null)
            Text(_loadError!, style: const TextStyle(fontSize: 12, color: AppColors.danger))
          else
            DropdownButtonFormField<Project>(
              initialValue: _project,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Progetto'),
              items: _projects
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.description, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _selectProject,
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProjectTask>(
            key: ValueKey(_project?.id),
            initialValue: _task,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'WBS',
              errorText: _project != null && tasks.isEmpty ? 'Nessuna WBS registrabile su questo progetto' : null,
            ),
            items: tasks
                .map((t) => DropdownMenuItem(
                    value: t, child: Text('${t.id} · ${t.description}', overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (t) => setState(() => _task = t),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Giorno'),
              child: Text(DateFormat('EEEE dd.MM.yyyy', 'it_IT').format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workDoneController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descrizione intervento'),
          ),
          const SizedBox(height: 16),
          _sectionHeader('Materiale', _addMaterial),
          for (var i = 0; i < _materials.length; i++)
            _removableRow(MaterialSheet.label(_materials[i]), () => setState(() => _materials.removeAt(i))),
          const SizedBox(height: 8),
          _sectionHeader('Manodopera${_labor.isEmpty ? '' : ' · totale ${_formatHours(laborTotal)} h'}', _addLabor),
          for (var i = 0; i < _labor.length; i++)
            _removableRow('${_labor[i]['workerName']} · ${_formatHours(_labor[i]['hours'] as double)} h',
                () => setState(() => _labor.removeAt(i))),
          const SizedBox(height: 16),
          const Text('Foto (facoltative)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photoPaths.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_photoPaths[i]), width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () => setState(() => _photoPaths.removeAt(i)),
                        child: const Icon(Icons.cancel, size: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                onPressed: () => _addPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Scatta'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galleria'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _clientNameController,
            decoration: const InputDecoration(labelText: 'Nome di chi firma'),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _sign,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: _signature == null
                  ? const Center(
                      child: Text('Tocca per far firmare il cliente', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : Image.memory(_signature!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _send,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Firma e invia bollettino'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatHours(double h) => h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(2);

/// Riga di manodopera: nome scritto a mano e ore. Solo documenta il
/// bollettino: le ore vere ognuno le registra in Ore progetti.
class _LaborSheet extends StatefulWidget {
  const _LaborSheet();

  @override
  State<_LaborSheet> createState() => _LaborSheetState();
}

class _LaborSheetState extends State<_LaborSheet> {
  final _nameController = TextEditingController();
  final _hoursController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final hours = double.tryParse(_hoursController.text.replaceAll(',', '.'));
    if (name.isEmpty) return setState(() => _error = 'Scrivi il nome dell\'operaio.');
    if (hours == null || hours <= 0 || hours > 24) return setState(() => _error = 'Inserisci le ore (es. 4 o 7,5).');
    Navigator.of(context).pop(<String, dynamic>{
      'workerName': name.length > 100 ? name.substring(0, 100) : name,
      'hours': hours,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Manodopera', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: true,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Operaio (nome e cognome)', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Ore'),
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
            ),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('Aggiungi'))),
        ],
      ),
    );
  }
}
