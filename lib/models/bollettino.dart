import 'dart:convert';

import 'bollettino_material.dart';
import 'timesheet_entry.dart' show SyncStatus;

/// Il bollettino di intervento digitale per un progetto Service (vedi
/// specifica funzionale, sezione 7). Contiene i dati dell'intervento e i
/// percorsi locali (non i contenuti binari) di foto e firma: i file veri
/// e propri restano su disco, in una cartella permanente dell'app (vedi
/// core/local_files.dart), e vengono letti solo al momento dell'invio a
/// Business Central o della generazione del PDF.
///
/// Salvato sempre prima in locale (stesso pattern di TimesheetPunch e
/// TimeEntry): non va perso nemmeno se compilato offline presso il cliente.
class Bollettino {
  final String localId;
  final String projectId; // deve essere un progetto di tipo Service
  final String clientContactName;
  final DateTime startTime;
  final DateTime endTime;
  final String description;
  final List<BollettinoMaterial> materials;
  final List<String> photoPaths; // percorsi locali permanenti
  final String clientSignaturePath; // percorso locale permanente (PNG)
  final String? technicianSignaturePath;
  SyncStatus status;
  String? errorMessage;

  Bollettino({
    required this.localId,
    required this.projectId,
    required this.clientContactName,
    required this.startTime,
    required this.endTime,
    required this.description,
    required this.clientSignaturePath,
    this.materials = const [],
    this.photoPaths = const [],
    this.technicianSignaturePath,
    this.status = SyncStatus.pending,
    this.errorMessage,
  });

  Map<String, dynamic> toDbMap() {
    return {
      'local_id': localId,
      'project_id': projectId,
      'client_contact_name': clientContactName,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'description': description,
      'materials_json': jsonEncode(materials.map((m) => m.toJson()).toList()),
      'photo_paths_json': jsonEncode(photoPaths),
      'client_signature_path': clientSignaturePath,
      'technician_signature_path': technicianSignaturePath,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  factory Bollettino.fromDbMap(Map<String, dynamic> map) {
    final rawMaterials = jsonDecode(map['materials_json'] as String) as List<dynamic>;
    final rawPhotos = jsonDecode(map['photo_paths_json'] as String) as List<dynamic>;
    return Bollettino(
      localId: map['local_id'] as String,
      projectId: map['project_id'] as String,
      clientContactName: map['client_contact_name'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      description: map['description'] as String,
      materials: rawMaterials
          .map((e) => BollettinoMaterial.fromJson(e as Map<String, dynamic>))
          .toList(),
      photoPaths: rawPhotos.map((e) => e as String).toList(),
      clientSignaturePath: map['client_signature_path'] as String,
      technicianSignaturePath: map['technician_signature_path'] as String?,
      status: SyncStatus.values.byName(map['status'] as String),
      errorMessage: map['error_message'] as String?,
    );
  }
}
