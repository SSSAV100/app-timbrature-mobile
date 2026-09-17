import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/bollettino_pdf.dart';
import '../core/local_files.dart';
import '../core/theme.dart';
import '../models/bollettino.dart';
import '../models/bollettino_material.dart';
import '../models/project.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import 'signature_pad_screen.dart';

class BollettinoScreen extends StatefulWidget {
  const BollettinoScreen({super.key});

  @override
  State<BollettinoScreen> createState() => _BollettinoScreenState();
}

class _MaterialRow {
  final TextEditingController description = TextEditingController();
  final TextEditingController quantity = TextEditingController(text: '1');
}

class _BollettinoScreenState extends State<BollettinoScreen> {
  final _uuid = const Uuid();
  final _clientContactController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Project> _serviceProjects = [];
  Project? _selectedProject;
  bool _isLoadingProjects = true;
  String? _loadError;

  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now();
  final List<_MaterialRow> _materials = [];
  final List<String> _photoPaths = [];
  Uint8List? _clientSignatureBytes;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadServiceProjects();
  }

  @override
  void dispose() {
    _clientContactController.dispose();
    _descriptionController.dispose();
    for (final m in _materials) {
      m.description.dispose();
      m.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _loadServiceProjects() async {
    setState(() {
      _isLoadingProjects = true;
      _loadError = null;
    });
    try {
      final projects = await BcApiService.instance.fetchAssignedProjects();
      final serviceOnly = projects.where((p) => p.type == ProjectType.service).toList();
      setState(() {
        _serviceProjects = serviceOnly;
        _selectedProject = serviceOnly.isNotEmpty ? serviceOnly.first : null;
      });
    } catch (_) {
      setState(() {
        _loadError = 'Impossibile aggiornare l\'elenco progetti (verifica la connessione).';
      });
    } finally {
      setState(() => _isLoadingProjects = false);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  void _addMaterialRow() {
    setState(() => _materials.add(_MaterialRow()));
  }

  void _removeMaterialRow(int index) {
    setState(() {
      _materials[index].description.dispose();
      _materials[index].quantity.dispose();
      _materials.removeAt(index);
    });
  }

  Future<void> _addPhoto() async {
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
              title: const Text('Scatta una foto'),
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

    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final permanentPath = await LocalFiles.copyToPermanentStorage(
      picked.path,
      '${_uuid.v4()}.jpg',
    );
    setState(() => _photoPaths.add(permanentPath));
  }

  void _removePhoto(int index) {
    setState(() => _photoPaths.removeAt(index));
  }

  Future<void> _captureSignature() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => const SignaturePadScreen(title: 'Firma del cliente'),
      ),
    );
    if (bytes == null) return;
    setState(() => _clientSignatureBytes = bytes);
  }

  DateTime _combineWithToday(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  Future<void> _submit() async {
    if (_selectedProject == null) {
      _showError('Seleziona un progetto Service.');
      return;
    }
    if (_clientContactController.text.trim().isEmpty) {
      _showError('Inserisci il nome del referente cliente.');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showError('Inserisci una descrizione dell\'intervento.');
      return;
    }
    if (_clientSignatureBytes == null) {
      _showError('Serve la firma del cliente prima di inviare il bollettino.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final signaturePath = await LocalFiles.saveBytes(
        _clientSignatureBytes!,
        'firma_${_uuid.v4()}.png',
      );

      final materials = _materials
          .where((m) => m.description.text.trim().isNotEmpty)
          .map((m) => BollettinoMaterial(
                description: m.description.text.trim(),
                quantity: double.tryParse(m.quantity.text.replaceAll(',', '.')) ?? 1,
              ))
          .toList();

      final bollettino = Bollettino(
        localId: _uuid.v4(),
        projectId: _selectedProject!.id,
        clientContactName: _clientContactController.text.trim(),
        startTime: _combineWithToday(_startTime),
        endTime: _combineWithToday(_endTime),
        description: _descriptionController.text.trim(),
        materials: materials,
        photoPaths: List.of(_photoPaths),
        clientSignaturePath: signaturePath,
      );

      await LocalDbService.instance.saveBollettino(bollettino);

      final pdfFile = await BollettinoPdfGenerator.generate(
        bollettino: bollettino,
        project: _selectedProject!,
      );

      SyncService.instance.syncAll();

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(pdfFile.path)],
          subject: 'Bollettino di intervento - ${_selectedProject!.description}',
          text: 'In allegato il bollettino di intervento firmato.',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bollettino salvato e inviato in sincronizzazione.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      _showError('Errore durante il salvataggio del bollettino: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bollettino di intervento')),
      body: _isLoadingProjects
          ? const Center(child: CircularProgressIndicator())
          : _serviceProjects.isEmpty
              ? _buildEmptyState()
              : _buildForm(),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          _loadError ?? 'Nessun progetto di tipo Service assegnato al momento.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        DropdownButtonFormField<Project>(
          initialValue: _selectedProject,
          decoration: const InputDecoration(labelText: 'Progetto Service'),
          items: _serviceProjects
              .map((p) => DropdownMenuItem(value: p, child: Text(p.description)))
              .toList(),
          onChanged: (p) => setState(() => _selectedProject = p),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientContactController,
          decoration: const InputDecoration(labelText: 'Referente cliente presente sul posto'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TimeField(label: 'Inizio', time: _startTime, onTap: () => _pickTime(isStart: true)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeField(label: 'Fine', time: _endTime, onTap: () => _pickTime(isStart: false)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Descrizione intervento'),
          maxLines: 4,
        ),
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Materiali utilizzati', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            TextButton.icon(
              onPressed: _addMaterialRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Aggiungi'),
            ),
          ],
        ),
        ..._materials.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.description,
                    decoration: const InputDecoration(labelText: 'Materiale'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qtà'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _removeMaterialRow(index),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 20),
        const Text('Foto', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._photoPaths.asMap().entries.map((entry) {
                final index = entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(entry.value),
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removePhoto(index),
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _addPhoto,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Firma cliente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _captureSignature,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _clientSignatureBytes == null
                ? const Center(
                    child: Text('Tocca per far firmare il cliente', style: TextStyle(color: AppColors.textSecondary)),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.memory(_clientSignatureBytes!, height: 90),
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(Icons.check_circle, color: AppColors.success, size: 20),
                      ),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Genera bollettino e invia'),
          ),
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeField({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(time.format(context)),
      ),
    );
  }
}
