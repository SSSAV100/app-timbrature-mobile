import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/local_files.dart';
import '../models/assenza_request.dart';
import '../models/bollettino.dart';
import '../models/nota_spesa.dart';
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

  /// Legge il saldo ferie/permessi residuo dell'utente, espresso in ore
  /// (vedi specifica funzionale, sezione 8: tutto è gestito in ore, non in
  /// giorni). Endpoint atteso: GET {customApiBaseUrl}/vacationBalance
  Future<double> fetchVacationBalanceHours() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/vacationBalance');

    final response = await http.get(uri, headers: headers);
    _throwIfNotOk(response);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['balanceHours'] as num? ?? 0).toDouble();
  }

  /// Invia una richiesta di ferie o una segnalazione di assenza (malattia,
  /// infortunio) a Business Central. Endpoint atteso:
  /// POST {customApiBaseUrl}/absenceRequests
  /// Nessun flusso di approvazione è gestito da questa versione dell'app:
  /// la richiesta viene semplicemente raccolta e inviata.
  Future<void> submitAssenza(AssenzaRequest assenza) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/absenceRequests');

    String? attachmentBase64;
    String? attachmentFileName;
    if (assenza.attachmentPath != null) {
      attachmentBase64 = base64Encode(await LocalFiles.readBytes(assenza.attachmentPath!));
      attachmentFileName = assenza.attachmentPath!.split('/').last;
    }

    final payload = {
      'type': assenza.type.name,
      'startDate': _dateOnly(assenza.startDate),
      'endDate': _dateOnly(assenza.endDate),
      'hoursPerDay': assenza.hoursPerDay,
      if (assenza.note != null && assenza.note!.isNotEmpty) 'note': assenza.note,
      if (assenza.incidentDescription != null) 'incidentDescription': assenza.incidentDescription,
      if (assenza.incidentLocation != null) 'incidentLocation': assenza.incidentLocation,
      if (attachmentBase64 != null) 'attachmentBase64': attachmentBase64,
      if (attachmentFileName != null) 'attachmentFileName': attachmentFileName,
    };

    final response = await http.post(uri, headers: headers, body: jsonEncode(payload));
    _throwIfNotOk(response);
  }

  /// Invia una nota spesa a Business Central. Endpoint atteso:
  /// POST {customApiBaseUrl}/expenseReports
  Future<void> submitNotaSpesa(NotaSpesa nota) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.instance.customApiBaseUrl}/expenseReports');

    final receiptBase64 = base64Encode(await LocalFiles.readBytes(nota.receiptPath));

    final payload = {
      'date': _dateOnly(nota.date),
      'category': nota.category.name,
      'amountChf': nota.amountChf,
      if (nota.description != null && nota.description!.isNotEmpty) 'description': nota.description,
      if (nota.projectId != null) 'projectId': nota.projectId,
      'receiptBase64': receiptBase64,
      'receiptFileName': nota.receiptPath.split('/').last,
    };

    final response = await http.post(uri, headers: headers, body: jsonEncode(payload));
    _throwIfNotOk(response);
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
