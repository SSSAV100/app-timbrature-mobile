import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carica la configurazione del cliente (assets/client_config.json) e
  // applica il suo colore aziendale alla palette, PRIMA di costruire
  // qualunque widget. Vedi core/config.dart per i dettagli.
  final config = await AppConfig.load();
  AppColors.applyBrandColor(config.primaryColorHex);

  // Necessario perché ore_progetti_screen.dart formatta le date in
  // italiano (es. "lunedì 17 settembre"); senza questa riga, DateFormat
  // con locale 'it_IT' lancia un'eccezione a runtime.
  await initializeDateFormatting('it_IT');

  runApp(const TimbratureApp());
}
