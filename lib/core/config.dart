import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Configurazione specifica del cliente/azienda per cui questa build
/// dell'app è destinata.
///
/// Per pubblicare l'app per un nuovo cliente NON serve modificare il
/// codice: basta sostituire il file `assets/client_config.json` (e
/// l'icona/logo in `assets/branding/`) con quelli del nuovo cliente, poi
/// ricompilare. Vedi README.md, sezione "Onboarding di un nuovo cliente".
class AppConfig {
  AppConfig._({
    required this.appDisplayName,
    required this.companyName,
    required this.primaryColorHex,
    required this.azureTenantId,
    required this.azureClientId,
    required this.redirectUri,
    required this.bcEnvironment,
    required this.customApiPublisher,
    required this.customApiGroup,
    required this.customApiVersion,
  });

  final String appDisplayName;
  final String companyName;
  final String primaryColorHex;
  final String azureTenantId;
  final String azureClientId;
  final String redirectUri;
  final String bcEnvironment;
  final String customApiPublisher;
  final String customApiGroup;
  final String customApiVersion;

  static AppConfig? _instance;

  /// Configurazione attiva. Va caricata con [load] in main() prima di
  /// runApp(); se interrogata prima del caricamento, lancia un errore
  /// esplicito piuttosto che restituire dati sbagliati o vuoti.
  static AppConfig get instance {
    final config = _instance;
    if (config == null) {
      throw StateError(
        'AppConfig non ancora caricata: chiamare AppConfig.load() in main() '
        'prima di runApp().',
      );
    }
    return config;
  }

  /// Carica la configurazione dal file assets/client_config.json incluso
  /// nel bundle dell'app. Questo è l'UNICO file da cambiare (insieme
  /// all'icona) per creare la build di un nuovo cliente.
  static Future<AppConfig> load() async {
    final raw = await rootBundle.loadString('assets/client_config.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final config = AppConfig._(
      appDisplayName: json['appDisplayName'] as String,
      companyName: json['companyName'] as String,
      primaryColorHex: json['primaryColorHex'] as String,
      azureTenantId: json['azureTenantId'] as String,
      azureClientId: json['azureClientId'] as String,
      redirectUri: json['redirectUri'] as String,
      bcEnvironment: json['bcEnvironment'] as String,
      customApiPublisher: json['customApiPublisher'] as String,
      customApiGroup: json['customApiGroup'] as String,
      customApiVersion: json['customApiVersion'] as String,
    );
    _instance = config;
    return config;
  }

  // --- Valori uguali per tutti i clienti: non vanno duplicati nel JSON ---

  static const List<String> scopes = [
    'https://api.businesscentral.dynamics.com/user_impersonation',
    'offline_access',
    'openid',
    'profile',
  ];

  String get authorizationEndpoint =>
      'https://login.microsoftonline.com/$azureTenantId/oauth2/v2.0/authorize';

  String get tokenEndpoint =>
      'https://login.microsoftonline.com/$azureTenantId/oauth2/v2.0/token';

  /// Base URL delle API custom AL usate da questa app. Esempio risultante:
  /// https://api.businesscentral.dynamics.com/v2.0/<tenant>/Sandbox/api/nomeazienda/timbrature/v1.0
  String get customApiBaseUrl =>
      'https://api.businesscentral.dynamics.com/v2.0/$azureTenantId/'
      '$bcEnvironment/api/$customApiPublisher/$customApiGroup/$customApiVersion';
}
