import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/service_action.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import 'theme.dart';
import 'work_time.dart';

/// Giornata divisa in mattino, pausa pranzo e pomeriggio (richiesta del
/// cliente, 26.11.2026), per le ore di progetto e per quelle Service.
/// Ogni riga ore sceglie mattino o pomeriggio con il suo Dalle-Alle; la pausa
/// pranzo si inserisce una volta al giorno. I limiti vengono dalla Setup App
/// Timbrature (campo dayRules di `me`); BC rifà gli stessi controlli.
enum DayPart {
  mattino('Mattino'),
  pomeriggio('Pomeriggio');

  final String label;
  const DayPart(this.label);

  static DayPart? fromName(String? name) => switch (name) {
        'mattino' => DayPart.mattino,
        'pomeriggio' => DayPart.pomeriggio,
        _ => null,
      };
}

/// Limiti della giornata. Valori predefiniti = quelli di BC con la Setup vuota.
class DayRules {
  final TimeOfDay morningLatestEnd;
  final double morningMaxHours;
  final TimeOfDay lunchEarliestStart;
  final TimeOfDay lunchLatestEnd;
  final double lunchMinHours;
  final TimeOfDay afternoonEarliestStart;
  final TimeOfDay afternoonLatestEnd;
  final double afternoonMaxHours;

  const DayRules({
    this.morningLatestEnd = const TimeOfDay(hour: 12, minute: 30),
    this.morningMaxHours = 5.5,
    this.lunchEarliestStart = const TimeOfDay(hour: 12, minute: 0),
    this.lunchLatestEnd = const TimeOfDay(hour: 14, minute: 0),
    this.lunchMinHours = 1,
    this.afternoonEarliestStart = const TimeOfDay(hour: 13, minute: 0),
    this.afternoonLatestEnd = const TimeOfDay(hour: 23, minute: 59),
    this.afternoonMaxHours = 5.5,
  });

  /// Regole in uso: aggiornate dalla home quando legge `me`.
  static DayRules current = const DayRules();

  /// "12:30|5.5|12:00|14:00|1|13:00|23:59|5.5" (SS Work Time Mgt.DayRulesText).
  static DayRules? parse(String? raw) {
    final parts = raw?.split('|') ?? const [];
    if (parts.length != 8) return null;
    final times = [parts[0], parts[2], parts[3], parts[5], parts[6]].map(WorkTime.parse).toList();
    final numbers = [parts[1], parts[4], parts[7]].map(double.tryParse).toList();
    if (times.contains(null) || numbers.contains(null)) return null;
    return DayRules(
      morningLatestEnd: times[0]!,
      morningMaxHours: numbers[0]!,
      lunchEarliestStart: times[1]!,
      lunchLatestEnd: times[2]!,
      lunchMinHours: numbers[1]!,
      afternoonEarliestStart: times[3]!,
      afternoonLatestEnd: times[4]!,
      afternoonMaxHours: numbers[2]!,
    );
  }

  /// Parte proposta per una nuova riga: mattino fino alla fine del mattino.
  DayPart suggestedPart(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (!isToday) return DayPart.mattino;
    return _m(TimeOfDay.fromDateTime(now)) < _m(morningLatestEnd) ? DayPart.mattino : DayPart.pomeriggio;
  }
}

int _m(TimeOfDay t) => t.hour * 60 + t.minute;
String _f(TimeOfDay t) => WorkTime.format(t);
String _h(double hours) => hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toString().replaceAll('.', ',');

/// Un intervallo già presente nella giornata (riga ore, ore Service, pausa).
class DaySlot {
  final DayPart? part; // null = pausa pranzo
  final TimeOfDay start;
  final TimeOfDay end;
  final String source;

  const DaySlot(this.part, this.start, this.end, this.source);

  bool get isLunch => part == null;
  double get hours => WorkTime.hoursBetween(start, end) ?? 0;
}

/// Giornata del dipendente come la vede il telefono: righe ore di progetto,
/// ore Service e pausa pranzo inserite da qui (inviate o in coda).
class DayPlan {
  final List<DaySlot> slots;
  const DayPlan(this.slots);

  DaySlot? get lunch => slots.where((s) => s.isLunch).lastOrNull;

  static String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static DayPart _partOf(String? name, TimeOfDay end) =>
      DayPart.fromName(name) ??
      (_m(end) <= _m(DayRules.current.morningLatestEnd) ? DayPart.mattino : DayPart.pomeriggio);

  static Future<DayPlan> load(DateTime date) async {
    final slots = <DaySlot>[];
    for (final e in await LocalDbService.instance.getTimeEntriesForDate(date)) {
      final s = WorkTime.parse(e.startTime);
      final t = WorkTime.parse(e.endTime);
      if (s != null && t != null) slots.add(DaySlot(_partOf(e.dayPart, t), s, t, 'progetti'));
    }
    DaySlot? lunch;
    for (final a in await LocalDbService.instance.getServiceActionsOfKinds(
        [ServiceActionKind.hours, ServiceActionKind.lunchBreak], _day(date))) {
      final s = WorkTime.parse(a.payload['startTime'] as String?);
      final t = WorkTime.parse(a.payload['endTime'] as String?);
      if (s == null || t == null) continue;
      if (a.kind == ServiceActionKind.lunchBreak) {
        lunch = DaySlot(null, s, t, 'pausa'); // l'ultima sostituisce le precedenti, come in BC
      } else {
        slots.add(DaySlot(_partOf(a.payload['dayPart'] as String?, t), s, t, 'Service ${a.orderNo}'));
      }
    }
    if (lunch != null) slots.add(lunch);
    return DayPlan(slots);
  }

  /// Controlla una nuova riga ore; null se va bene, altrimenti il motivo.
  /// [lunchMissing] diventa true quando manca solo la pausa pranzo.
  String? check(DayPart part, TimeOfDay start, TimeOfDay end, {void Function()? onLunchMissing}) {
    final r = DayRules.current;
    if (_m(end) <= _m(start)) return 'L\'orario Alle deve essere dopo Dalle.';
    if (part == DayPart.mattino && _m(end) > _m(r.morningLatestEnd)) {
      return 'Le ore del mattino devono finire entro le ${_f(r.morningLatestEnd)}.';
    }
    if (part == DayPart.pomeriggio) {
      if (_m(start) < _m(r.afternoonEarliestStart)) {
        return 'Le ore del pomeriggio non possono iniziare prima delle ${_f(r.afternoonEarliestStart)}.';
      }
      if (_m(end) > _m(r.afternoonLatestEnd)) {
        return 'Le ore del pomeriggio devono finire entro le ${_f(r.afternoonLatestEnd)}.';
      }
    }
    for (final s in slots) {
      if (WorkTime.overlaps(start, end, s.start, s.end)) {
        return 'Si sovrappone a ${_f(s.start)}–${_f(s.end)} (${s.isLunch ? 'pausa pranzo' : s.source}).';
      }
    }
    final newHours = WorkTime.hoursBetween(start, end) ?? 0;
    final partHours = slots.where((s) => s.part == part).fold(newHours, (sum, s) => sum + s.hours);
    final max = part == DayPart.mattino ? r.morningMaxHours : r.afternoonMaxHours;
    if (partHours > max + 0.001) {
      return 'Il ${part.label.toLowerCase()} supera il massimo di ${_h(max)} ore (con questa riga: ${_h(partHours)} h).';
    }
    final other = part == DayPart.mattino ? DayPart.pomeriggio : DayPart.mattino;
    if (lunch == null && slots.any((s) => s.part == other)) {
      onLunchMissing?.call();
      return 'Con ore sia di mattino sia di pomeriggio serve prima la pausa pranzo.';
    }
    return null;
  }

  /// Controlla la pausa pranzo; null se va bene.
  String? checkLunch(TimeOfDay start, TimeOfDay end) {
    final r = DayRules.current;
    if (_m(end) <= _m(start)) return 'L\'orario Alle deve essere dopo Dalle.';
    if (_m(start) < _m(r.lunchEarliestStart) || _m(end) > _m(r.lunchLatestEnd)) {
      return 'La pausa pranzo deve stare tra le ${_f(r.lunchEarliestStart)} e le ${_f(r.lunchLatestEnd)}.';
    }
    if ((WorkTime.hoursBetween(start, end) ?? 0) + 0.001 < r.lunchMinHours) {
      return 'La pausa pranzo deve durare almeno ${_h(r.lunchMinHours)} ore.';
    }
    for (final s in slots.where((s) => !s.isLunch)) {
      if (WorkTime.overlaps(start, end, s.start, s.end)) {
        return 'La pausa si sovrappone alle ore ${_f(s.start)}–${_f(s.end)}.';
      }
    }
    return null;
  }
}

/// Scelta Mattino / Pomeriggio per le righe ore.
class DayPartSelector extends StatelessWidget {
  final DayPart value;
  final ValueChanged<DayPart> onChanged;

  const DayPartSelector({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final r = DayRules.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<DayPart>(
            segments: const [
              ButtonSegment(value: DayPart.mattino, label: Text('Mattino'), icon: Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: DayPart.pomeriggio, label: Text('Pomeriggio'), icon: Icon(Icons.wb_twilight)),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value == DayPart.mattino
              ? 'Fino alle ${_f(r.morningLatestEnd)}, massimo ${_h(r.morningMaxHours)} h nella giornata'
              : 'Dalle ${_f(r.afternoonEarliestStart)} alle ${_f(r.afternoonLatestEnd)}, massimo ${_h(r.afternoonMaxHours)} h nella giornata',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Pannello della pausa pranzo del giorno. Mette in coda la pausa verso BC
/// (lunchBreaks) e restituisce true se salvata.
class LunchBreakSheet extends StatefulWidget {
  final DateTime date;
  const LunchBreakSheet({super.key, required this.date});

  /// Apre il pannello; true se la pausa è stata salvata.
  static Future<bool> open(BuildContext context, DateTime date) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => LunchBreakSheet(date: date),
    );
    return saved == true;
  }

  @override
  State<LunchBreakSheet> createState() => _LunchBreakSheetState();
}

class _LunchBreakSheetState extends State<LunchBreakSheet> {
  TimeOfDay? _start;
  TimeOfDay? _end;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    DayPlan.load(widget.date).then((plan) {
      final lunch = plan.lunch;
      if (mounted && lunch != null) {
        setState(() {
          _start = lunch.start;
          _end = lunch.end;
        });
      }
    });
  }

  Future<void> _save() async {
    if (_start == null || _end == null) {
      setState(() => _error = 'Indica l\'orario Dalle e Alle della pausa.');
      return;
    }
    final plan = await DayPlan.load(widget.date);
    final error = plan.checkLunch(_start!, _end!);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    await LocalDbService.instance.saveServiceAction(ServiceAction(
      localId: const Uuid().v4(),
      createdAt: DateTime.now(),
      kind: ServiceActionKind.lunchBreak,
      orderNo: '',
      itemLineNo: 0,
      payload: {
        'date': DateFormat('yyyy-MM-dd').format(widget.date),
        'startTime': WorkTime.toBc(_start!),
        'endTime': WorkTime.toBc(_end!),
      },
    ));
    SyncService.instance.syncAll();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final r = DayRules.current;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pausa pranzo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('EEEE d MMMM', 'it_IT').format(widget.date)} · tra le ${_f(r.lunchEarliestStart)} e le '
            '${_f(r.lunchLatestEnd)}, almeno ${_h(r.lunchMinHours)} h',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TimeRangeFields(
            start: _start,
            end: _end,
            onStartChanged: (t) => setState(() => _start = t),
            onEndChanged: (t) => setState(() => _end = t),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Salva pausa')),
          ),
        ],
      ),
    );
  }
}
