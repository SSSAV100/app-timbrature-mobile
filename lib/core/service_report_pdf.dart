import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/service_action.dart';
import '../models/service_assignment.dart';
import 'config.dart';

/// Rapporto di intervento Service firmato dal cliente: condiviso subito col
/// cliente e allegato all'ordine di assistenza in BC (serviceAttachments).
/// Ore e materiali sono quelli inseriti dall'app su questo intervento.
class ServiceReportPdf {
  ServiceReportPdf._();

  static Future<File> generate({
    required ServiceAssignment assignment,
    required List<ServiceAction> actions,
    required String workDone,
    required String clientName,
    required Uint8List signaturePng,
  }) async {
    final doc = pw.Document();
    final dateFormat = DateFormat('dd.MM.yyyy');
    final hours = actions.where((a) => a.kind == ServiceActionKind.hours).toList();
    final materials = actions.where((a) => a.kind == ServiceActionKind.material).toList();

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
            pw.Text('Rapporto di intervento ${assignment.orderNo}', style: const pw.TextStyle(fontSize: 14)),
            pw.Divider(height: 24),
            _row('Cliente', assignment.customerName),
            _row('Indirizzo', assignment.fullAddress),
            _row('Data', dateFormat.format(DateTime.now())),
            if (assignment.itemDescription.isNotEmpty) _row('Oggetto', assignment.itemDescription),
            if (assignment.orderDescription.isNotEmpty) _row('Richiesta', assignment.orderDescription),
            pw.SizedBox(height: 16),
            pw.Text('Lavoro svolto', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(workDone.isEmpty ? '-' : workDone),
            if (hours.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('Ore', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              for (final h in hours)
                pw.Text('${h.payload['date']} · ${h.payload['workTypeCode']} · ${h.payload['hoursService']} h'),
            ],
            if (materials.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('Materiale', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              for (final m in materials)
                pw.Text('${m.payload['quantity']} × ${m.payload['itemNo']} ${m.payload['_itemDescription'] ?? ''}'),
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
    final file = File(p.join(dir.path, 'bollettini', 'rapporto_${assignment.orderNo}_${DateTime.now().millisecondsSinceEpoch}.pdf'));
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
