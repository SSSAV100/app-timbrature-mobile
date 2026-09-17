import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/local_files.dart';
import '../core/theme.dart';
import '../models/assenza_request.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';

class AssenzaFormScreen extends StatefulWidget {
  const AssenzaFormScreen({super.key});

  @override
  State<AssenzaFormScreen> createState() => _AssenzaFormScreenState();
}

class _AssenzaFormScreenState extends State<AssenzaFormScreen> {
  final _uuid = const Uuid();
  final _hoursController = TextEditingController(text: '8');
  final _noteController = TextEditingController();
  final _incidentDescriptionController = TextEditingController();
  final _incidentLocationController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  AssenzaType _type = AssenzaType.ferie;
  DateTimeRange _dateRange = DateTimeRange(start: DateTime.now(), end: DateTime.now());
  String? _attachmentPath;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _hoursController.dispose();
    _noteController.dispose();
    _incidentDescriptionController.dispose();
    _incidentLocationController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
  }

  Future<void> _pickAttachment() async {
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
              title: const Text('Fotografa il documento'),
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
    setState(() => _attachmentPath = permanentPath);
  }

  bool get _requiresAttachment => _type == AssenzaType.malattia || _type == AssenzaType.infortunio;

  Future<void> _submit() async {
    final hours = double.tryParse(_hoursController.text.replaceAll(',', '.'));
    if (hours == null || hours <= 0) {
      _showError('Inserisci un numero di ore valido.');
      return;
    }
    if (_requiresAttachment && _attachmentPath == null) {
      _showError(
        _type == AssenzaType.malattia
            ? 'Allega il certificato medico prima di inviare.'
            : 'Allega il referto/dichiarazione prima di inviare.',
      );
      return;
    }
    if (_type == AssenzaType.infortunio && _incidentDescriptionController.text.trim().isEmpty) {
      _showError('Descrivi brevemente l\'accaduto.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final assenza = AssenzaRequest(
        localId: _uuid.v4(),
        type: _type,
        startDate: _dateRange.start,
        endDate: _dateRange.end,
        hoursPerDay: hours,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        incidentDescription: _type == AssenzaType.infortunio
            ? _incidentDescriptionController.text.trim()
            : null,
        incidentLocation: _type == AssenzaType.infortunio && _incidentLocationController.text.trim().isNotEmpty
            ? _incidentLocationController.text.trim()
            : null,
        attachmentPath: _attachmentPath,
      );

      await LocalDbService.instance.saveAssenza(assenza);
      SyncService.instance.syncAll();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Nuova richiesta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          SegmentedButton<AssenzaType>(
            segments: const [
              ButtonSegment(value: AssenzaType.ferie, label: Text('Ferie')),
              ButtonSegment(value: AssenzaType.malattia, label: Text('Malattia')),
              ButtonSegment(value: AssenzaType.infortunio, label: Text('Infortunio')),
            ],
            selected: {_type},
            onSelectionChanged: (selection) => setState(() => _type = selection.first),
          ),
          const SizedBox(height: 20),

          InkWell(
            onTap: _pickDateRange,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Periodo'),
              child: Text(
                '${dateFormat.format(_dateRange.start)} - ${dateFormat.format(_dateRange.end)}',
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Ore per giorno',
              helperText: '8 per giornata intera, 4 per mezza giornata, ecc.',
            ),
          ),
          const SizedBox(height: 12),

          if (_type == AssenzaType.infortunio) ...[
            TextField(
              controller: _incidentDescriptionController,
              decoration: const InputDecoration(labelText: 'Descrizione dell\'accaduto'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _incidentLocationController,
              decoration: const InputDecoration(labelText: 'Luogo/cantiere (opzionale)'),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Nota (opzionale)'),
            maxLines: 2,
          ),

          if (_requiresAttachment) ...[
            const SizedBox(height: 20),
            Text(
              _type == AssenzaType.malattia
                  ? 'Certificato medico (obbligatorio)'
                  : 'Referto/dichiarazione per l\'assicuratore (obbligatorio)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickAttachment,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: _attachmentPath == null
                    ? const Center(
                        child: Text('Tocca per allegare', style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(_attachmentPath!), height: 96, fit: BoxFit.cover),
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
          ],

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
                  : const Text('Invia richiesta'),
            ),
          ),
        ],
      ),
    );
  }
}
