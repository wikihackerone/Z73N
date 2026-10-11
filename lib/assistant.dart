import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'ai_brain.dart';
import 'db.dart';
import 'utils.dart';

// =========================================================
// المساعد المالي الذكي
// يعمل بالكامل على الهاتف (بدون إنترنت): يفهم أسئلتك بالعربي
// ويحسب الإجابة من بيانات العقارات والمدفوعات المسجلة.
// =========================================================

/// سطر في بطاقة نتيجة (مستأجر / عقار)
class _Row {
  final String title;
  final String subtitle;
  final String amount;
  final Color color;
  final Map<String, dynamic>? prop; // لإرسال واتساب
  final String? waMsg;
  const _Row(this.title, this.subtitle, this.amount, this.color, {this.prop, this.waMsg});
}

class _Msg {
  final bool mine;
  final String text;
  final List<_Row> rows;
  final List<String> images; // صور مرفقة (بطاقة / عقد) من ملفات الهاتف
  final List<String> suggestions; // أسئلة مقترحة تُرسل بلمسة
  const _Msg(this.mine, this.text,
      [this.rows = const [], this.images = const [], this.suggestions = const []]);
}

/// توحيد النص العربي للمقارنة (همزات/تشكيل/تاء مربوطة...)
String _norm(String s) {
  var t = s.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'[ً-ْـ]'), '');
  t = t
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

bool _has(String q, List<String> words) => words.any((w) => q.contains(_norm(w)));

const _kUnknown =
    'مش متأكد فهمت سؤالك 🤔\nممكن تسألني مثلاً:\n• مين عليه فلوس؟\n• كام اتحصّل الشهر ده؟\n• مين هيستحق قريب؟\n• العقود اللي هتنتهي\n• بطاقة أحمد / عقد أحمد (أبعتلك الصور)\n• أو اكتب اسم مستأجر أو عقار عشان أعرض حسابه.\n\n(تقدر تفعّل «الفهم الذكي» من أيقونة 🧠 فوق عشان أفهم صياغات أكتر.)';

/// أوامر النموذج الذكي ← جملة عربية يفهمها المساعد مباشرة
const _kCommands = {
  'DEBTORS': 'مين عليه فلوس',
  'UPCOMING': 'مين هيستحق قريب',
  'COLLECTED_MONTH': 'كام اتحصل الشهر ده',
  'COLLECTED_LAST': 'كام اتحصل الشهر الماضي',
  'COLLECTED_YEAR': 'كام اتحصل السنة',
  'VACANT': 'العقارات الشاغرة',
  'CONTRACTS_EXPIRING': 'العقود اللي هتنتهي',
  'CREDITS': 'مين ليه رصيد دائن',
  'LAST_PAYMENTS': 'آخر الإيصالات',
  'SUMMARY': 'ملخص عام',
};

class _Engine {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> pays;
  _Engine(this.items, this.pays);

  List<Map<String, dynamic>> get _active =>
      items.where((i) => i['status'] != 'شاغر').toList();

  double _paidIn(DateTime from, DateTime to) {
    var sum = 0.0;
    for (final p in pays) {
      final d = DateTime.tryParse((p['paid_at'] ?? '').toString());
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(from) && !day.isAfter(to)) sum += num0(p['amount']);
    }
    return sum;
  }

  String _reminder(Map<String, dynamic> i) =>
      'أهلاً ${i['tenant_name'] ?? ''}، نود تذكيركم بأن المستحق على ${i['name'] ?? 'العقار'} '
      'هو ${fmt(totalDue(i))}. برجاء السداد في أقرب وقت. شكراً لتعاونكم.';

  List<Map<String, dynamic>> _findHit(String q) {
    const stop = {'شقه', 'محل', 'مصنع', 'عقار', 'الدور', 'رقم', 'مين', 'كام'};
    final qTokens = q.split(' ').where((w) => w.length >= 3).toSet();
    bool nameHit(String raw) {
      final n = _norm(raw);
      if (n.length < 3) return false;
      if (' $q '.contains(' $n ')) return true;
      return n
          .split(' ')
          .any((w) => w.length >= 3 && !stop.contains(w) && qTokens.contains(w));
    }

    return items
        .where((i) => nameHit('${i['name'] ?? ''}') || nameHit('${i['tenant_name'] ?? ''}'))
        .toList();
  }

  /// بطاقة المستأجر / صور العقد: يرجع null إن لم يكن السؤال عنها
  Future<List<_Msg>?> _docs(String raw) async {
    final q = _norm(raw);
    final wantsId = _has(q, ['بطاقه', 'بطاقة', 'هويه', 'هوية', 'قومي', 'كارنيه']);
    final wantsContract = _has(q, ['عقد', 'عقود']) &&
        !_has(q, ['ينتهي', 'هتنتهي', 'هينتهي', 'انتهاء', 'قارب', 'تجديد']);
    if (!wantsId && !wantsContract) return null;

    final hit = _findHit(q);
    if (hit.isEmpty) {
      // ما ذُكر اسم: اعرض أسماء المستأجرين ليختار
      if (wantsId) {
        final names = _active
            .map((i) => '${i['tenant_name'] ?? ''}'.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .take(8)
            .toList();
        return [
          _Msg(false, 'بطاقة مين؟ اكتب اسم المستأجر أو اختار من هنا:', const [],
              const [], [for (final n in names) 'بطاقة $n'])
        ];
      }
      return null; // سؤال عام عن العقود → القائمة العادية
    }

    final out = <_Msg>[];
    for (final i in hit.take(3)) {
      final pid = i['id'] as int;
      final who = '${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}';
      Future<void> add(String kind, String label) async {
        final all = await DB.attachments(pid, kind);
        final ok = all.where((e) => File(e).existsSync()).toList();
        if (ok.isEmpty) {
          out.add(_Msg(false, 'مفيش صور $label مسجلة لـ $who.'));
        } else {
          out.add(_Msg(false, '$label $who (${ok.length} صورة):', const [], ok));
        }
      }

      if (wantsId) await add('id', 'بطاقة');
      if (wantsContract) {
        final e = contractEndOf(i);
        if (e != null) {
          out.add(_Msg(false, 'العقد ينتهي: ${contractText(i)}'));
        }
        await add('contract', 'عقد');
      }
    }
    return out;
  }

  Future<List<_Msg>> answerAsync(String raw) async =>
      await _docs(raw) ?? [answer(raw)];

  _Msg answer(String raw) {
    final q = _norm(raw);

    // 1) سؤال عن مستأجر/عقار بعينه
    final hit = _findHit(q);
    if (hit.isNotEmpty) return _single(hit);

    // 2) من عليه فلوس
    if (_has(q, ['عليه', 'عليهم', 'مديون', 'ديون', 'متاخر', 'متأخر', 'مستحق', 'مين لسه', 'ما دفع', 'مدفعش', 'باقي', 'متبقي', 'يدين'])) {
      return _debtors();
    }
    // 3) قرب الاستحقاق
    if (_has(q, ['قريب', 'هيستحق', 'قادم', 'الايام الجايه', 'الأيام الجاية', 'استحقاق'])) {
      return _upcoming();
    }
    // 4) المحصّل
    if (_has(q, ['محصل', 'تحصيل', 'حصلنا', 'اتدفع', 'اتحصل', 'ايراد', 'إيراد', 'دخل', 'مدفوعات', 'كام دفعوا', 'دفعوا'])) {
      return _collected(q);
    }
    // 5) شاغر
    if (_has(q, ['شاغر', 'فاضي', 'فاضيه', 'غير مؤجر'])) return _vacant();
    // 6) العقود
    if (_has(q, ['عقد', 'عقود', 'ينتهي', 'تجديد', 'انتهاء'])) return _contracts();
    // 7) رصيد دائن
    if (_has(q, ['دائن', 'زياده', 'زيادة', 'دافع زياده', 'مقدم'])) return _credits();
    // 8) آخر الإيصالات
    if (_has(q, ['اخر', 'آخر', 'اخير', 'ايصال', 'إيصال', 'ايصالات'])) return _lastPays();
    // 9) ملخص
    if (_has(q, ['ملخص', 'وضع', 'حال', 'تقرير', 'نظره', 'نظرة', 'احصائيات', 'اجمالي', 'إجمالي', 'اهلا', 'ازيك', 'مرحبا', 'السلام'])) {
      return summary();
    }
    return const _Msg(false, _kUnknown);
  }

  // ---------- مين عليه فلوس ----------
  _Msg _debtors() {
    final late = <Map<String, dynamic>>[];
    final withBal = <Map<String, dynamic>>[];
    for (final i in _active) {
      if (effStatus(i) == 'متأخرات') {
        late.add(i);
      } else if (num0(i['balance']) > 0.001) {
        withBal.add(i);
      }
    }
    late.sort((a, b) => totalDue(b).compareTo(totalDue(a)));
    withBal.sort((a, b) => num0(b['balance']).compareTo(num0(a['balance'])));
    if (late.isEmpty && withBal.isEmpty) {
      return const _Msg(false, 'ممتاز ✅ مفيش حد متأخر ولا عليه رصيد سابق دلوقتي.');
    }
    final rows = <_Row>[
      for (final i in late)
        _Row('${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}', 'متأخر • ${dueText(i)}',
            fmt(totalDue(i)), const Color(0xFFC62828),
            prop: i, waMsg: _reminder(i)),
      for (final i in withBal)
        _Row('${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}',
            'رصيد سابق عليه', fmt(num0(i['balance'])), const Color(0xFFEF6C00),
            prop: i, waMsg: _reminder(i)),
    ];
    final lateTotal = late.fold<double>(0, (s, e) => s + totalDue(e));
    final balTotal = withBal.fold<double>(0, (s, e) => s + num0(e['balance']));
    final top = late.isNotEmpty ? late.first : null;
    final b = StringBuffer();
    if (late.isNotEmpty) {
      b.write('${late.length} متأخرين بإجمالي ${fmt(lateTotal)}.');
      if (top != null) {
        b.write('\nأكبر مديونية: ${top['tenant_name']} (${fmt(totalDue(top))}).');
      }
    }
    if (withBal.isNotEmpty) {
      b.write('${late.isNotEmpty ? '\n' : ''}${withBal.length} عليهم رصيد سابق بإجمالي ${fmt(balTotal)}.');
    }
    b.write('\nتقدر تبعتلهم تذكير واتساب من الزر جنب كل اسم.');
    return _Msg(false, b.toString(), rows);
  }

  // ---------- قرب الاستحقاق ----------
  _Msg _upcoming() {
    final list = _active.where((i) {
      final d = daysUntilDue(i);
      return d != null && d >= 0 && d <= (soonDays > 7 ? soonDays : 7);
    }).toList()
      ..sort((a, b) => (daysUntilDue(a) ?? 0).compareTo(daysUntilDue(b) ?? 0));
    if (list.isEmpty) {
      return const _Msg(false, 'مفيش إيجارات هتستحق خلال الأسبوع الجاي.');
    }
    final total = list.fold<double>(0, (s, e) => s + totalDue(e));
    return _Msg(false, '${list.length} هيستحقوا خلال أيام بإجمالي ${fmt(total)}:', [
      for (final i in list)
        _Row('${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}', dueText(i),
            fmt(totalDue(i)), const Color(0xFFEF6C00),
            prop: i, waMsg: _reminder(i)),
    ]);
  }

  // ---------- المحصّل ----------
  _Msg _collected(String q) {
    final n = DateTime.now();
    late DateTime from, to;
    late String label;
    if (_has(q, ['الماضي', 'اللي فات', 'السابق'])) {
      from = DateTime(n.year, n.month - 1, 1);
      to = DateTime(n.year, n.month, 0);
      label = 'الشهر الماضي';
    } else if (_has(q, ['السنه', 'السنة', 'العام'])) {
      from = DateTime(n.year, 1, 1);
      to = DateTime(n.year, 12, 31);
      label = 'السنة دي';
    } else if (_has(q, ['اليوم', 'النهارده', 'النهاردة'])) {
      from = DateTime(n.year, n.month, n.day);
      to = from;
      label = 'النهاردة';
    } else {
      from = DateTime(n.year, n.month, 1);
      to = DateTime(n.year, n.month + 1, 0);
      label = 'الشهر ده';
    }
    final sum = _paidIn(from, to);
    final expected = _active.fold<double>(0, (s, e) => s + num0(e['rent_amount']));
    final extra = label == 'الشهر ده' && expected > 0
        ? '\nالإيجارات الشهرية المتوقعة: ${fmt(expected)} (نسبة التحصيل ${(sum / expected * 100).clamp(0, 999).toStringAsFixed(0)}%).'
        : '';
    return _Msg(false, 'المحصّل $label: ${fmt(sum)}.$extra');
  }

  _Msg _vacant() {
    final list = items.where((i) => i['status'] == 'شاغر').toList();
    if (list.isEmpty) return const _Msg(false, 'كل العقارات مؤجرة ✅');
    return _Msg(false, '${list.length} عقار شاغر:', [
      for (final i in list)
        _Row('${i['name'] ?? ''}', '${i['address'] ?? ''}',
            fmt(num0(i['rent_amount'])), Colors.blueGrey),
    ]);
  }

  _Msg _contracts() {
    final list = computeContractAlerts(items);
    if (list.isEmpty) {
      return const _Msg(false, 'مفيش عقود هتنتهي خلال شهرين ✅');
    }
    return _Msg(false, '${list.length} عقد منتهي أو قارب على الانتهاء:', [
      for (final i in list)
        _Row('${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}', contractText(i), '',
            (contractDaysLeft(i) ?? 0) < 0 ? const Color(0xFFC62828) : const Color(0xFFEF6C00)),
    ]);
  }

  _Msg _credits() {
    final list = _active.where((i) => num0(i['balance']) < -0.001).toList();
    if (list.isEmpty) return const _Msg(false, 'مفيش حد ليه رصيد دائن دلوقتي.');
    final total = list.fold<double>(0, (s, e) => s - num0(e['balance']));
    return _Msg(false, '${list.length} ليهم رصيد دائن بإجمالي ${fmt(total)}:', [
      for (final i in list)
        _Row('${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}', 'رصيد دائن',
            fmt(-num0(i['balance'])), const Color(0xFF2E7D32)),
    ]);
  }

  _Msg _lastPays() {
    if (pays.isEmpty) return const _Msg(false, 'لسه مفيش مدفوعات مسجلة.');
    return _Msg(false, 'آخر ${pays.length > 5 ? 5 : pays.length} إيصالات:', [
      for (final p in pays.take(5))
        _Row('${p['tenant_name'] ?? ''} - ${p['property_name'] ?? ''}',
            '${fmtDateStr(p['paid_at'])} • إيصال ${receiptNo(p)}',
            fmt(num0(p['amount'])), const Color(0xFF2E7D32)),
    ]);
  }

  // ---------- مستأجر / عقار بعينه ----------
  _Msg _single(List<Map<String, dynamic>> hit) {
    final rows = <_Row>[];
    for (final i in hit.take(5)) {
      final es = effStatus(i);
      final c = es == 'متأخرات'
          ? const Color(0xFFC62828)
          : es == 'شاغر'
              ? Colors.blueGrey
              : const Color(0xFF2E7D32);
      final mine = pays.where((p) => p['property_id'] == i['id']).toList();
      final paid = mine.fold<double>(0, (s, e) => s + num0(e['amount']));
      final bal = num0(i['balance']);
      rows.add(_Row(
        '${i['tenant_name'] ?? ''} - ${i['name'] ?? ''}',
        'الحالة: $es • الاستحقاق: ${dueText(i)}\n'
            'الإيجار ${fmt(num0(i['rent_amount']))} + مرافق ${fmt(utilitiesTotal(i))}'
            '${bal != 0 ? ' + ${bal > 0 ? 'رصيد سابق' : 'رصيد دائن'} ${fmt(bal.abs())}' : ''}\n'
            'إجمالي ما سدّده: ${fmt(paid)} (${mine.length} إيصال)',
        i['status'] == 'شاغر' ? '' : fmt(totalDue(i)),
        c,
        prop: i['status'] == 'شاغر' ? null : i,
        waMsg: _reminder(i),
      ));
    }
    return _Msg(false, 'ده حساب ${hit.length > 1 ? 'المطابقين لسؤالك' : 'اللي سألت عنه'}:', rows);
  }

  // ---------- ملخص ----------
  _Msg summary() {
    final act = _active;
    final late = act.where((i) => effStatus(i) == 'متأخرات').toList();
    final lateTotal = late.fold<double>(0, (s, e) => s + totalDue(e));
    final n = DateTime.now();
    final month = _paidIn(DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 0));
    final rent = act.fold<double>(0, (s, e) => s + num0(e['rent_amount']));
    final vacant = items.length - act.length;
    return _Msg(
        false,
        'ملخص سريع:\n'
        '• العقارات: ${items.length} (مؤجر ${act.length} • شاغر $vacant)\n'
        '• الإيجارات الشهرية: ${fmt(rent)}\n'
        '• المحصّل الشهر ده: ${fmt(month)}\n'
        '• المتأخرات: ${late.length} بإجمالي ${fmt(lateTotal)}'
        '${late.isEmpty ? '\n✅ مفيش متأخرات' : '\nاسألني «مين عليه فلوس؟» وأعرضلك التفاصيل.'}');
  }
}

class AssistantScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> pays;
  const AssistantScreen({super.key, required this.items, required this.pays});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final _Engine _e = _Engine(widget.items, widget.pays);
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];

  static const _quick = [
    'مين عليه فلوس؟',
    'كام اتحصّل الشهر ده؟',
    'مين هيستحق قريب؟',
    'العقود اللي هتنتهي',
    'العقارات الشاغرة',
    'ملخص عام',
    'بطاقة مستأجر',
  ];

  @override
  void initState() {
    super.initState();
    _msgs.add(const _Msg(false,
        'أهلاً 👋 أنا مساعدك المالي. أقدر أقولك مين عليه فلوس، وكام اتحصّل، وإيه اللي قرب يستحق أو ينتهي.'));
    _msgs.add(_e._debtors());
  }

  @override
  void dispose() {
    AiBrain.I.dispose();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    final t = q.trim();
    if (t.isEmpty) return;
    setState(() {
      _msgs.add(_Msg(true, t));
      _c.clear();
    });
    var replies = await _e.answerAsync(t);
    if (replies.length == 1 && replies.first.text == _kUnknown) {
      final smart = await _smartQuery(t);
      if (smart != null) replies = await _e.answerAsync(smart);
    }
    if (!mounted) return;
    setState(() => _msgs.addAll(replies));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  /// الفهم الذكي (اختياري): النموذج يحوّل السؤال إلى أمر، والمساعد ينفذه من بياناتك
  Future<String?> _smartQuery(String q) async {
    if (!await AiBrain.I.installed()) return null;
    const wait = _Msg(false, '⏳ بفكر في سؤالك...');
    if (mounted) setState(() => _msgs.add(wait));
    String? out;
    try {
      final names = <String>{
        for (final i in widget.items) ...[
          '${i['tenant_name'] ?? ''}'.trim(),
          '${i['name'] ?? ''}'.trim(),
        ]
      }..removeWhere((e) => e.isEmpty);
      final list = names.take(40).toList();
      final reply = await AiBrain.I
          .classify(q, list)
          .timeout(const Duration(seconds: 90), onTimeout: () => null);
      if (reply != null) out = _fromCommand(reply, list);
    } catch (_) {}
    if (mounted) setState(() => _msgs.remove(wait));
    return out;
  }

  String? _fromCommand(String reply, List<String> names) {
    final line = reply.split('\n').first.trim();
    for (final e in _kCommands.entries) {
      if (line.toUpperCase().startsWith(e.key)) return e.value;
    }
    final m = RegExp(r'^(ID_CARD|CONTRACT_DOC|ACCOUNT)\s*:\s*(.+)$',
            caseSensitive: false)
        .firstMatch(line);
    if (m == null) return null;
    // لازم الاسم يكون موجوداً فعلاً (حماية من التأليف)
    final raw = _norm(m.group(2)!.replaceAll(RegExp(r'[<>"]'), ''));
    String? real;
    for (final n in names) {
      if (_norm(n) == raw) real = n;
    }
    real ??= names.cast<String?>().firstWhere(
        (n) => n != null && raw.length >= 3 && _norm(n).contains(raw),
        orElse: () => null);
    if (real == null) return null;
    switch (m.group(1)!.toUpperCase()) {
      case 'ID_CARD':
        return 'بطاقة $real';
      case 'CONTRACT_DOC':
        return 'عقد $real';
      default:
        return real;
    }
  }

  /// نافذة تفعيل/حذف الفهم الذكي
  Future<void> _aiDialog() async {
    var installed = await AiBrain.I.installed();
    var busy = false;
    double prog = 0;
    String? err;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('الفهم الذكي (AI)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(installed
                  ? '✅ مفعّل. لو المساعد ما فهمش سؤالك بالكلمات، النموذج الصغير بيفهم قصدك وبينفذه من بياناتك.'
                  : 'نموذج Qwen 2.5 صغير بيفهم صياغات أكتر للأسئلة. حجمه $kAiModelSizeText وبيتنزّل مرة واحدة (يفضّل واي فاي)، وبعدها يشتغل أوفلاين وبياناتك ما بتخرجش من الهاتف.'),
              const SizedBox(height: 8),
              const Text(
                  'النموذج بيفهم السؤال بس؛ كل الأرقام بتتحسب من قاعدة بياناتك. ممكن يبطّأ على الهواتف الضعيفة.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              if (busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: prog > 0 ? prog : null),
                const SizedBox(height: 4),
                Text('${(prog * 100).toStringAsFixed(0)}%'),
              ],
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            if (busy)
              TextButton(
                  onPressed: AiBrain.I.cancelDownload,
                  child: const Text('إلغاء التنزيل'))
            else ...[
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
              if (installed)
                TextButton(
                  onPressed: () async {
                    await AiBrain.I.remove();
                    setS(() => installed = false);
                  },
                  child: const Text('حذف النموذج',
                      style: TextStyle(color: Colors.red)),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    setS(() {
                      busy = true;
                      err = null;
                      prog = 0;
                    });
                    try {
                      await AiBrain.I.download((v) {
                        if (ctx.mounted) setS(() => prog = v);
                      });
                      installed = true;
                    } catch (e) {
                      err = e.toString().contains('_Cancelled')
                          ? 'تم إلغاء التنزيل'
                          : 'تعذر التنزيل، تأكد من الإنترنت وحاول مرة أخرى';
                    }
                    if (ctx.mounted) setS(() => busy = false);
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('تنزيل وتفعيل'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.mine ? cs.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text,
                style: TextStyle(
                    height: 1.5, color: m.mine ? Colors.white : Colors.black87)),
            if (m.images.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in m.images)
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: InteractiveViewer(child: Image.file(File(f))),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(f),
                            width: 110, height: 110, fit: BoxFit.cover),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  try {
                    await Share.shareXFiles([for (final f in m.images) XFile(f)],
                        text: m.text);
                  } catch (_) {
                    toast(context, 'تعذرت المشاركة');
                  }
                },
                icon: const Icon(Icons.share),
                label: const Text('إرسال / مشاركة (واتساب وغيره)'),
              ),
            ],
            if (m.suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final sgt in m.suggestions)
                    ActionChip(label: Text(sgt), onPressed: () => _ask(sgt)),
                ],
              ),
            ],
            for (final r in m.rows) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                decoration: BoxDecoration(
                  color: r.color.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title,
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (r.subtitle.isNotEmpty)
                            Text(r.subtitle,
                                style: const TextStyle(
                                    fontSize: 12.5, color: Colors.black54, height: 1.4)),
                        ],
                      ),
                    ),
                    if (r.amount.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(r.amount,
                            style: TextStyle(
                                fontWeight: FontWeight.w900, color: r.color)),
                      ),
                    if (r.prop != null && r.waMsg != null)
                      IconButton(
                        tooltip: 'تذكير واتساب',
                        icon: const Icon(Icons.chat, color: Color(0xFF2E7D32)),
                        onPressed: () =>
                            launchWa(context, phoneOf(r.prop!), r.waMsg!),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المساعد المالي'),
        actions: [
          IconButton(
            tooltip: 'الفهم الذكي (AI)',
            icon: const Icon(Icons.psychology_alt),
            onPressed: _aiDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [for (final m in _msgs) _bubble(m)],
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final q in _quick)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(label: Text(q), onPressed: () => _ask(q)),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _c,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                          hintText: 'اسأل عن الماليات أو اكتب اسم مستأجر...',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _ask(_c.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
