import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'security.dart';
import 'utils.dart';

class Fin {
  /// تسجيل سداد. kind: full (إيجار + مرافق) أو utilities (مرافق فقط)
  static Future<Map<String, dynamic>> pay(Map<String, dynamic> prop,
      {required double amount, String kind = 'full', String note = ''}) async {
    final pid = prop['id'] as int;
    final now = DateTime.now();
    final due = parseDue(prop['due_date']);
    final isUtil = kind == 'utilities';
    final prevBal = num0(prop['balance']);
    final dueTotal = isUtil ? utilitiesTotal(prop) : totalDue(prop);
    final newBal = isUtil ? prevBal : dueTotal - amount;
    final no = await DB.nextReceiptNo(pid);

    final row = <String, dynamic>{
      'property_id': pid,
      'property_name': prop['name'],
      'tenant_name': prop['tenant_name'],
      'tenant_phone': phoneOf(prop),
      'kind': kind,
      'receipt_no': no,
      'amount': amount,
      'due_total': dueTotal,
      'prev_balance': prevBal,
      'new_balance': newBal,
      'rent': isUtil ? 0.0 : num0(prop['rent_amount']),
      'electricity': num0(prop['electricity']),
      'water': num0(prop['water']),
      'gas': num0(prop['gas']),
      'other_note': (prop['other_note'] ?? '').toString(),
      'other_amount': num0(prop['other_amount']),
      'paid_at': dateIso(now),
      'period_due': (isUtil || due == null) ? '' : dateIso(due),
      'note': note,
    };
    final id = await DB.insertPayment(row);
    final next = addMonths(due ?? now, 1);

    // تصفير المرافق والخدمات الأخرى عند السداد
    final upd = <String, dynamic>{
      'electricity': 0.0,
      'water': 0.0,
      'gas': 0.0,
      'other_amount': 0.0,
      'other_note': '',
    };
    if (!isUtil) {
      upd['status'] = 'مؤجر';
      upd['balance'] = newBal;
      upd['due_date'] = dateIso(next);
    }
    await DB.update(pid, upd);
    return {...row, 'id': id, 'next_due': dateIso(next)};
  }

  /// حذف سداد. إن كان آخر سداد للعقار تُعاد الأرصدة والمرافق وتاريخ الاستحقاق.
  /// يرجع true إذا تمت إعادة الحساب.
  static Future<bool> deletePayment(Map<String, dynamic> pay) async {
    final pid = pay['property_id'] as int?;
    var reverted = false;
    if (pid != null) {
      final list = await DB.paymentsOf(pid);
      final prop = await DB.property(pid);
      if (list.isNotEmpty && list.first['id'] == pay['id'] && prop != null) {
        final curNote = (prop['other_note'] ?? '').toString();
        final upd = <String, dynamic>{
          'electricity': num0(prop['electricity']) + num0(pay['electricity']),
          'water': num0(prop['water']) + num0(pay['water']),
          'gas': num0(prop['gas']) + num0(pay['gas']),
          'other_amount': num0(prop['other_amount']) + num0(pay['other_amount']),
          'other_note': curNote.isEmpty ? (pay['other_note'] ?? '') : curNote,
        };
        if (pay['kind'] != 'utilities') {
          upd['balance'] = num0(pay['prev_balance']);
          upd['due_date'] = (pay['period_due'] ?? '').toString();
        }
        await DB.update(pid, upd);
        reverted = true;
      }
    }
    await DB.deletePayment(pay['id'] as int);
    return reverted;
  }

  /// تعديل سداد (المبلغ/التاريخ/ملاحظة). إن كان آخر سداد يُعاد حساب الرصيد.
  static Future<bool> editPayment(Map<String, dynamic> pay,
      {required double amount,
      required DateTime date,
      required String note}) async {
    final isUtil = pay['kind'] == 'utilities';
    final newBal = isUtil ? num0(pay['new_balance']) : num0(pay['due_total']) - amount;
    await DB.updatePayment(pay['id'] as int, {
      'amount': amount,
      'paid_at': dateIso(date),
      'note': note,
      'new_balance': newBal,
    });
    final pid = pay['property_id'] as int?;
    if (pid != null && !isUtil) {
      final list = await DB.paymentsOf(pid);
      if (list.isNotEmpty && list.first['id'] == pay['id']) {
        await DB.update(pid, {'balance': newBal});
        return true;
      }
    }
    return false;
  }
}

/// نافذة تسجيل السداد (إيجار ومرافق، أو مرافق فقط). ترجع true عند النجاح.
Future<bool> showPayDialog(BuildContext context, Map<String, dynamic> prop,
    {String kind = 'full'}) async {
  final isUtil = kind == 'utilities';
  final due = isUtil ? utilitiesTotal(prop) : totalDue(prop);
  if (isUtil && due <= 0) {
    toast(context, 'لا توجد مستحقات مرافق');
    return false;
  }
  final ctrl = TextEditingController(text: plain(due));
  var wa = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(isUtil ? 'سداد المرافق' : 'تسجيل سداد الإيجار'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${prop['name']} - ${prop['tenant_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('المستحق: ${fmt(due)}',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                enabled: !isUtil,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: const InputDecoration(labelText: 'المبلغ المسدد (ج.م)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: wa,
                onChanged: (v) => setS(() => wa = v),
                title: const Text('إرسال رسالة شكر عبر واتساب'),
              ),
              Text(
                isUtil
                    ? 'سيتم إصدار إيصال وتصفير قيم المرافق والخدمات الأخرى.'
                    : 'سيتم إصدار إيصال برقم متسلسل، وتحديد الاستحقاق التالي بعد شهر، وتصفير المرافق. لو المبلغ أقل من المستحق يُرحَّل الباقي كرصيد.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد السداد')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final amount = double.tryParse(ctrl.text.trim()) ?? 0;
  if (amount <= 0) {
    toast(context, 'أدخل مبلغاً صحيحاً');
    return false;
  }
  final pay = await Fin.pay(prop, amount: amount, kind: kind);
  if (!context.mounted) return true;
  final no = receiptNo(pay);
  toast(context, 'تم تسجيل السداد - إيصال رقم $no');
  if (wa) {
    final remain = num0(pay['new_balance']);
    final next = isUtil ? '' : ' موعد السداد القادم ${fmtDateStr(pay['next_due'])}.';
    final rest = (!isUtil && remain > 0) ? ' المتبقي ${fmt(remain)}.' : '';
    await launchWa(
      context,
      phoneOf(prop),
      'شكراً لك ${prop['tenant_name']}، تم استلام مبلغ ${fmt(amount)} الخاص بـ ${prop['name']} بنجاح (إيصال رقم $no).$rest$next',
    );
  }
  return true;
}

/// تعديل سداد
Future<bool> showEditPaymentDialog(
    BuildContext context, Map<String, dynamic> pay) async {
  final isUtil = pay['kind'] == 'utilities';
  final amountCtrl = TextEditingController(text: plain(num0(pay['amount'])));
  final noteCtrl = TextEditingController(text: (pay['note'] ?? '').toString());
  var date = DateTime.tryParse((pay['paid_at'] ?? '').toString()) ?? DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('تعديل السداد ${receiptNo(pay)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                enabled: !isUtil,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: const InputDecoration(labelText: 'المبلغ المسدد'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setS(() => date = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'تاريخ السداد'),
                  child: Text(fmtDate(date)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
  if (amount <= 0) {
    toast(context, 'أدخل مبلغاً صحيحاً');
    return false;
  }
  if (!await confirmAction(context,
      title: 'تأكيد تعديل السداد',
      message: 'حفظ التعديل على الإيصال ${receiptNo(pay)}؟')) {
    return false;
  }
  if (!context.mounted) return false;
  final recalculated = await Fin.editPayment(pay,
      amount: amount, date: date, note: noteCtrl.text.trim());
  toast(
      context,
      recalculated
          ? 'تم التعديل وإعادة حساب الرصيد'
          : 'تم التعديل (سداد سابق: رصيد العقار الحالي لم يتغير)');
  return true;
}

/// حذف سداد بعد التأكيد
Future<bool> confirmDeletePayment(
    BuildContext context, Map<String, dynamic> pay) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حذف السداد'),
      content: Text(
          'حذف الإيصال ${receiptNo(pay)} بمبلغ ${fmt(num0(pay['amount']))}؟\nلو كان آخر سداد للعقار ستُعاد المرافق والرصيد وتاريخ الاستحقاق لما قبله.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  if (!await biometricAuth(context, 'تأكيد حذف السداد')) return false;
  final reverted = await Fin.deletePayment(pay);
  toast(
      context,
      reverted
          ? 'تم الحذف وإعادة حساب الأرصدة'
          : 'تم الحذف (سداد سابق: رصيد العقار الحالي لم يتغير)');
  return true;
}
