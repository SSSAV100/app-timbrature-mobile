import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/local_files.dart';
import '../core/theme.dart';
import '../models/nota_spesa.dart';
import '../models/project.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../widgets/sync_status_dot.dart';

class NoteSpeseScreen extends StatefulWidget {
  const NoteSpeseScreen({super.key});

  @override
  State<NoteSpeseScreen> createState() => _NoteSpeseScreenState();
}

class _NoteSpeseScreenState extends State<NoteSpeseScreen> {
  List<NotaSpesa> _notes = [];
  List<Project> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        LocalDbService.instance.getAllNoteSpese(),
        BcApiService.instance.fetchAssignedProjects(),
      ]);
      setState(() {
        _notes = results[0] as List<NotaSpesa>;
        _projects = results[1] as List<Project>;
      });
    } catch (_) {
      final notes = await LocalDbService.instance.getAllNoteSpese();
      setState(() => _notes = notes);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openAddSheet() async {
    final result = await showModalBottomSheet<NotaSpesa>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddNotaSpesaSheet(projects: _projects),
    );
    if (result == null) return;

    await LocalDbService.instance.saveNotaSpesa(result);
    await _loadAll();
    SyncService.instance.syncAll();
  }

  double get _totalChf => _notes.fold(0.0, (sum, n) => sum + n.amountChf);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Note spese')),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            _buildTotalCard(),
            const SizedBox(height: 20),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nessuna nota spesa ancora inserita.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._notes.map(_buildNoteTile),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi spesa'),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Totale note spese', style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          Text('CHF ${_totalChf.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildNoteTile(NotaSpesa nota) {
    final dateFormat = DateFormat('dd.MM.yyyy');
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
          SyncStatusDot(status: nota.status),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(nota.receiptPath), width: 40, height: 40, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nota.category.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(dateFormat.format(nota.date), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text('CHF ${nota.amountChf.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Foglio modale per l'inserimento di una nuova nota spesa.
class _AddNotaSpesaSheet extends StatefulWidget {
  final List<Project> projects;
  const _AddNotaSpesaSheet({required this.projects});

  @override
  State<_AddNotaSpesaSheet> createState() => _AddNotaSpesaSheetState();
}

class _AddNotaSpesaSheetState extends State<_AddNotaSpesaSheet> {
  final _uuid = const Uuid();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  NotaSpesaCategoria _category = NotaSpesaCategoria.vitto;
  DateTime _date = DateTime.now();
  Project? _selectedProject;
  String? _receiptPath;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Fotografa la ricevuta'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final permanentPath = await LocalFiles.copyToPermanentStorage(picked.path, '${_uuid.v4()}.jpg');
    setState(() => _receiptPath = permanentPath);
  }

  void _save() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un importo valido.')),
      );
      return;
    }
    if (_receiptPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Allega la foto della ricevuta.')),
      );
      return;
    }

    final nota = NotaSpesa(
      localId: _uuid.v4(),
      date: _date,
      category: _category,
      amountChf: amount,
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      projectId: _selectedProject?.id,
      receiptPath: _receiptPath!,
    );

    Navigator.of(context).pop(nota);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuova nota spesa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Data'),
                child: Text(dateFormat.format(_date)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NotaSpesaCategoria>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: NotaSpesaCategoria.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (c) => setState(() => _category = c ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Importo (CHF)'),
            ),
            const SizedBox(height: 12),
            if (widget.projects.isNotEmpty)
              DropdownButtonFormField<Project>(
                initialValue: _selectedProject,
                decoration: const InputDecoration(labelText: 'Progetto (opzionale)'),
                items: widget.projects
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.description)))
                    .toList(),
                onChanged: (p) => setState(() => _selectedProject = p),
              ),
            if (widget.projects.isNotEmpty) const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descrizione (opzionale)'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text('Ricevuta (obbligatoria)', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickReceipt,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: _receiptPath == null
                    ? const Center(
                        child: Text('Tocca per fotografare', style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(_receiptPath!), height: 86, fit: BoxFit.cover),
                          ),
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(Icons.check_circle, color: AppColors.success, size: 20),
                          ),
                        ],
                      ),
              ),
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
      ),
    );
  }
}
