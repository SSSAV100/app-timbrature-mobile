import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/local_files.dart';
import '../core/service_report_pdf.dart';
import '../core/day_parts.dart';
import '../core/service_markup.dart';
import '../core/theme.dart';
import '../models/app_user.dart';
import '../core/work_time.dart';
import '../models/service_action.dart';
import '../models/service_assignment.dart';
import '../services/local_db_service.dart';
import '../services/location_service.dart';
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
  // Orari Dalle-Alle (commissione paritetica): Dalle = Inizia (se oggi),
  // Alle = adesso. Le ore stipendio sono la durata; le ore Service la
  // seguono finché il tecnico non le cambia.
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _serviceEdited = false;
  bool _registerHours = true;
  late DayPart _part = DayRules.current.suggestedPart(DateTime.now());
  DateTime? _startedAt;
  double _alreadyEnteredHours = 0;

  ServiceAssignment get _a => widget.assignment;

  String get _terms {
    final fromBc = AppUser.current?.serviceReportTerms ?? '';
    return fromBc.isNotEmpty
        ? fromBc
        : 'Firmando, il cliente conferma il lavoro svolto e accetta le condizioni generali e il costo della trasferta indicato.';
  }

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
    final now = DateTime.now();
    if (_startedAt != null &&
        _startedAt!.year == now.year && _startedAt!.month == now.month && _startedAt!.day == now.day) {
      _start = TimeOfDay.fromDateTime(_startedAt!);
    }
    _end = TimeOfDay.fromDateTime(now);
    _syncServiceHours();

  }

  void _syncServiceHours() {
    final hours = WorkTime.hoursBetween(_start, _end);
    if (!_serviceEdited && hours != null) _hoursServiceController.text = _format(hours);
  }

  String _format(double hours) => hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toString();

  double? _parse(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : double.tryParse(c.text.replaceAll(',', '.'));

  @override
  void dispose() {
    _workDoneController.dispose();
    _clientNameController.dispose();
    _hoursServiceController.dispose();
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
    final hoursSalary = WorkTime.hoursBetween(_start, _end);
    if (_registerHours) {
      if (hoursSalary == null) {
        _snack('Indica l\'orario Dalle e Alle (la fine dopo l\'inizio).');
        return;
      }
      if (hoursService == null || hoursService < 0) {
        _snack('Le ore Service devono essere un numero (0 se non si fatturano).');
        return;
      }
      // Mattino / pausa / pomeriggio su tutta la giornata (progetti e Service).
      final plan = await DayPlan.load(DateTime.now());
      var lunchMissing = false;
      final dayError = plan.check(_part, _start!, _end!, onLunchMissing: () => lunchMissing = true);
      if (dayError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dayError),
          duration: const Duration(seconds: 8),
          action: lunchMissing
              ? SnackBarAction(label: 'Pausa pranzo', onPressed: () => LunchBreakSheet.open(context, DateTime.now()))
              : null,
        ));
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
          'hoursService': hoursService,
          'hoursSalary': hoursSalary,
          'startTime': WorkTime.toBc(_start!),
          'endTime': WorkTime.toBc(_end!),
          'dayPart': _part.name,
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
        terms: _terms,
      );

      await _queue(ServiceActionKind.attachment, {'fileName': 'firma_cliente_$stamp.png'}, filePath: signaturePath);
      for (var i = 0; i < _photoPaths.length; i++) {
        await _queue(ServiceActionKind.attachment, {'fileName': 'foto_${i + 1}_$stamp.jpg'}, filePath: _photoPaths[i]);
      }
      await _queue(ServiceActionKind.attachment, {'fileName': 'rapporto_${_a.orderNo}_$stamp.pdf'}, filePath: pdf.path);
      // Termina: un punto GPS (mai bloccante).
      final position = await LocationService.getCurrentPositionOrNull();
      await _queue(ServiceActionKind.event, {
        if (position != null) 'latitude': position.latitude,
        if (position != null) 'longitude': position.longitude,
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
    // Ore già inserite con il pulsante "Ore": niente interruttore né campi,
    // per non far registrare le stesse ore due volte.
    if (_alreadyEnteredHours > 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Ore già inserite: ${_format(_alreadyEnteredHours)} h Service. '
          'Per aggiungerne usa il pulsante Ore prima di terminare.',
          style: const TextStyle(fontSize: 13),
        ),
      );
    }
    final timeFormat = DateFormat('HH:mm');
    final hint = _startedAt == null
        ? 'Intervento senza ora di inizio: inserisci le ore.'
        : 'Iniziato alle ${timeFormat.format(_startedAt!)}: orario proposto fino ad ora, modificabile.';
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
            DayPartSelector(value: _part, onChanged: (p) => setState(() => _part = p)),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            TextField(
              controller: _hoursServiceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _serviceEdited = true),
              decoration: const InputDecoration(
                labelText: 'Ore Service',
                helperText: 'Da fatturare al cliente',
              ),
            ),
            if ((double.tryParse(_hoursServiceController.text.replaceAll(',', '.')) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  ServiceMarkup.describe(double.parse(_hoursServiceController.text.replaceAll(',', '.'))),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
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
          // Trasferta della zona: il cliente la vede e la firma (26.11.2026).
          if (_a.travelFeeAmount > 0) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car_outlined, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _a.travelFeeDescription.isEmpty ? 'Trasferta zona ${_a.zoneCode}' : _a.travelFeeDescription,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text('CHF ${_a.travelFeeAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _clientNameController,
            decoration: const InputDecoration(labelText: 'Nome di chi firma'),
          ),
          const SizedBox(height: 12),
          // Condizioni accettate con la firma (testo dalla Setup di BC).
          Text(_terms, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
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
