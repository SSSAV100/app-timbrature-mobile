import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/local_files.dart';
import '../core/service_report_pdf.dart';
import '../core/theme.dart';
import '../models/service_action.dart';
import '../models/service_assignment.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import 'signature_pad_screen.dart';

/// Chiusura di un intervento: lavoro svolto, foto, nome e firma del cliente.
/// Genera il rapporto PDF (condiviso subito col cliente) e mette in coda,
/// in quest'ordine: firma, foto e PDF come allegati dell'ordine, poi
/// l'evento "finish" con la nota (Work Description in BC, trasferta della
/// zona aggiunta da BC). Restituisce true se l'intervento è stato chiuso.
class ServiceFinishScreen extends StatefulWidget {
  final ServiceAssignment assignment;
  final List<ServiceAction> actions;

  const ServiceFinishScreen({super.key, required this.assignment, required this.actions});

  @override
  State<ServiceFinishScreen> createState() => _ServiceFinishScreenState();
}

class _ServiceFinishScreenState extends State<ServiceFinishScreen> {
  static const _uuid = Uuid();
  final _workDoneController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<String> _photoPaths = [];
  Uint8List? _signature;
  bool _isSaving = false;

  // Ore proposte: tempo da "Inizia" a ora, arrotondato al quarto d'ora.
  final _hoursServiceController = TextEditingController();
  final _hoursSalaryController = TextEditingController();
  bool _registerHours = true;
  List<WorkType> _workTypes = [];
  WorkType? _workType;
  DateTime? _startedAt;
  double _alreadyEnteredHours = 0;

  ServiceAssignment get _a => widget.assignment;

  @override
  void initState() {
    super.initState();
    _clientNameController.text = _a.contactName;

    // Inizio: l'ultimo "Inizia" fatto dall'app, altrimenti quello registrato
    // da BC (es. iniziato da un altro telefono o dall'ufficio).
    final localStart = widget.actions
        .where((a) => a.kind == ServiceActionKind.event && a.payload['eventType'] == 'start')
        .firstOrNull;
    _startedAt = localStart?.createdAt ?? _a.startedAt;
    _alreadyEnteredHours = widget.actions
        .where((a) => a.kind == ServiceActionKind.hours)
        .fold(0.0, (sum, a) => sum + ((a.payload['hoursService'] as num?)?.toDouble() ?? 0));

    // Ore già inserite a mano: nessuna proposta (si possono aggiungere).
    _registerHours = _alreadyEnteredHours == 0;
    final proposed = _proposedHours();
    if (proposed != null) {
      final text = _format(proposed);
      _hoursServiceController.text = text;
      _hoursSalaryController.text = text;
    }

    BcApiService.instance.fetchWorkTypes().then((types) {
      if (!mounted) return;
      setState(() {
        _workTypes = types;
        _workType = types.isNotEmpty ? types.first : null;
      });
    }).catchError((Object _) {
      // Senza tipi lavoro (offline, mai letti) si chiude senza ore proposte.
      if (mounted) setState(() => _registerHours = false);
    });
  }

  double? _proposedHours() {
    if (_startedAt == null) return null;
    final minutes = DateTime.now().difference(_startedAt!).inMinutes;
    if (minutes <= 0) return null;
    final quarters = (minutes / 15).round();
    return (quarters < 1 ? 1 : quarters) / 4;
  }

  String _format(double hours) => hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toString();

  double? _parse(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : double.tryParse(c.text.replaceAll(',', '.'));

  @override
  void dispose() {
    _workDoneController.dispose();
    _clientNameController.dispose();
    _hoursServiceController.dispose();
    _hoursSalaryController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80, maxWidth: 1920);
    if (picked == null) return;
    final path = await LocalFiles.copyToPermanentStorage(picked.path, 'foto_${_a.orderNo}_${_uuid.v4()}.jpg');
    setState(() => _photoPaths.add(path));
  }

  Future<void> _sign() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignaturePadScreen(title: 'Firma del cliente')),
    );
    if (bytes != null) setState(() => _signature = bytes);
  }

  // Orari strettamente crescenti: la coda si invia in ordine di creazione,
  // e la chiusura deve partire per ultima.
  DateTime _queueTime = DateTime.now();

  Future<void> _queue(ServiceActionKind kind, Map<String, dynamic> payload, {String? filePath}) {
    final now = DateTime.now();
    _queueTime = now.isAfter(_queueTime) ? now : _queueTime.add(const Duration(milliseconds: 1));
    return LocalDbService.instance.saveServiceAction(ServiceAction(
      localId: _uuid.v4(),
      createdAt: _queueTime,
      kind: kind,
      orderNo: _a.orderNo,
      itemLineNo: _a.itemLineNo,
      payload: {'orderNo': _a.orderNo, 'itemLineNo': _a.itemLineNo, ...payload},
      filePath: filePath,
    ));
  }

  Future<void> _finish() async {
    final workDone = _workDoneController.text.trim();
    final clientName = _clientNameController.text.trim();
    if (workDone.isEmpty) {
      _snack('Descrivi il lavoro svolto.');
      return;
    }
    if (_signature == null) {
      _snack('Serve la firma del cliente.');
      return;
    }
    final hoursService = _parse(_hoursServiceController);
    final hoursSalary = _parse(_hoursSalaryController);
    if (_registerHours) {
      if (_workType == null) {
        _snack('Scegli il tipo lavoro delle ore.');
        return;
      }
      if (hoursService == null || hoursSalary == null || hoursService < 0 || hoursSalary < 0 ||
          (hoursService == 0 && hoursSalary == 0)) {
        _snack('Controlla le ore Service e stipendio.');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;

      // Ore prima di tutto il resto: in coda vanno inviate prima della chiusura.
      final pdfActions = [...widget.actions];
      if (_registerHours) {
        final hoursPayload = <String, dynamic>{
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'workTypeCode': _workType!.code,
          'hoursService': hoursService,
          'hoursSalary': hoursSalary,
        };
        await _queue(ServiceActionKind.hours, hoursPayload);
        pdfActions.add(ServiceAction(
          localId: '',
          createdAt: DateTime.now(),
          kind: ServiceActionKind.hours,
          orderNo: _a.orderNo,
          itemLineNo: _a.itemLineNo,
          payload: hoursPayload,
        ));
      }

      final signaturePath = await LocalFiles.saveBytes(_signature!, 'firma_${_a.orderNo}_$stamp.png');
      final pdf = await ServiceReportPdf.generate(
        assignment: _a,
        actions: pdfActions,
        workDone: workDone,
        clientName: clientName,
        signaturePng: _signature!,
      );

      await _queue(ServiceActionKind.attachment, {'fileName': 'firma_cliente_$stamp.png'}, filePath: signaturePath);
      for (var i = 0; i < _photoPaths.length; i++) {
        await _queue(ServiceActionKind.attachment, {'fileName': 'foto_${i + 1}_$stamp.jpg'}, filePath: _photoPaths[i]);
      }
      await _queue(ServiceActionKind.attachment, {'fileName': 'rapporto_${_a.orderNo}_$stamp.pdf'}, filePath: pdf.path);
      await _queue(ServiceActionKind.event, {
        'eventType': 'finish',
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
        'note': clientName.isEmpty ? workDone : '$workDone (firmato da $clientName)',
      });

      // Il rapporto al cliente subito (email, WhatsApp…), anche offline.
      await SharePlus.instance.share(ShareParams(files: [XFile(pdf.path)], subject: 'Rapporto di intervento ${_a.orderNo}'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Errore nella chiusura: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _buildHoursSection() {
    final timeFormat = DateFormat('HH:mm');
    final hint = _startedAt == null
        ? 'Intervento senza ora di inizio: inserisci le ore.'
        : 'Iniziato alle ${timeFormat.format(_startedAt!)}: ore proposte fino ad ora, modificabili.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Registra le ore dell\'intervento'),
            subtitle: Text(
              _alreadyEnteredHours > 0 ? 'Già inserite: ${_format(_alreadyEnteredHours)} h Service' : hint,
              style: const TextStyle(fontSize: 12),
            ),
            value: _registerHours,
            onChanged: (v) => setState(() => _registerHours = v),
          ),
          if (_registerHours) ...[
            DropdownButtonFormField<WorkType>(
              initialValue: _workType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo lavoro'),
              items: _workTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text('${t.code} · ${t.description}')))
                  .toList(),
              onChanged: (t) => setState(() => _workType = t),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hoursServiceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ore Service'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hoursSalaryController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ore stipendio'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termina intervento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(_a.customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text(_a.orderNo, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: _workDoneController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Lavoro svolto'),
          ),
          const SizedBox(height: 16),
          _buildHoursSection(),
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
              onPressed: _isSaving ? null : _finish,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Termina e invia rapporto'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}
