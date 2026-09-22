import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<String> _debugLines = [];

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _debugLines = [];
    });

    final success = await AuthService.instance.signIn();

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }

    setState(() {
      final detail = AuthService.instance.lastErrorMessage;
      _errorMessage = detail == null
          ? 'Accesso non riuscito. Riprova.'
          : 'Accesso non riuscito: $detail';
      // Diagnostica temporanea: l'intera sequenza di log del tentativo
      // (1/2 avviato, completato, 2/2 avviato, ecc.), per leggerla
      // direttamente sullo schermo senza collegare il telefono a un PC.
      _debugLines = List.of(AuthService.debugLog);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.access_time_filled_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppConfig.instance.companyName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Timbrature e cantieri',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleSignIn,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login, size: 18),
                    label: Text(
                      _isLoading ? 'Accesso in corso...' : 'Accedi con Microsoft',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Login aziendale (Azure AD SSO)',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                // Diagnostica temporanea: nessun accesso alla console del
                // dispositivo per una build TestFlight (niente Mac
                // collegato), quindi il redirectUri usato a runtime va
                // reso visibile qui invece che solo loggato.
                Text(
                  'redirectUri: ${AppConfig.instance.redirectUri}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_debugLines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _debugLines.join('\n'),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
