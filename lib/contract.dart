import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'security.dart';
import 'utils.dart';

/// نافذة تجديد العقد بتاريخ جديد. ترجع true عند نجاح التجديد.
Future<bool> showRenewDialog(
    BuildContext context, Map<String, dynamic> prop) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final oldEnd = contractEndOf(prop);

  // العقد الجديد يبدأ من نهاية القديم (إن لم ينتهِ بعد)، وإلا من اليوم
  var start = (oldEnd != null &&
          !DateTime(oldEnd.year, oldEnd.month, oldEnd.day).isBefore(today))
      ? DateTime(oldEnd.year, oldEnd.month, oldEnd.day)
      : today;
  final oldMonths = (prop['contract_months'] as num?)?.toInt() ?? 0;
  final monthsC = TextEditingController(text: '${oldMonths > 0 ? oldMonths : 12}');
  final rentC = TextEditingController(text: plain(num0(prop['rent_amount'])));
  var sendMsg = phoneOf(prop).isNotEmpty;
  String? pendingMsg;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final m = int.tryParse(monthsC.text.trim());
        final validM = m != null && m >= 1 && m <= 120;
        final end = validM ? addMonths(start, m) : null;
        return AlertDialog(
          title: const Text('تجديد العقد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${prop['name'] ?? ''} - ${prop['tenant_name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('العقد الحالي: ${oldEnd == null ? 'غير محدد' : contractText(prop)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime(now.year - 5),
                      lastDate: DateTime(now.year + 15),
                    );
                    if (picked != null) setS(() => start = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'تاريخ بداية العقد الجديد',
                        prefixIcon: Icon(Icons.event_available_outlined)),
                    child: Text(fmtDate(start)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: monthsC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                      labelText: 'مدة العقد الجديد',
                      suffixText: 'شهر',
                      prefixIcon: Icon(Icons.timelapse)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final x in const [6, 12, 24, 36])
                      ChoiceChip(
                        label: Text(x == 12
                            ? 'سنة'
                            : x == 24
                                ? 'سنتان'
                                : x == 36
                                    ? '3 سنوات'
                                    : '$x أشهر'),
                        selected: m == x,
                        onSelected: (_) => setS(() => monthsC.text = '$x'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    end == null
                        ? 'اكتب مدة صحيحة من 1 إلى 120 شهراً'
                        : 'ينتهي العقد الجديد في: ${fmtDate(end)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rentC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration: const InputDecoration(
                      labelText: 'الإيجار الشهري بعد التجديد',
                      helperText: 'عدّله إن تغيّرت القيمة، أو اتركه كما هو',
                      prefixIcon: Icon(Icons.payments_outlined)),
                ),
                CheckboxListTile(
                  value: sendMsg,
                  onChanged: (v) => setS(() => sendMsg = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('إرسال رسالة واتساب للمستأجر بقيمة العقد الجديد'),
                  subtitle: phoneOf(prop).isEmpty
                      ? const Text('لا يوجد رقم هاتف مسجل')
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton.icon(
              onPressed: end == null
                  ? null
                  : () async {
                      // تجديد العقد يحتاج تأكيد بصمة بيومترك
                      final authed = await biometricAuth(ctx, 'تأكيد تجديد العقد');
                      if (!authed || !ctx.mounted) return;
                      final rent = double.tryParse(rentC.text.trim());
                      await DB.renewContract(prop['id'] as int,
                          start: start, months: m!, end: end, rent: rent);
                      if (sendMsg) {
                        pendingMsg = contractMessage(prop,
                            rent: rent ?? num0(prop['rent_amount']),
                            start: start,
                            end: end,
                            renewed: true);
                      }
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              icon: const Icon(Icons.autorenew),
              label: const Text('تجديد العقد'),
            ),
          ],
        );
      },
    ),
  );
  if (ok == true && context.mounted) {
    toast(context, 'تم تجديد العقد');
  }
  if (ok == true && pendingMsg != null && context.mounted) {
    await launchWa(context, phoneOf(prop), pendingMsg!);
  }
  return ok == true;
}

/// نافذة تعديل القيم الإيجارية وإرسال رسالة واتساب بها للمستأجر.
/// ترجع true إن تم حفظ القيم الجديدة في العقار.
Future<bool> showContractMessageDialog(
    BuildContext context, Map<String, dynamic> prop) async {
  final oldRent = num0(prop['rent_amount']);
  final rentC = TextEditingController(text: plain(oldRent));
  final elecC = TextEditingController(text: plain(num0(prop['electricity'])));
  final waterC = TextEditingController(text: plain(num0(prop['water'])));
  final gasC = TextEditingController(text: plain(num0(prop['gas'])));
  final msgC = TextEditingController();
  final start = contractStartOf(prop);
  final end = contractEndOf(prop);
  var edited = false;
  var save = true;
  var saved = false;
  String? sendText;

  double? val(TextEditingController c) => double.tryParse(c.text.trim());

  String build() => contractMessage(
        prop,
        rent: val(rentC) ?? oldRent,
        start: start,
        end: end,
        electricity: val(elecC),
        water: val(waterC),
        gas: val(gasC),
      );
  msgC.text = build();

  Widget numField(StateSetter setS, TextEditingController c, String label,
      IconData icon, {String? error}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: (_) => setS(() {
        if (!edited) msgC.text = build();
      }),
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        prefixIcon: Icon(icon),
        isDense: true,
      ),
    );
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final rentOk = val(rentC) != null;
        return AlertDialog(
          title: const Text('رسالة بالقيمة الإيجارية الجديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${prop['name'] ?? ''} - ${prop['tenant_name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('الإيجار الحالي: ${fmt(oldRent)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 12),
                numField(setS, rentC, 'الإيجار الشهري الجديد',
                    Icons.payments_outlined,
                    error: rentOk ? null : 'اكتب قيمة صحيحة'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: numField(
                            setS, elecC, 'كهرباء', Icons.bolt_outlined)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: numField(
                            setS, waterC, 'مياه', Icons.water_drop_outlined)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: numField(setS, gasC, 'غاز',
                            Icons.local_fire_department_outlined)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgC,
                  minLines: 5,
                  maxLines: 9,
                  onChanged: (_) => edited = true,
                  decoration: const InputDecoration(
                      labelText: 'نص الرسالة (يمكن تعديله)'),
                ),
                if (edited)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setS(() {
                        edited = false;
                        msgC.text = build();
                      }),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('إعادة الصياغة تلقائياً'),
                    ),
                  ),
                CheckboxListTile(
                  value: save,
                  onChanged: (v) => setS(() => save = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('حفظ القيم الجديدة في بيانات العقار'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton.icon(
              onPressed: !rentOk
                  ? null
                  : () async {
                      if (save) {
                        await DB.update(prop['id'] as int, {
                          'rent_amount': val(rentC),
                          'electricity': val(elecC) ?? num0(prop['electricity']),
                          'water': val(waterC) ?? num0(prop['water']),
                          'gas': val(gasC) ?? num0(prop['gas']),
                        });
                        saved = true;
                      }
                      sendText = msgC.text.trim();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              icon: const Icon(Icons.chat),
              label: const Text('إرسال واتساب'),
            ),
          ],
        );
      },
    ),
  );
  if (saved && context.mounted) toast(context, 'تم حفظ القيم الجديدة');
  if (sendText != null && sendText!.isNotEmpty && context.mounted) {
    await launchWa(context, phoneOf(prop), sendText!);
  }
  return saved;
}
