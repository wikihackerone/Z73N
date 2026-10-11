import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'db.dart';
import 'utils.dart';

final LocalAuthentication _localAuth = LocalAuthentication();

/// طلب بصمة الهاتف (أو قفل الجهاز كبديل). يرجع true عند النجاح.
/// إن لم يكن في الهاتف أي قفل/بصمة مفعّلة يُكتفى برسالة التأكيد حتى لا يتعطل التطبيق.
Future<bool> biometricAuth(BuildContext context, String reason) async {
  var supported = false;
  try {
    supported = await _localAuth.isDeviceSupported();
  } catch (_) {}
  if (!supported) return true;
  try {
    final ok = await _localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
    );
    if (!ok && context.mounted) toast(context, 'لم يتم التحقق من البصمة، أُلغيت العملية');
    return ok;
  } on PlatformException catch (e) {
    if (e.code == 'NotEnrolled' ||
        e.code == 'PasscodeNotSet' ||
        e.code == 'NotAvailable') {
      return true; // لا توجد بصمة/قفل على الهاتف
    }
    if (context.mounted) toast(context, 'تعذر التحقق من البصمة، أُلغيت العملية');
    return false;
  } catch (_) {
    if (context.mounted) toast(context, 'تعذر التحقق من البصمة، أُلغيت العملية');
    return false;
  }
}

/// رسالة تأكيد ثم طلب البصمة. ترجع true فقط إذا أكّد المستخدم ونجحت البصمة.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = 'تأكيد',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
          child: Text(okLabel),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return biometricAuth(context, title);
}

// ---------------------------------------------------------
// أسئلة الأمان (استعادة كلمة السر)
// ---------------------------------------------------------
const kSecurityQuestions = [
  'ما اسم أول مدرسة التحقت بها؟',
  'ما اسم المدينة التي وُلدت فيها والدتك؟',
  'ما اسم أقرب صديق لك في الطفولة؟',
  'ما اسم أول حيوان أليف امتلكته؟',
  'ما هو طبقك المفضل؟',
  'ما اسم الشارع الذي نشأت فيه؟',
];

/// توحيد الإجابة حتى لا تفشل بسبب التشكيل أو اختلاف شكل الألف/الياء/التاء المربوطة
String normAnswer(String s) {
  var t = s.trim().toLowerCase();
  t = t.replaceAll(RegExp('[ً-ٰٟـ]'), '');
  t = t
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < ar.length; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

String _ansHash(String salt, int qid, String answer) =>
    hashPw(salt, 'sq$qid:${normAnswer(answer)}');

bool hasSecurityQuestions(Map<String, dynamic>? u) =>
    u != null && u['sq1_id'] != null && u['sq2_id'] != null && u['sq_salt'] != null;

Future<void> saveSecurityAnswers(
    int userId, int q1, String a1, int q2, String a2) async {
  final salt = newSalt();
  await DB.updateUser(userId, {
    'sq_salt': salt,
    'sq1_id': q1,
    'sq1_hash': _ansHash(salt, q1, a1),
    'sq2_id': q2,
    'sq2_hash': _ansHash(salt, q2, a2),
  });
}

bool verifySecurityAnswers(Map<String, dynamic> u, String a1, String a2) {
  if (!hasSecurityQuestions(u)) return false;
  final salt = u['sq_salt'].toString();
  return _ansHash(salt, u['sq1_id'] as int, a1) == u['sq1_hash'] &&
      _ansHash(salt, u['sq2_id'] as int, a2) == u['sq2_hash'];
}

/// نافذة إعداد أسئلة الأمان (اختيار سؤالين من 6). ترجع true عند الحفظ.
Future<bool> showSecuritySetupDialog(
    BuildContext context, Map<String, dynamic> user) async {
  int? q1 = user['sq1_id'] as int?;
  int? q2 = user['sq2_id'] as int?;
  final a1 = TextEditingController();
  final a2 = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        DropdownButtonFormField<int> dd(String label, int? v, int? other,
                void Function(int?) on) =>
            DropdownButtonFormField<int>(
              value: v,
              isExpanded: true,
              items: [
                for (var i = 0; i < kSecurityQuestions.length; i++)
                  if (i != other)
                    DropdownMenuItem(
                        value: i,
                        child: Text(kSecurityQuestions[i],
                            overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (x) => setS(() => on(x)),
              decoration: InputDecoration(labelText: label),
            );
        return AlertDialog(
          title: const Text('أسئلة الأمان'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'اختر سؤالين من 6 أسئلة وأجب عنهما. تُستخدم الإجابات لاستعادة كلمة السر إذا نسيتها.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 12),
                dd('السؤال الأول', q1, q2, (x) => q1 = x),
                const SizedBox(height: 8),
                TextField(
                    controller: a1,
                    decoration: const InputDecoration(labelText: 'الإجابة الأولى')),
                const SizedBox(height: 14),
                dd('السؤال الثاني', q2, q1, (x) => q2 = x),
                const SizedBox(height: 8),
                TextField(
                    controller: a2,
                    decoration: const InputDecoration(labelText: 'الإجابة الثانية')),
                if (err != null) ...[
                  const SizedBox(height: 10),
                  Text(err!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (q1 == null || q2 == null) {
                  setS(() => err = 'اختر سؤالين');
                  return;
                }
                if (normAnswer(a1.text).length < 2 || normAnswer(a2.text).length < 2) {
                  setS(() => err = 'اكتب إجابة لكل سؤال (حرفان على الأقل)');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return false;
  if (!await biometricAuth(context, 'تأكيد حفظ أسئلة الأمان')) return false;
  await saveSecurityAnswers(user['id'] as int, q1!, a1.text, q2!, a2.text);
  return true;
}

// ---------------------------------------------------------
// شاشة استعادة كلمة السر
// ---------------------------------------------------------
class ForgotPasswordScreen extends StatefulWidget {
  final String initialUser;
  const ForgotPasswordScreen({super.key, this.initialUser = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _user =
      TextEditingController(text: widget.initialUser);
  final _a1 = TextEditingController();
  final _a2 = TextEditingController();
  final _np = TextEditingController();
  final _np2 = TextEditingController();
  Map<String, dynamic>? _u;
  String? _error;
  int _fails = 0;

  Future<void> _next() async {
    final u = await DB.userByName(_user.text.trim());
    if (u == null) {
      setState(() => _error = 'اسم المستخدم غير موجود');
      return;
    }
    if (!hasSecurityQuestions(u)) {
      setState(() => _error =
          'لم تُضبط أسئلة الأمان لهذا الحساب. يمكن ضبطها من الإعدادات بعد تسجيل الدخول.');
      return;
    }
    setState(() {
      _u = u;
      _error = null;
    });
  }

  Future<void> _reset() async {
    final u = _u!;
    if (_np.text.length < 4) {
      setState(() => _error = 'كلمة المرور 4 أحرف على الأقل');
      return;
    }
    if (_np.text != _np2.text) {
      setState(() => _error = 'تأكيد كلمة المرور غير مطابق');
      return;
    }
    if (!verifySecurityAnswers(u, _a1.text, _a2.text)) {
      _fails++;
      if (_fails >= 5) {
        if (mounted) {
          toast(context, 'محاولات كثيرة خاطئة، حاول لاحقاً');
          Navigator.pop(context);
        }
        return;
      }
      setState(() => _error = 'الإجابات غير صحيحة (المحاولة $_fails من 5)');
      return;
    }
    final salt = newSalt();
    await DB.updateUser(u['id'] as int, {
      'salt': salt,
      'pass_hash': hashPw(salt, _np.text),
      'must_change': 0,
    });
    if (!mounted) return;
    toast(context, 'تم تغيير كلمة المرور، سجّل الدخول بها');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (u == null) ...[
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                  labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _next, child: const Text('التالي')),
          ] else ...[
            Text('الحساب: ${u['display_name']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(kSecurityQuestions[u['sq1_id'] as int],
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
                controller: _a1,
                decoration: const InputDecoration(labelText: 'الإجابة')),
            const SizedBox(height: 16),
            Text(kSecurityQuestions[u['sq2_id'] as int],
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
                controller: _a2,
                decoration: const InputDecoration(labelText: 'الإجابة')),
            const SizedBox(height: 16),
            TextField(
                controller: _np,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
            const SizedBox(height: 10),
            TextField(
                controller: _np2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reset, child: const Text('تغيير كلمة المرور')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
