import 'dart:async';

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

  /// Avvia il login interattivo tramite il browser di sistema (Azure AD SSO).
  /// Ritorna true se il login è andato a buon fine.
  Future<bool> signIn() async {
    lastErrorMessage = null;
    try {
      final result = await _appAuth
          .authorizeAndExchangeCode(
            AuthorizationTokenRequest(
              AppConfig.instance.azureClientId,
              AppConfig.instance.platformRedirectUri,
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
          // alcun segnale d'errore.
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException(
              'Timeout: il login non si è completato entro 25 secondi.',
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
          AppConfig.instance.platformRedirectUri,
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
