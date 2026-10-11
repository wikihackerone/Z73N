import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'utils.dart';

Future<pw.Document> _doc() async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  return pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
}

/// حجم خط الجداول (يصغر قليلاً في ورق A5)
double _fs = 9;

pw.Widget _cell(String t, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(t,
          style: pw.TextStyle(
              fontSize: _fs,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

pw.Widget _table(List<String> head, List<List<String>> rows) => pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: head.map((h) => _cell(h, bold: true)).toList(),
        ),
        ...rows.map((r) => pw.TableRow(children: r.map((c) => _cell(c)).toList())),
      ],
    );

pw.Widget _kv(String a, String b, {bool strong = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(a,
              style: pw.TextStyle(
                  fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(b,
              style: pw.TextStyle(
                  fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );

pw.Widget _title(String t) => pw.Column(children: [
      if (companyName.isNotEmpty)
        pw.Center(child: pw.Text(companyName, style: const pw.TextStyle(fontSize: 11))),
      pw.Center(
        child: pw.Text(t,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      ),
      pw.SizedBox(height: 6),
    ]);

Future<void> _show(pw.Document doc, String name) => Printing.layoutPdf(
      name: name,
      onLayout: (PdfPageFormat f) async => doc.save(),
    );

// ---------------------------------------------------------
// إيصال استلام (برقم متسلسل)
// ---------------------------------------------------------
Future<void> printReceipt(Map<String, dynamic> pay,
    {PdfPageFormat format = PdfPageFormat.a5}) async {
  final doc = await _doc();
  final small = format.width < PdfPageFormat.a4.width;
  _fs = small ? 8 : 9;
  final no = receiptNo(pay);
  final other = num0(pay['other_amount']);
  final otherNote = (pay['other_note'] ?? '').toString();
  final newBal = num0(pay['new_balance']);
  final isUtil = pay['kind'] == 'utilities';

  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.all(small ? 24 : 40),
      textDirection: pw.TextDirection.rtl,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _title('إيصال استلام ${isUtil ? 'مرافق' : 'إيجار ومرافق'}'),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('رقم الإيصال: $no',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('التاريخ: ${fmtDateStr(pay['paid_at'])}'),
            ],
          ),
          pw.Divider(),
          pw.Text('العقار: ${pay['property_name'] ?? ''}'),
          pw.SizedBox(height: 4),
          pw.Text('المستأجر: ${pay['tenant_name'] ?? ''}'),
          pw.SizedBox(height: 4),
          pw.Text('الهاتف: ${pay['tenant_phone'] ?? ''}'),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(children: [
              if (!isUtil) _kv('الإيجار الشهري', fmt(num0(pay['rent']))),
              _kv('كهرباء', fmt(num0(pay['electricity']))),
              _kv('مياه', fmt(num0(pay['water']))),
              _kv('غاز', fmt(num0(pay['gas']))),
              if (other > 0)
                _kv(otherNote.isEmpty ? 'خدمات أخرى' : 'خدمات أخرى ($otherNote)',
                    fmt(other)),
              if (!isUtil && num0(pay['prev_balance']) != 0)
                _kv('رصيد سابق', fmt(num0(pay['prev_balance']))),
              pw.Divider(),
              _kv('إجمالي المستحق', fmt(num0(pay['due_total']))),
              _kv('المبلغ المسدد', fmt(num0(pay['amount'])), strong: true),
              if (!isUtil && newBal != 0)
                _kv(newBal > 0 ? 'المتبقي' : 'رصيد دائن', fmt(newBal.abs())),
            ]),
          ),
          if ((pay['note'] ?? '').toString().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('ملاحظات: ${pay['note']}'),
          ],
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('توقيع المستلم: ..................'),
              pw.Text('ختم: ..................'),
            ],
          ),
        ],
      ),
    ),
  );
  await _show(doc, 'receipt_$no.pdf');
}

// ---------------------------------------------------------
// حساب خاص لعقار واحد
// ---------------------------------------------------------
Future<void> exportAccount(
    Map<String, dynamic> prop, List<Map<String, dynamic>> pays,
    {PdfPageFormat format = PdfPageFormat.a4}) async {
  final doc = await _doc();
  _fs = format.width < PdfPageFormat.a4.width ? 7.5 : 9;
  final totalPaid = pays.fold<double>(0, (s, e) => s + num0(e['amount']));
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(format.width < PdfPageFormat.a4.width ? 20 : 28),
      textDirection: pw.TextDirection.rtl,
      build: (_) => [
        _title('كشف حساب عقار'),
        pw.Text('العقار: ${prop['name'] ?? ''}   (كود ${prop['id']})'),
        pw.SizedBox(height: 3),
        pw.Text('الموقع: ${prop['location'] ?? ''}'),
        pw.SizedBox(height: 3),
        pw.Text('العنوان: ${prop['address'] ?? ''}'),
        pw.SizedBox(height: 3),
        pw.Text('المستأجر: ${prop['tenant_name'] ?? ''}'),
        pw.SizedBox(height: 3),
        pw.Text('الهاتف: ${prop['tenant_phone'] ?? ''}   بديل: ${prop['alt_phone'] ?? ''}'),
        pw.SizedBox(height: 3),
        pw.Text('تاريخ الاستحقاق: ${dueText(prop)}'),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(children: [
            _kv('الإيجار الشهري', fmt(num0(prop['rent_amount']))),
            _kv('مرافق وخدمات حالية', fmt(utilitiesTotal(prop))),
            _kv('رصيد سابق', fmt(num0(prop['balance']))),
            _kv('إجمالي المستحق الآن', fmt(totalDue(prop)), strong: true),
            pw.Divider(),
            _kv('إجمالي المسدد', fmt(totalPaid)),
            _kv('عدد الإيصالات', '${pays.length}'),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Text('سجل المدفوعات',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (pays.isEmpty)
          pw.Text('لا توجد مدفوعات.')
        else
          _table(
            ['رقم الإيصال', 'التاريخ', 'النوع', 'المستحق', 'المسدد', 'المتبقي'],
            pays
                .map((e) => [
                      receiptNo(e),
                      fmtDateStr(e['paid_at']),
                      kindLabel(e['kind']),
                      fmt(num0(e['due_total'])),
                      fmt(num0(e['amount'])),
                      fmt(num0(e['new_balance'])),
                    ])
                .toList(),
          ),
      ],
    ),
  );
  await _show(doc, 'account_${prop['id']}.pdf');
}

// ---------------------------------------------------------
// تقرير مالي مجمع لكل العقارات
// ---------------------------------------------------------
Future<void> exportAll(List<Map<String, dynamic>> props,
    List<Map<String, dynamic>> pays,
    {DateTime? from, DateTime? to, bool allProps = true,
    PdfPageFormat format = PdfPageFormat.a4}) async {
  final doc = await _doc();
  _fs = format.width < PdfPageFormat.a4.width ? 7.5 : 9;
  final paidBy = <int, double>{};
  double totalPaid = 0;
  for (final e in pays) {
    final pid = (e['property_id'] as int?) ?? 0;
    paidBy[pid] = (paidBy[pid] ?? 0) + num0(e['amount']);
    totalPaid += num0(e['amount']);
  }
  double rent = 0, due = 0;
  var late = 0, vacant = 0;
  for (final i in props) {
    rent += num0(i['rent_amount']);
    final es = effStatus(i);
    if (es == 'شاغر') {
      vacant++;
    } else {
      due += totalDue(i);
      if (es == 'متأخرات') late++;
    }
  }
  final rows = props
      .map((i) => [
            '${i['id']}',
            '${i['name'] ?? ''}',
            '${i['tenant_name'] ?? ''}',
            effStatus(i),
            fmt(num0(i['rent_amount'])),
            fmt(totalDue(i)),
            fmt(paidBy[i['id']] ?? 0),
          ])
      .toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(format.width < PdfPageFormat.a4.width ? 20 : 28),
      textDirection: pw.TextDirection.rtl,
      build: (_) => [
        _title('التقرير المالي المجمع'),
        pw.Center(child: pw.Text('بتاريخ ${fmtDate(DateTime.now())}')),
        pw.Center(
            child: pw.Text(
                'الفترة: ${(from == null || to == null) ? 'كل الفترات' : 'من ${fmtDate(from)} إلى ${fmtDate(to)}'}'
                '   •   العقارات: ${allProps ? 'كافة العقارات' : '${props.length} محدد'}')),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(children: [
            _kv('عدد العقارات', '${props.length}'),
            _kv('شاغر / متأخر', '$vacant / $late'),
            _kv('إجمالي الإيجارات الشهرية', fmt(rent)),
            _kv('إجمالي المستحق الآن', fmt(due), strong: true),
            _kv('إجمالي المحصّل (الفترة المحددة)', fmt(totalPaid), strong: true),
            _kv('عدد الإيصالات', '${pays.length}'),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Text('تفاصيل العقارات',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          pw.Text('لا توجد عقارات.')
        else
          _table(
            ['كود', 'العقار', 'المستأجر', 'الحالة', 'الإيجار', 'المستحق', 'المحصّل'],
            rows,
          ),
        pw.SizedBox(height: 14),
        pw.Text('تفاصيل المدفوعات',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (pays.isEmpty)
          pw.Text('لا توجد مدفوعات في الفترة المحددة.')
        else
          _table(
            ['رقم الإيصال', 'التاريخ', 'العقار', 'المستأجر', 'النوع', 'المبلغ'],
            pays
                .map((e) => [
                      receiptNo(e),
                      fmtDateStr(e['paid_at']),
                      '${e['property_name'] ?? ''}',
                      '${e['tenant_name'] ?? ''}',
                      kindLabel(e['kind']),
                      fmt(num0(e['amount'])),
                    ])
                .toList(),
          ),
      ],
    ),
  );
  await _show(doc, 'financial_report.pdf');
}
