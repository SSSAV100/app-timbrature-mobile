import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bollettino.dart';
import '../models/project.dart';
import 'config.dart';

/// Genera il PDF del bollettino di intervento firmato, da condividere
/// immediatamente con il cliente (vedi specifica funzionale, sezione 7.2).
/// Questo PDF è una comodità per l'utente sul momento: la registrazione
/// ufficiale del bollettino avviene comunque tramite l'invio dei dati a
/// Business Central (vedi BcApiService.submitBollettino).
class BollettinoPdfGenerator {
  BollettinoPdfGenerator._();

  static Future<File> generate({
    required Bollettino bollettino,
    required Project project,
  }) async {
    final doc = pw.Document();
    final dateFormat = DateFormat('dd.MM.yyyy');
    final timeFormat = DateFormat('HH:mm');

    final clientSignatureBytes = await File(bollettino.clientSignaturePath).readAsBytes();
    final clientSignatureImage = pw.MemoryImage(clientSignatureBytes);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                AppConfig.instance.companyName,
                style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Bollettino di intervento', style: const pw.TextStyle(fontSize: 14)),
              pw.Divider(height: 24),

              _row('Cliente / progetto', project.description),
              _row('Referente cliente', bollettino.clientContactName),
              _row('Data', dateFormat.format(bollettino.startTime)),
              _row(
                'Orario',
                '${timeFormat.format(bollettino.startTime)} - ${timeFormat.format(bollettino.endTime)}',
              ),
              pw.SizedBox(height: 16),

              pw.Text('Descrizione intervento', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(bollettino.description),
              pw.SizedBox(height: 16),

              if (bollettino.materials.isNotEmpty) ...[
                pw.Text('Materiali utilizzati', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _cell('Descrizione', bold: true),
                        _cell('Quantità', bold: true),
                      ],
                    ),
                    ...bollettino.materials.map(
                      (m) => pw.TableRow(children: [
                        _cell(m.description),
                        _cell(m.quantity.toStringAsFixed(2)),
                      ]),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
              ],

              pw.Spacer(),
              pw.Text('Firma cliente', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Container(
                height: 100,
                width: 220,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                child: pw.Image(clientSignatureImage),
              ),
            ],
          );
        },
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final fileName = 'bollettino_${bollettino.localId}.pdf';
    final file = File(p.join(tempDir.path, fileName));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
          ),
          pw.Text(value),
        ],
      ),
    );
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }
}
