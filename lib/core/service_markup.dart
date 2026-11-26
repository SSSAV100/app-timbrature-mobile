import '../models/app_user.dart';

/// Maggiorazione automatica delle ore Service da fatturare (richiesta del
/// cliente, 26.11.2026): +10% fino a 1 ora compresa, +5% oltre, al centesimo.
/// La applica BC alla registrazione (SS Service Mgt.WithMarkup); qui serve
/// solo per mostrarla al tecnico. Percentuali dalla Setup (`me.serviceMarkup`).
class ServiceMarkup {
  ServiceMarkup._();

  static (double, double) get _percents {
    final parts = (AppUser.current?.serviceMarkup ?? '').split('|');
    final short = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
    final long = parts.length > 1 ? double.tryParse(parts[1]) : null;
    return (short ?? 10, long ?? 5);
  }

  static double percentFor(double hours) => hours <= 1 ? _percents.$1 : _percents.$2;

  static double apply(double hours) {
    if (hours <= 0) return hours;
    return (hours * (1 + percentFor(hours) / 100) * 100).round() / 100;
  }

  /// "0,75 h + 10% = 0,83 h da fatturare"
  static String describe(double hours) {
    String f(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    final pct = percentFor(hours);
    return '${f(hours)} h + ${pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct}% = ${f(apply(hours))} h da fatturare';
  }
}
