// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// "Print recovery sheet": the 25 words, filled in, sent straight to the system print dialog. Nothing is saved:
// the PDF exists only in memory and is handed to the printer. (The system print panel can still offer "Save as PDF";
// the warning before printing tells people not to use it.)
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../wallet/wallet_meta.dart';
import 'theme.dart';
import 'widgets.dart';

/// One page: the numbered words in a 5 x 5 grid, blanks to write on, and the rules.
Future<Uint8List> seedSheetPdf(List<String> words, PdfPageFormat format, {bool compress = true, WalletMeta? meta}) {
  final doc = pw.Document(
    compress: compress,
    title: 'Recovery sheet',
    author: 'Ghillie',
    creator: 'Ghillie',
    producer: 'Ghillie',
  );
  final ink = PdfColor.fromInt(0xFF1E2418), grey = PdfColor.fromInt(0xFF6B7062);
  pw.Widget blank(String label, [String? value]) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          height: 22,
          alignment: pw.Alignment.bottomLeft,
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: value == null
              ? null
              : pw.Text(value, style: pw.TextStyle(font: pw.Font.courierBold(), fontSize: 12, color: ink)),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: ink)),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: grey)),
      ],
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CAMO RECOVERY SHEET',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ink),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Ghillie wallet · 25 recovery words', style: pw.TextStyle(fontSize: 11, color: grey)),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: 1.5)),
            child: pw.Text(
              'Anyone with these words can take your coins. Keep this paper somewhere safe and private. '
              'Never type the words into a website, a chat or a photo. Nobody from CAMO will ever ask for them.',
              style: pw.TextStyle(fontSize: 10, color: ink, lineSpacing: 2),
            ),
          ),
          pw.SizedBox(height: 22),
          pw.GridView(
            crossAxisCount: 5,
            childAspectRatio: 0.42,
            crossAxisSpacing: 8,
            mainAxisSpacing: 10,
            children: [
              for (var i = 0; i < words.length; i++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: grey, width: 0.8)),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 18,
                        child: pw.Text('${i + 1}', style: pw.TextStyle(fontSize: 9, color: grey)),
                      ),
                      pw.Expanded(
                        child: pw.FittedBox(
                          // the longest words ("verification") shrink a little instead of wrapping
                          fit: pw.BoxFit.scaleDown,
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Text(
                            words[i],
                            style: pw.TextStyle(font: pw.Font.courierBold(), fontSize: 12, color: ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 26),
          pw.Row(children: [blank('Wallet name (optional)'), pw.SizedBox(width: 16), blank('Date the wallet was made', meta?.createdText)]),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              blank('Restore height (speeds up a restore; lower is always safe)', meta?.restoreHeight?.toString()),
              pw.SizedBox(width: 16),
              blank('Where the second copy is kept'),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            'Keep two copies in two places. Paper fades and burns: consider stamping the words in metal later. '
            'To restore: Ghillie > Restore from 25 words.',
            style: pw.TextStyle(fontSize: 9, color: grey, lineSpacing: 2),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Asks first (trusted printer, no "Save as PDF"), then opens the system print dialog with the filled-in sheet.
Future<void> printSeedSheet(
  BuildContext context,
  List<String> words, {
  Future<bool> Function(LayoutCallback onLayout)? printer,
  WalletMeta? meta,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('PRINT YOUR WORDS', style: Gt.pixel(24)),
      content: Text(
        'Print only on your own printer at home. Office, library and shop printers often keep copies.\n\n'
        'In the print screen, choose your printer. Do not choose "Save as PDF" or share it: '
        'that would put your words in a file.\n\nNothing is saved by Ghillie.',
        style: Gt.body(14, color: Gc.text2).copyWith(height: 1.45),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('seed-print-go'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Print'),
        ),
      ],
    ),
  );
  if (go != true) return;
  await (printer ?? (f) => Printing.layoutPdf(onLayout: f, name: 'Recovery sheet'))(
    (format) => seedSheetPdf(words, format, meta: meta),
  );
}

/// The 25 words on screen, numbered, in reading order.
class SeedWordsGrid extends StatelessWidget {
  final List<String> words;
  const SeedWordsGrid(this.words, {super.key});
  @override
  Widget build(BuildContext context) => NotchBox(
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < words.length; i++)
          SizedBox(width: 98, child: Text('${(i + 1).toString().padLeft(2)} ${words[i]}', style: Gt.mono(13))),
      ],
    ),
  );
}
