import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

/// إعدادات عامة (تُحمَّل من قاعدة البيانات عند التشغيل)
int soonDays = 3;
String companyName = '';

const kStatuses = ['مؤجر', 'شاغر', 'متأخرات'];

/// أنواع العقار: كل نوع له شعار (أيقونة) يظهر في النموذج وفي قائمة العقارات
const kPropertyTypes = <String, ({String label, IconData icon})>{
  'apartment': (label: 'شقة', icon: Icons.apartment),
  'shop': (label: 'محل', icon: Icons.storefront),
  'factory': (label: 'مصنع', icon: Icons.factory),
};

IconData propertyTypeIcon(dynamic t) =>
    (kPropertyTypes[t] ?? kPropertyTypes['apartment']!).icon;
String propertyTypeLabel(dynamic t) =>
    (kPropertyTypes[t] ?? kPropertyTypes['apartment']!).label;
const int kMaxImages = 20;

final _money = intl.NumberFormat('#,##0.##');
String fmt(num v) => '${_money.format(v)} ج.م';

Color statusColor(String? s) {
  switch (s) {
    case 'مؤجر':
      return const Color(0xFF2E7D32);
    case 'متأخرات':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFFEF6C00);
  }
}

double num0(dynamic v) => (v is num) ? v.toDouble() : 0.0;

String plain(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String dateIso(DateTime d) => intl.DateFormat('yyyy-MM-dd').format(d);
String fmtDate(DateTime d) => intl.DateFormat('yyyy/MM/dd').format(d);
String fmtDateStr(dynamic s) {
  final d = DateTime.tryParse((s ?? '').toString());
  return d == null ? '' : fmtDate(d);
}

String receiptNo(Map<String, dynamic> pay) =>
    (pay['receipt_no'] ?? pay['id'] ?? '').toString();

String kindLabel(dynamic k) => k == 'utilities' ? 'مرافق' : 'إيجار ومرافق';

DateTime? parseDue(dynamic v) {
  if (v == null) return null;
  final t = v.toString();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t);
}

DateTime addMonths(DateTime d, int n) {
  final y = d.year + ((d.month - 1 + n) ~/ 12);
  final m = (d.month - 1 + n) % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > last ? last : d.day);
}

int? daysUntilDue(Map<String, dynamic> i) {
  final d = parseDue(i['due_date']);
  if (d == null) return null;
  final t = DateTime.now();
  return DateTime(d.year, d.month, d.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
}

// ---------------- العقود ----------------
/// قبل انتهاء العقد بكم شهر يبدأ التنبيه
const int kContractAlertMonths = 2;

DateTime? contractEndOf(Map<String, dynamic> i) => parseDue(i['contract_end']);
DateTime? contractStartOf(Map<String, dynamic> i) => parseDue(i['contract_start']);

/// الأيام المتبقية على انتهاء العقد (سالب = انتهى)
int? contractDaysLeft(Map<String, dynamic> i) {
  final e = contractEndOf(i);
  if (e == null) return null;
  final t = DateTime.now();
  return DateTime(e.year, e.month, e.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
}

/// هل دخل العقد فترة التنبيه (قبل الانتهاء بشهرين) أو انتهى؟
bool contractNeedsAlert(Map<String, dynamic> i) {
  if (i['status'] == 'شاغر') return false;
  final e = contractEndOf(i);
  if (e == null) return false;
  final t = DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final from = addMonths(DateTime(e.year, e.month, e.day), -kContractAlertMonths);
  return !today.isBefore(from);
}

String contractText(Map<String, dynamic> i) {
  final e = contractEndOf(i);
  final n = contractDaysLeft(i);
  if (e == null || n == null) return 'غير محدد';
  if (n < 0) return '${fmtDate(e)} (انتهى منذ ${-n} يوم)';
  if (n == 0) return '${fmtDate(e)} (ينتهي اليوم)';
  return '${fmtDate(e)} (متبقي $n يوم)';
}

List<Map<String, dynamic>> computeContractAlerts(List<Map<String, dynamic>> items) {
  final list = items.where(contractNeedsAlert).toList();
  list.sort((a, b) =>
      (contractDaysLeft(a) ?? 0).compareTo(contractDaysLeft(b) ?? 0));
  return list;
}

String effStatus(Map<String, dynamic> i) {
  if (i['status'] == 'شاغر') return 'شاغر';
  if (i['status'] == 'متأخرات') return 'متأخرات';
  final d = daysUntilDue(i);
  if (d != null && d < 0) return 'متأخرات';
  return 'مؤجر';
}

String dueText(Map<String, dynamic> i) {
  final d = parseDue(i['due_date']);
  final n = daysUntilDue(i);
  if (d == null || n == null) return 'غير محدد';
  if (n < 0) return '${fmtDate(d)} (متأخر ${-n} يوم)';
  if (n == 0) return '${fmtDate(d)} (اليوم)';
  return '${fmtDate(d)} (بعد $n يوم)';
}

/// مرافق + خدمات أخرى
double utilitiesTotal(Map<String, dynamic> i) =>
    num0(i['electricity']) +
    num0(i['water']) +
    num0(i['gas']) +
    num0(i['other_amount']);

/// إجمالي المستحق = إيجار + مرافق + خدمات أخرى + رصيد سابق
double totalDue(Map<String, dynamic> i) =>
    num0(i['rent_amount']) + utilitiesTotal(i) + num0(i['balance']);

String phoneOf(Map<String, dynamic> i) {
  final a = (i['tenant_phone'] ?? '').toString().trim();
  if (a.isNotEmpty) return a;
  return (i['alt_phone'] ?? '').toString().trim();
}

/// العقارات التي عليها تنبيه (متأخرة أو قريبة الاستحقاق)
List<Map<String, dynamic>> computeAlerts(List<Map<String, dynamic>> items) {
  final list = <Map<String, dynamic>>[];
  for (final i in items) {
    if (i['status'] == 'شاغر') continue;
    final d = daysUntilDue(i);
    if (d == null) {
      if (i['status'] == 'متأخرات') list.add(i);
    } else if (d <= soonDays) {
      list.add(i);
    }
  }
  list.sort((a, b) =>
      (daysUntilDue(a) ?? -9999).compareTo(daysUntilDue(b) ?? -9999));
  return list;
}

void toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
}

/// يحوّل رقماً مكتوباً إلى صيغة دولية بالأرقام فقط. مفتاح مصر (20) افتراضي:
/// 01012345678 / 1012345678 / 201012345678 / +201012345678 => 201012345678
/// الأرقام الدولية الأخرى: تبدأ بـ + أو 00 (أو تكون أطول من 10 أرقام بمفتاح دولة).
String normalizePhone(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  final intl0 = t.startsWith('+') || t.startsWith('00');
  var d = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return '';
  if (intl0) return d.startsWith('00') ? d.substring(2) : d;
  if (d.startsWith('0')) return '20${d.substring(1)}';
  if (d.startsWith('20') && d.length >= 11) return d;
  if (d.length >= 11) return d; // رقم مخزّن مسبقاً بمفتاح دولة آخر
  return '20$d';
}

/// ما يظهر في خانة الإدخال (المفتاح +20 ثابت قبلها): الرقم بدون 20
String phoneForInput(dynamic stored) {
  final d = (stored ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('20') && d.length >= 11) return d.substring(2);
  if (d.startsWith('0')) return d.substring(1);
  if (d.length >= 11) return '+$d';
  return d;
}

Future<void> launchWa(BuildContext context, String phone, String msg) async {
  final clean = normalizePhone(phone);
  if (clean.isEmpty) {
    toast(context, 'رقم الهاتف غير مسجل');
    return;
  }
  final url = Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(msg)}');
  try {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) toast(context, 'تعذر فتح WhatsApp');
  } catch (_) {
    toast(context, 'تعذر فتح WhatsApp');
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final Clip clipBehavior;
  const AppCard({super.key, required this.child, this.clipBehavior = Clip.none});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        clipBehavior: clipBehavior,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black.withAlpha(15)),
        ),
        child: child,
      );
}

// ---------------- عدّادات الأيام + رسالة العقد ----------------
/// الرقم الكبير في عدّاد الأيام ("—" إن لم يُحدد، "اليوم" إن كان 0)
String counterBig(int? n) => n == null ? '—' : (n == 0 ? 'اليوم' : '${n.abs()}');

/// الوصف الصغير تحت الرقم
String counterCaption(int? n, {required bool contract}) {
  if (n == null) return 'غير محدد';
  if (n == 0) return contract ? 'ينتهي العقد' : 'يستحق الإيجار';
  if (n > 0) return 'يوم متبقي';
  return contract ? 'يوم منذ الانتهاء' : 'يوم تأخير';
}

/// لون عدّاد الإيجار: أحمر متأخر - برتقالي قريب - أخضر مطمئن
Color rentCounterColor(int? n) {
  if (n == null) return Colors.blueGrey;
  if (n < 0) return const Color(0xFFC62828);
  if (n <= soonDays) return const Color(0xFFEF6C00);
  return const Color(0xFF2E7D32);
}

/// لون عدّاد العقد: أحمر منتهي - برتقالي داخل فترة الشهرين - أخضر مطمئن
Color contractCounterColor(Map<String, dynamic> i) {
  final n = contractDaysLeft(i);
  if (n == null) return Colors.blueGrey;
  if (n < 0) return const Color(0xFFC62828);
  if (contractNeedsAlert(i)) return const Color(0xFFEF6C00);
  return const Color(0xFF2E7D32);
}

/// نص رسالة واتساب بقيمة العقد/الإيجار الجديدة.
/// القيم القديمة تؤخذ من [prop] ويُذكر فقط ما تغيّر منها.
String contractMessage(
  Map<String, dynamic> prop, {
  required double rent,
  DateTime? start,
  DateTime? end,
  double? electricity,
  double? water,
  double? gas,
  bool renewed = false,
}) {
  final t = (prop['tenant_name'] ?? '').toString();
  final n = (prop['name'] ?? '').toString();
  final oldRent = num0(prop['rent_amount']);
  final b = StringBuffer('أهلاً $t،\n');
  b.writeln(renewed
      ? 'تم تجديد عقد إيجار $n بالبيانات التالية:'
      : 'نود إحاطتكم بالقيم المحدّثة لعقد إيجار $n:');
  if (start != null) b.writeln('• بداية العقد: ${fmtDate(start)}');
  if (end != null) b.writeln('• نهاية العقد: ${fmtDate(end)}');
  b.write('• الإيجار الشهري الجديد: ${fmt(rent)}');
  if (oldRent > 0 && (rent - oldRent).abs() > 0.001) {
    b.write(' (بدلاً من ${fmt(oldRent)})');
  }
  b.writeln();
  void extra(String label, double? now, dynamic old) {
    if (now == null) return;
    if ((now - num0(old)).abs() > 0.001) {
      b.writeln('• $label: ${fmt(now)}');
    }
  }

  extra('الكهرباء', electricity, prop['electricity']);
  extra('المياه', water, prop['water']);
  extra('الغاز', gas, prop['gas']);
  b.write('شكراً لتعاملكم معنا.');
  return b.toString();
}
