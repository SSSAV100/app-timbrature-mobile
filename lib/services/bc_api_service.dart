import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/local_files.dart';
import '../models/bollettino.dart';
import '../models/project.dart';
import '../models/time_entry.dart';
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

  /// Recupera i progetti/cantieri assegnati all'utente corrente, con i
  /// relativi task/attività annidati.
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

  /// Invia una singola riga di ripartizione ore a Business Central.
  /// Endpoint atteso: POST {customApiBaseUrl}/timeEntries
  /// Business Central, una volta approvata la riga (vedi specifica
  /// funzionale sezione 10), si occupa internamente di propagarla sia al
  /// modulo Progetti sia a SwissSalary: l'app non parla mai direttamente
  /// con SwissSalary.
  Future<void> submitTimeEntry(TimeEntry entry) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/timeEntries');

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(entry.toBcJson()),
    );
    _throwIfNotOk(response);
  }

  /// Invia un bollettino di intervento firmato a Business Central.
  /// Endpoint atteso: POST {customApiBaseUrl}/serviceReports
  /// Foto e firma vengono lette dal disco e incluse come stringhe base64
  /// nel payload: per il volume previsto (poche foto per intervento) è la
  /// soluzione più semplice; se in futuro i bollettini includessero molte
  /// foto ad alta risoluzione, andrebbe valutato un endpoint di upload
  /// separato per gli allegati.
  Future<void> submitBollettino(Bollettino bollettino) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/serviceReports');

    final clientSignatureBytes = await LocalFiles.readBytes(bollettino.clientSignaturePath);
    final technicianSignatureBytes = bollettino.technicianSignaturePath != null
        ? await LocalFiles.readBytes(bollettino.technicianSignaturePath!)
        : null;
    final photosBase64 = await Future.wait(
      bollettino.photoPaths.map((path) async => base64Encode(await LocalFiles.readBytes(path))),
    );

    final payload = {
      'projectId': bollettino.projectId,
      'clientContactName': bollettino.clientContactName,
      'startTime': bollettino.startTime.toUtc().toIso8601String(),
      'endTime': bollettino.endTime.toUtc().toIso8601String(),
      'description': bollettino.description,
      'materials': bollettino.materials.map((m) => m.toJson()).toList(),
      'photosBase64': photosBase64,
      'clientSignatureBase64': base64Encode(clientSignatureBytes),
      if (technicianSignatureBytes != null)
        'technicianSignatureBase64': base64Encode(technicianSignatureBytes),
    };

    final response = await http.post(uri, headers: headers, body: jsonEncode(payload));
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
