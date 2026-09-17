import 'package:flutter/material.dart';

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

  runApp(const TimbratureApp());
}
