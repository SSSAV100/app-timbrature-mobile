import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  /// Messaggio dell'ultimo errore di login, per diagnosticare i fallimenti
  /// (mostrato da LoginScreen). Non tradotto/ripulito: è un dettaglio
  /// tecnico utile in fase di test, non pensato per l'utente finale.
  String? lastErrorMessage;

  static void _log(String message) {
    // ignore: avoid_print
    print('[AUTH DEBUG] $message');
    developer.log(message, name: 'AuthService');
  }

  /// Avvia il login interattivo tramite il browser di sistema (Azure AD SSO).
  /// Ritorna true se il login è andato a buon fine.
  ///
  /// VERSIONE DIAGNOSTICA TEMPORANEA: il flusso normale
  /// (authorizeAndExchangeCode, un'unica chiamata) è stato diviso in due
  /// passaggi separati — authorize() e token() — ciascuno con il proprio
  /// timeout e log a console, per capire quale dei due si blocca durante
  /// il login su iOS reale (osservato: timeout dopo 25s con la chiamata
  /// unica, causa non ancora isolata). Da ripristinare alla versione unica
  /// una volta isolata la causa.
  Future<bool> signIn() async {
    lastErrorMessage = null;
    try {
      _log('redirectUri="${AppConfig.instance.redirectUri}"');
      _log('1/2 — Avvio authorize() (autorizzazione + redirect)...');

      final authResponse = await _appAuth
          .authorize(
            AuthorizationRequest(
              AppConfig.instance.azureClientId,
              AppConfig.instance.redirectUri,
              serviceConfiguration: AuthorizationServiceConfiguration(
                authorizationEndpoint: AppConfig.instance.authorizationEndpoint,
                tokenEndpoint: AppConfig.instance.tokenEndpoint,
              ),
              scopes: AppConfig.scopes,
              promptValues: const ['select_account'],
            ),
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              _log('1/2 — TIMEOUT: authorize() non ha risposto entro 45s. '
                  'Il blocco è nel redirect/autorizzazione, non nello scambio token.');
              throw TimeoutException('authorize() timeout (redirect/autorizzazione)');
            },
          );

      _log('1/2 — authorize() completato. '
          'authorizationCode presente: ${authResponse.authorizationCode != null}, '
          'codeVerifier presente: ${authResponse.codeVerifier != null}');

      if (authResponse.authorizationCode == null) {
        _log('1/2 — Nessun codice di autorizzazione ricevuto: '
            'l\'utente ha annullato, o il redirect non ha portato un codice valido.');
        lastErrorMessage = 'authorize() non ha restituito un codice di autorizzazione.';
        return false;
      }

      _log('2/2 — Avvio token() (scambio codice -> access token)...');

      final tokenResponse = await _appAuth
          .token(
            TokenRequest(
              AppConfig.instance.azureClientId,
              AppConfig.instance.redirectUri,
              authorizationCode: authResponse.authorizationCode,
              codeVerifier: authResponse.codeVerifier,
              serviceConfiguration: AuthorizationServiceConfiguration(
                authorizationEndpoint: AppConfig.instance.authorizationEndpoint,
                tokenEndpoint: AppConfig.instance.tokenEndpoint,
              ),
              scopes: AppConfig.scopes,
            ),
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              _log('2/2 — TIMEOUT: token() non ha risposto entro 45s. '
                  'Il redirect ha funzionato, il blocco è nella chiamata di '
                  'rete verso il token endpoint (dopo che il browser si è già chiuso).');
              throw TimeoutException('token() timeout (scambio codice -> token)');
            },
          );

      _log('2/2 — token() completato. accessToken presente: ${tokenResponse.accessToken != null}');

      if (tokenResponse.accessToken == null) {
        lastErrorMessage = 'token() non ha restituito un access token.';
        return false;
      }

      await _persistTokens(
        accessToken: tokenResponse.accessToken!,
        refreshToken: tokenResponse.refreshToken,
        accessTokenExpirationDateTime: tokenResponse.accessTokenExpirationDateTime,
      );
      return true;
    } catch (e, stackTrace) {
      _log('ECCEZIONE: ${e.runtimeType} — $e');
      _log('Stack trace: $stackTrace');
      lastErrorMessage = e.toString();
      return false;
    }
  }

  /// Restituisce un access token valido, rinnovandolo automaticamente
  /// tramite il refresh token se necessario. Ritorna null se serve un
  /// nuovo login interattivo (es. refresh token scaduto/revocato).
  Future<String?> getValidAccessToken() async {
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
    final token = await _secureStorage.read(key: _keyAccessToken);
    return token != null;
  }

  Future<void> signOut() async {
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyExpiry);
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
