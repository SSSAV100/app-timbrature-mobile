import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/project.dart';
import 'local_files.dart';
import '../widgets/material_sheet.dart';

/// PDF del bollettino a regia (richiesta del cliente, 26.11.2026): commessa,
/// WBS, giorno, descrizione intervento, materiale, manodopera e firma del
/// cliente. Condiviso subito, allegato alla commessa e mandato da BC al
/// Capo Cantiere.
class ProjectReportPdf {
  ProjectReportPdf._();

  static Future<File> generate({
    required Project project,
    required String taskLabel,
    required DateTime date,
    required List<Map<String, dynamic>> materials,
    required List<Map<String, dynamic>> labor,
    required String workDone,
    required String clientName,
    required Uint8List signaturePng,
  }) async {
    final companyName = await LocalFiles.companyName();
    final doc = pw.Document();
    final laborTotal = labor.fold(0.0, (sum, l) => sum + ((l['hours'] as num?)?.toDouble() ?? 0));
    String h(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(companyName, style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Bollettino a regia', style: const pw.TextStyle(fontSize: 14)),
          pw.Divider(height: 24),
          _row('Commessa', '${project.id} · ${project.description}'),
          if (taskLabel.isNotEmpty) _row('WBS', taskLabel),
          _row('Data', DateFormat('dd.MM.yyyy').format(date)),
          pw.SizedBox(height: 16),
          pw.Text('Descrizione intervento', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(workDone),
          if (materials.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Materiale', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            for (final m in materials) pw.Text(MaterialSheet.label(m)),
          ],
          if (labor.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Manodopera', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            for (final l in labor) pw.Text('${l['workerName']} · ${h((l['hours'] as num).toDouble())} h'),
            pw.Text('Totale: ${h(laborTotal)} h', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
          pw.SizedBox(height: 32),
          pw.Text('Firma del cliente${clientName.isEmpty ? '' : ' ($clientName)'}'),
          pw.SizedBox(height: 8),
          pw.Image(pw.MemoryImage(signaturePng), height: 80),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'bollettini',
        'bollettino_${project.id}_${DateFormat('yyyyMMdd').format(date)}_${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 110, child: pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(value)),
          ],
        ),
      );
}
