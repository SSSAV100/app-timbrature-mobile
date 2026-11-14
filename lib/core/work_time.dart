import 'package:flutter/material.dart';

/// Orari Dalle-Alle delle righe ore (richiesta della commissione
/// paritetica, 14.11.2026). Le ore si ricavano dagli orari, arrotondate al
/// centesimo come in BC (SS Work Time Mgt), così ore lavorate e fatturabili
/// coincidono. Mattino/pomeriggio li calcola BC (separazione alle 12:00).
class WorkTime {
  WorkTime._();

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Ore tra [start] e [end], al centesimo; null se [end] non è dopo [start].
  static double? hoursBetween(TimeOfDay? start, TimeOfDay? end) {
    if (start == null || end == null) return null;
    final minutes = _minutes(end) - _minutes(start);
    if (minutes <= 0) return null;
    return (minutes / 60 * 100).round() / 100;
  }

  /// "07:30" (per DB locale e testi).
  static String format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// "07:30:00" (formato Time di BC per le API).
  static String toBc(TimeOfDay t) => '${format(t)}:00';

  static TimeOfDay? parse(String? hhmm) {
    if (hhmm == null || hhmm.length < 4) return null;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// True se i due intervalli si sovrappongono (toccarsi agli estremi, es.
  /// 07:00-12:00 e 12:00-13:00, va bene).
  static bool overlaps(TimeOfDay aStart, TimeOfDay aEnd, TimeOfDay bStart, TimeOfDay bEnd) =>
      _minutes(aStart) < _minutes(bEnd) && _minutes(bStart) < _minutes(aEnd);
}

/// Due campi "Dalle" / "Alle" con selettore orario a 24 ore e il totale ore.
class TimeRangeFields extends StatelessWidget {
  final TimeOfDay? start;
  final TimeOfDay? end;
  final ValueChanged<TimeOfDay> onStartChanged;
  final ValueChanged<TimeOfDay> onEndChanged;

  const TimeRangeFields({
    super.key,
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  Future<void> _pick(BuildContext context, TimeOfDay? initial, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hours = WorkTime.hoursBetween(start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _pick(context, start, onStartChanged),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Dalle'),
                  child: Text(start == null ? '--:--' : WorkTime.format(start!)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => _pick(context, end ?? start, onEndChanged),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Alle'),
                  child: Text(end == null ? '--:--' : WorkTime.format(end!)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          start == null || end == null
              ? 'Indica l\'orario di inizio e di fine.'
              : hours == null
                  ? 'L\'orario di fine deve essere dopo quello di inizio.'
                  : 'Totale: ${hours.toStringAsFixed(2)} h',
          style: TextStyle(fontSize: 12, color: hours == null && start != null && end != null ? Colors.red : null),
        ),
      ],
    );
  }
}
