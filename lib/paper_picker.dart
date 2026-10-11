import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import 'pdf_export.dart';

/// يسأل عن حجم الورق (A5 أو A4). يرجع null إن أُلغي.
Future<PdfPageFormat?> askPaperSize(BuildContext context,
    {required String title, bool a5Default = false}) {
  return showDialog<PdfPageFormat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, PdfPageFormat.a5),
          child: ListTile(
            leading: const Icon(Icons.crop_portrait),
            title: const Text('A5 (نصف ورقة)'),
            subtitle: Text(a5Default ? 'الافتراضي' : 'مناسب للإيصالات والتقارير المختصرة'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, PdfPageFormat.a4),
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('A4 (ورقة كاملة)'),
            subtitle: Text(a5Default ? 'ورقة كاملة' : 'الافتراضي'),
          ),
        ),
      ],
    ),
  );
}

Future<void> printReceiptAsk(BuildContext context, Map<String, dynamic> pay) async {
  final f = await askPaperSize(context, title: 'طباعة الإيصال', a5Default: true);
  if (f == null) return;
  await printReceipt(pay, format: f);
}

Future<void> exportAccountAsk(BuildContext context, Map<String, dynamic> prop,
    List<Map<String, dynamic>> pays) async {
  final f = await askPaperSize(context, title: 'كشف الحساب - حجم الورق');
  if (f == null) return;
  await exportAccount(prop, pays, format: f);
}

Future<void> exportAllAsk(BuildContext context, List<Map<String, dynamic>> props,
    List<Map<String, dynamic>> pays,
    {DateTime? from, DateTime? to, bool allProps = true}) async {
  final f = await askPaperSize(context, title: 'التقرير الشامل - حجم الورق');
  if (f == null) return;
  await exportAll(props, pays, from: from, to: to, allProps: allProps, format: f);
}
