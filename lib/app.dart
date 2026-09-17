import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

class TimbratureApp extends StatelessWidget {
  const TimbratureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.instance.appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _StartupGate(),
    );
  }
}

/// Decide se mostrare la schermata di login o direttamente la Home,
/// in base alla presenza di una sessione già valida (token salvato in modo
/// sicuro sul dispositivo).
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService.instance.isSignedIn,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return (snapshot.data ?? false) ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
