import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../models/project.dart';
import '../models/timesheet_entry.dart';
import 'auth_service.dart';

/// Client HTTP verso le API personalizzate di Business Central.
///
/// L'app non passa mai da un middleware: chiama direttamente le API AL
/// esposte da Business Central (vedi specifica funzionale, sezione 12).
/// Gli endpoint esatti (nomi risorsa, campi) vanno allineati con lo
/// sviluppo AL prima del primo utilizzo reale — vedi README.md, sezione
/// "API attese da Business Central", per il contratto atteso da questo file.
class BcApiService {
  BcApiService._internal();
  static final BcApiService instance = BcApiService._internal();

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.instance.getValidAccessToken();
    if (token == null) {
      throw BcApiException(
          'Sessione scaduta, effettuare nuovamente il login.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Recupera i progetti/cantieri assegnati all'utente corrente.
  /// Endpoint atteso: GET {customApiBaseUrl}/assignedProjects
  Future<List<Project>> fetchAssignedProjects() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/assignedProjects');

    final response = await http.get(uri, headers: headers);
    _throwIfNotOk(response);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['value'] as List<dynamic>? ?? []);
    return items
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Invia una singola timbratura a Business Central.
  /// Endpoint atteso: POST {customApiBaseUrl}/timePunches
  /// Lancia [BcApiException] in caso di errore di rete o risposta non 2xx:
  /// il chiamante (SyncService) decide se ritentare più tardi.
  Future<void> submitPunch(TimesheetPunch punch) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/timePunches');

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(punch.toBcJson()),
    );
    _throwIfNotOk(response);
  }

  void _throwIfNotOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BcApiException(
        'Errore Business Central (${response.statusCode}): ${response.body}',
      );
    }
  }
}

class BcApiException implements Exception {
  final String message;
  BcApiException(this.message);

  @override
  String toString() => message;
}
