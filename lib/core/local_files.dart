import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Salva dei byte (es. una firma catturata su schermo, o una foto scelta
/// dalla galleria) in una cartella permanente dell'app, così da non
/// perderli se il sistema operativo ripulisce le cartelle temporanee/cache
/// prima che il bollettino sia stato sincronizzato con Business Central.
class LocalFiles {
  LocalFiles._();

  static Future<String> saveBytes(Uint8List bytes, String suggestedName) async {
    final dir = await getApplicationDocumentsDirectory();
    final bollettiniDir = Directory(p.join(dir.path, 'bollettini'));
    if (!await bollettiniDir.exists()) {
      await bollettiniDir.create(recursive: true);
    }
    final path = p.join(bollettiniDir.path, suggestedName);
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Copia un file (es. una foto scelta da fotocamera/galleria, che
  /// image_picker restituisce spesso in una cartella temporanea) nella
  /// cartella permanente dell'app.
  static Future<String> copyToPermanentStorage(String sourcePath, String suggestedName) async {
    final bytes = await File(sourcePath).readAsBytes();
    return saveBytes(bytes, suggestedName);
  }

  static Future<Uint8List> readBytes(String path) => File(path).readAsBytes();
}
