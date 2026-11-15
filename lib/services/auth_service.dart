import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Gestisce il login aziendale (Azure AD / Microsoft Entra ID) e la
/// conservazione sicura dei token di accesso verso Business Central.
///
/// Nota di sicurezza: questa è un'app mobile pubblica, quindi usa il flusso
/// OAuth2 "Authorization Code + PKCE" tramite il browser di sistema, senza
/// alcun client secret incorporato nel codice (un client secret in un'app
/// mobile sarebbe comunque estraibile e quindi non sicuro).
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const _keyAccessToken = 'bc_access_token';
  static const _keyRefreshToken = 'bc_refresh_token';
  static const _keyExpiry = 'bc_token_expiry';

  // Login con codice azienda, nome utente e password (operai senza account
  // Microsoft): pass del server di login di Salary Solution (vedi server/).
  static const _keyMode = 'auth_mode'; // 'microsoft' | 'password'
  static const _keyAppToken = 'app_token';
  static const _keyAppTokenExpiry = 'app_token_expiry';
  static const _keyCompanyCode = 'app_company_code';
  static const _keyUsername = 'app_username';

  bool _passwordMode = false;

  /// True se l'utente è entrato con nome utente e password: le chiamate
  /// passano dal server di login invece che direttamente da BC.
  bool get isPasswordMode => _passwordMode;

  /// Base delle API: BC direttamente (login Microsoft) o il server di login.
  String get apiBaseUrl => _passwordMode
      ? '${AppConfig.instance.loginServerUrl}/bc'
      : AppConfig.instance.customApiBaseUrl;

  /// Da chiamare all'avvio, prima di usare [apiBaseUrl].
  Future<void> init() async {
    _passwordMode = await _secureStorage.read(key: _keyMode) == 'password';
  }

  /// Ultimi codice azienda e nome utente usati, per proporli nel login.
  Future<({String company, String username})> lastPasswordLogin() async => (
        company: await _secureStorage.read(key: _keyCompanyCode) ?? AppConfig.instance.defaultCompanyCode,
        username: await _secureStorage.read(key: _keyUsername) ?? '',
      );

  /// Login con codice azienda, nome utente e password tramite il server di
  /// login. Ritorna true se riuscito; altrimenti [lastErrorMessage] spiega.
  Future<bool> signInWithPassword(String company, String username, String password) async {
    lastErrorMessage = null;
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.instance.loginServerUrl}/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'company': company, 'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        lastErrorMessage = body['error'] as String? ?? 'Accesso non riuscito (${response.statusCode}).';
        return false;
      }
      final expiry = DateTime.fromMillisecondsSinceEpoch((body['expiresAt'] as num).toInt() * 1000);
      await _secureStorage.write(key: _keyAppToken, value: body['token'] as String);
      await _secureStorage.write(key: _keyAppTokenExpiry, value: expiry.toIso8601String());
      await _secureStorage.write(key: _keyCompanyCode, value: company.trim());
      await _secureStorage.write(key: _keyUsername, value: username.trim());
      await _secureStorage.write(key: _keyMode, value: 'password');
      _passwordMode = true;
      return true;
    } on TimeoutException {
      lastErrorMessage = 'Il server non risponde: controlla la connessione e riprova.';
      return false;
    } catch (e) {
      lastErrorMessage = 'Accesso non riuscito: $e';
      return false;
    }
  }

  /// Messaggio dell'ultimo errore di login, per diagnosticare i fallimenti
  /// (mostrato da LoginScreen). Non tradotto/ripulito: è un dettaglio
  /// tecnico utile in fase di test, non pensato per l'utente finale.
  String? lastErrorMessage;

  /// Avvia il login interattivo tramite il browser di sistema (Azure AD SSO).
  /// Ritorna true se il login è andato a buon fine.
  Future<bool> signIn() async {
    lastErrorMessage = null;
    // Diagnostica: nessun accesso alla console del dispositivo per una
    // build TestFlight (niente Mac collegato), quindi il valore usato a
    // runtime va reso visibile a schermo invece che solo loggato.
    debugPrint('AuthService.signIn: redirectUri="${AppConfig.instance.redirectUri}"');
    try {
      final result = await _appAuth
          .authorizeAndExchangeCode(
            AuthorizationTokenRequest(
              AppConfig.instance.azureClientId,
              AppConfig.instance.redirectUri,
              serviceConfiguration: AuthorizationServiceConfiguration(
                authorizationEndpoint: AppConfig.instance.authorizationEndpoint,
                tokenEndpoint: AppConfig.instance.tokenEndpoint,
              ),
              scopes: AppConfig.scopes,
              // Nessun prompt esplicito: sia 'select_account' che 'login' hanno
              // mostrato in test reale un ciclo silenzioso-poi-interattivo che
              // si blocca (AADSTS50199 seguito da un retry interno che non
              // completa il redirect verso l'app, o con 'login' un loop di
              // richieste di credenziali). Si lascia che Azure AD scelga il
              // proprio comportamento predefinito.
            ),
          )
          // Senza timeout, un blocco della sessione di login (osservato in
          // test reale su iOS: resta su "Accesso in corso..." a tempo
          // indeterminato dopo il redirect) lascia l'utente bloccato senza
          // alcun segnale d'errore. Il timeout include anche il tempo in cui
          // l'utente inserisce password e MFA nel browser, quindi deve essere
          // ampio.
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () => throw TimeoutException(
              'Timeout: il login non si è completato entro 3 minuti.',
            ),
          );

      if (result.accessToken == null) {
        lastErrorMessage = 'Nessun access token ricevuto dal login.';
        return false;
      }

      await _persistTokens(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        accessTokenExpirationDateTime: result.accessTokenExpirationDateTime,
      );
      await _secureStorage.write(key: _keyMode, value: 'microsoft');
      _passwordMode = false;
      return true;
    } catch (e) {
      lastErrorMessage = e.toString();
      return false;
    }
  }

  /// Restituisce un access token valido, rinnovandolo automaticamente
  /// tramite il refresh token se necessario. Ritorna null se serve un
  /// nuovo login interattivo (es. refresh token scaduto/revocato).
  Future<String?> getValidAccessToken() async {
    if (_passwordMode) {
      // Pass del server: valido 30 giorni, poi si rifà il login.
      final token = await _secureStorage.read(key: _keyAppToken);
      final expiry = DateTime.tryParse(await _secureStorage.read(key: _keyAppTokenExpiry) ?? '');
      if (token == null || expiry == null || expiry.isBefore(DateTime.now())) return null;
      return token;
    }
    final expiryString = await _secureStorage.read(key: _keyExpiry);
    final accessToken = await _secureStorage.read(key: _keyAccessToken);
    final refreshToken = await _secureStorage.read(key: _keyRefreshToken);

    if (accessToken == null) return null;

    final expiry =
        expiryString != null ? DateTime.tryParse(expiryString) : null;
    final isExpired = expiry == null ||
        expiry.isBefore(DateTime.now().add(const Duration(minutes: 2)));

    if (!isExpired) return accessToken;
    if (refreshToken == null) return null;

    try {
      final result = await _appAuth.token(
        TokenRequest(
          AppConfig.instance.azureClientId,
          AppConfig.instance.redirectUri,
          refreshToken: refreshToken,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: AppConfig.instance.authorizationEndpoint,
            tokenEndpoint: AppConfig.instance.tokenEndpoint,
          ),
          scopes: AppConfig.scopes,
        ),
      );

      if (result.accessToken == null) return null;

      await _persistTokens(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken ?? refreshToken,
        accessTokenExpirationDateTime: result.accessTokenExpirationDateTime,
      );
      return result.accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isSignedIn async {
    final token = await _secureStorage.read(key: _passwordMode ? _keyAppToken : _keyAccessToken);
    return token != null;
  }

  /// Esce da entrambi i tipi di login. Codice azienda e nome utente restano,
  /// per proporli al prossimo accesso.
  Future<void> signOut() async {
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyExpiry);
    await _secureStorage.delete(key: _keyAppToken);
    await _secureStorage.delete(key: _keyAppTokenExpiry);
    await _secureStorage.delete(key: _keyMode);
    _passwordMode = false;
  }

  Future<void> _persistTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? accessTokenExpirationDateTime,
  }) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    if (refreshToken != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    }
    if (accessTokenExpirationDateTime != null) {
      await _secureStorage.write(
        key: _keyExpiry,
        value: accessTokenExpirationDateTime.toIso8601String(),
      );
    }
  }
}
