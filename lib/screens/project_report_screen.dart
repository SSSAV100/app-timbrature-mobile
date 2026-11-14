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
import '../models/service_action.dart';
import '../models/time_entry.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../widgets/material_sheet.dart';
import 'signature_pad_screen.dart';

/// Bollettino facoltativo delle ore di progetto (richiesta del cliente,
/// 14.11.2026): commessa e giorno, ore Dalle-Alle già inserite, lavoro
/// svolto, materiali, foto e firma del cliente. Genera il PDF (condiviso
/// subito) e mette in coda verso BC: bollettino, materiali, firma, foto e
/// PDF come allegati della commessa. Restituisce true se inviato.
class ProjectReportScreen extends StatefulWidget {
  final List<Project> projects;
  final DateTime date;

  /// Righe ore del giorno, per proporre la commessa e riportare le ore.
  final List<TimeEntry> entries;

  const ProjectReportScreen({super.key, required this.projects, required this.date, required this.entries});

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
  Project? _project;
  Uint8List? _signature;
  bool _isSaving = false;
  DateTime _queueTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Commessa proposta: quella delle ore del giorno, se ce ne sono.
    final entryProjectIds = widget.entries.map((e) => e.projectId).toSet();
    _project = widget.projects.where((p) => entryProjectIds.contains(p.id)).firstOrNull ??
        (widget.projects.isNotEmpty ? widget.projects.first : null);
  }

  @override
  void dispose() {
    _workDoneController.dispose();
    _clientNameController.dispose();
    super.dispose();
  }

  List<TimeEntry> get _projectHours =>
      widget.entries.where((e) => e.projectId == _project?.id).toList()
        ..sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));

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

  // Coda in ordine: il bollettino prima di materiali e allegati.
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

  Future<void> _send() async {
    final workDone = _workDoneController.text.trim();
    final clientName = _clientNameController.text.trim();
    if (_project == null) {
      _snack('Scegli la commessa.');
      return;
    }
    if (workDone.isEmpty) {
      _snack('Descrivi il lavoro svolto.');
      return;
    }
    if (_signature == null) {
      _snack('Serve la firma del cliente.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final reportId = _uuid.v4();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final day = DateFormat('yyyy-MM-dd').format(widget.date);
      final pdf = await ProjectReportPdf.generate(
        project: _project!,
        date: widget.date,
        hours: _projectHours,
        materials: _materials,
        workDone: workDone,
        clientName: clientName,
        signaturePng: _signature!,
      );
      final signaturePath = await LocalFiles.saveBytes(_signature!, 'firma_${_project!.id}_$stamp.png');

      await _queue(ServiceActionKind.projectReport, {
        'reportId': reportId,
        'date': day,
        'workDescription': workDone,
        'clientName': clientName,
      });
      for (final m in _materials) {
        await _queue(ServiceActionKind.projectMaterial, {'reportId': reportId, ...m});
      }
      await _queue(ServiceActionKind.projectAttachment, {'fileName': 'firma_${day}_$stamp.png'}, filePath: signaturePath);
      for (var i = 0; i < _photoPaths.length; i++) {
        await _queue(ServiceActionKind.projectAttachment, {'fileName': 'foto_${day}_${i + 1}_$stamp.jpg'},
            filePath: _photoPaths[i]);
      }
      await _queue(ServiceActionKind.projectAttachment, {'fileName': 'bollettino_${day}_$stamp.pdf'}, filePath: pdf.path);
      SyncService.instance.syncAll();

      await SharePlus.instance.share(ShareParams(files: [XFile(pdf.path)], subject: 'Bollettino ${_project!.description}'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Errore nel bollettino: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final hours = _projectHours;
    final total = hours.fold(0.0, (sum, e) => sum + e.hoursWorked);

    return Scaffold(
      appBar: AppBar(title: Text('Bollettino ${DateFormat('dd.MM.yyyy').format(widget.date)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          DropdownButtonFormField<Project>(
            initialValue: _project,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Commessa'),
            items: widget.projects
                .map((p) => DropdownMenuItem(value: p, child: Text(p.description, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (p) => setState(() => _project = p),
          ),
          const SizedBox(height: 16),
          const Text('Ore del giorno', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          if (hours.isEmpty)
            const Text('Nessuna ora inserita su questa commessa nel giorno.', style: TextStyle(fontSize: 13))
          else ...[
            for (final e in hours)
              Text('${e.startTime ?? ''}–${e.endTime ?? ''} · ${e.hoursWorked.toStringAsFixed(2)} h',
                  style: const TextStyle(fontSize: 13)),
            Text('Totale ${total.toStringAsFixed(2)} h', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _workDoneController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Lavoro svolto'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Materiale', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              TextButton.icon(onPressed: _addMaterial, icon: const Icon(Icons.add), label: const Text('Aggiungi')),
            ],
          ),
          for (var i = 0; i < _materials.length; i++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_materials[i]['quantity']} × ${_materials[i]['itemNo']} ${_materials[i]['_itemDescription'] ?? ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _materials.removeAt(i)),
                ),
              ],
            ),
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
