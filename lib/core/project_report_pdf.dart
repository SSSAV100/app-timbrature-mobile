import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/project.dart';
import '../models/time_entry.dart';
import 'config.dart';

/// Bollettino facoltativo delle ore di progetto, firmato dal cliente:
/// condiviso subito e allegato alla commessa in BC (projectAttachments).
class ProjectReportPdf {
  ProjectReportPdf._();

  static Future<File> generate({
    required Project project,
    required DateTime date,
    required List<TimeEntry> hours,
    required List<Map<String, dynamic>> materials,
    required String workDone,
    required String clientName,
    required Uint8List signaturePng,
  }) async {
    final doc = pw.Document();
    String taskName(String? id) =>
        project.tasks.where((t) => t.id == id).map((t) => t.description).firstOrNull ?? (id ?? '');
    final total = hours.fold(0.0, (sum, e) => sum + e.hoursWorked);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(AppConfig.instance.companyName,
                style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Bollettino di lavoro', style: const pw.TextStyle(fontSize: 14)),
            pw.Divider(height: 24),
            _row('Commessa', '${project.id} · ${project.description}'),
            _row('Data', DateFormat('dd.MM.yyyy').format(date)),
            if (hours.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('Ore', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              for (final e in hours)
                pw.Text('${e.startTime ?? ''}–${e.endTime ?? ''} · ${taskName(e.taskId)} · '
                    '${e.hoursWorked.toStringAsFixed(2)} h'),
              pw.Text('Totale: ${total.toStringAsFixed(2)} h', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
            pw.SizedBox(height: 16),
            pw.Text('Lavoro svolto', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(workDone),
            if (materials.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('Materiale', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              for (final m in materials) pw.Text('${m['quantity']} × ${m['itemNo']} ${m['_itemDescription'] ?? ''}'),
            ],
            pw.Spacer(),
            pw.Text('Firma del cliente${clientName.isEmpty ? '' : ' ($clientName)'}'),
            pw.SizedBox(height: 8),
            pw.Image(pw.MemoryImage(signaturePng), height: 80),
          ],
        ),
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
