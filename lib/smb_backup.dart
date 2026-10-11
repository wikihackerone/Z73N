import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';

import 'db.dart';

/// وجهة النسخ على كمبيوتر ويندوز: الجهاز + اسم المجلد المشترك + مجلد فرعي اختياري
class SmbTarget {
  final String host;
  final String share;
  final List<String> sub;
  const SmbTarget(this.host, this.share, this.sub);

  /// مسار المجلد داخل المشاركة بصيغة المكتبة: /Share/sub1/sub2
  String get dir {
    final tail = sub.isEmpty ? '' : '/${sub.join('/')}';
    return '/$share$tail';
  }
}

/// رفع النسخ الاحتياطية إلى مجلد مشترك (Network Share / SMB) على كمبيوتر ويندوز.
/// خيار إضافي بجانب النسخة المحلية (أوفلاين): النسخة تُحفظ محلياً دائماً، ثم تُرفع للكمبيوتر إن كان مفعّلاً.
/// إن كان الكمبيوتر مغلقاً/غير متصل تبقى النسخة «معلّقة» وتُرفع تلقائياً عند أول فرصة.
class SmbBackup {
  static const _kEnabled = 'smb_enabled';
  static const _kPath = 'smb_path';
  static const _kUser = 'smb_user';
  static const _kPass = 'smb_pass';
  static const _kLast = 'smb_last';
  static const _kError = 'smb_error';
  static const _kPending = 'smb_pending';

  // ---------------- الإعدادات ----------------
  static Future<bool> enabled() async =>
      (await DB.getSetting(_kEnabled)) == '1';

  static Future<void> setEnabled(bool v) =>
      DB.setSetting(_kEnabled, v ? '1' : '0');

  static Future<String> path() async => (await DB.getSetting(_kPath)) ?? '';
  static Future<String> user() async => (await DB.getSetting(_kUser)) ?? '';
  static Future<String> pass() async => (await DB.getSetting(_kPass)) ?? '';
  static Future<String> lastError() async =>
      (await DB.getSetting(_kError)) ?? '';
  static Future<DateTime?> lastUpload() async =>
      DateTime.tryParse((await DB.getSetting(_kLast)) ?? '');
  static Future<bool> hasPending() async =>
      ((await DB.getSetting(_kPending)) ?? '').isNotEmpty;

  static Future<void> saveConfig(String path, String user, String pass) async {
    await DB.setSetting(_kPath, path.trim());
    await DB.setSetting(_kUser, user.trim());
    await DB.setSetting(_kPass, pass);
  }

  /// يقبل: \\192.168.1.5\Backups\RealEstate  أو  192.168.1.5/Backups  أو  smb://PC/Backups
  static SmbTarget? parseTarget(String raw) {
    var t = raw.trim().replaceAll('\\', '/');
    t = t.replaceFirst(RegExp(r'^smb://', caseSensitive: false), '');
    final parts = t.split('/').where((e) => e.trim().isNotEmpty).toList();
    if (parts.length < 2) return null;
    return SmbTarget(
        parts[0].trim(), parts[1].trim(), parts.sublist(2).map((e) => e.trim()).toList());
  }

  static Future<bool> configured() async =>
      parseTarget(await path()) != null && (await user()).trim().isNotEmpty;

  // ---------------- الاتصال ----------------
  /// المستخدم قد يُكتب: user  أو  PCNAME\user  (حساب محلي أو دومين)
  static List<String> _splitUser(String raw) {
    final u = raw.trim();
    final i = u.indexOf('\\');
    if (i > 0) return [u.substring(0, i), u.substring(i + 1)];
    return ['', u];
  }

  static Future<SmbConnect> _connect(
      SmbTarget t, String userRaw, String pass) {
    final u = _splitUser(userRaw);
    return SmbConnect.connectAuth(
      host: t.host,
      domain: u[0],
      username: u[1],
      password: pass,
    ).timeout(const Duration(seconds: 15));
  }

  static Future<void> _ensureDir(SmbConnect c, SmbTarget t) async {
    var cur = '/${t.share}';
    for (final s in t.sub) {
      cur = '$cur/$s';
      final f = await c.file(cur);
      if (!f.isExists) await c.createFolder(cur);
    }
  }

  static Future<T> _withConnection<T>(
      Future<T> Function(SmbConnect c, SmbTarget t) job) async {
    final t = parseTarget(await path());
    if (t == null) {
      throw Exception(
          'اكتب عنوان المجلد المشترك بالشكل: \\\\192.168.1.5\\اسم_المجلد');
    }
    final c = await _connect(t, await user(), await pass());
    try {
      return await job(c, t);
    } finally {
      try {
        await c.close();
      } catch (_) {}
    }
  }

  /// يترجم أخطاء الشبكة لرسالة مفهومة
  static String explain(Object e) {
    if (e is TimeoutException || e is SocketException) {
      return 'تعذر الوصول للكمبيوتر. تأكد أنه شغّال ومتصل بنفس شبكة الواي فاي وأن العنوان صحيح';
    }
    final raw = e.toString();
    final s = raw.toLowerCase();
    if (s.contains('logon') ||
        s.contains('auth') ||
        s.contains('password') ||
        s.contains('credential')) {
      return 'اسم المستخدم أو كلمة المرور غير صحيحة';
    }
    if (s.contains('bad_network_name') || s.contains('bad network name')) {
      return 'اسم المجلد المشترك غير صحيح';
    }
    if (s.contains('access_denied') || s.contains('access denied')) {
      return 'لا توجد صلاحية كتابة على المجلد المشترك';
    }
    if (s.contains('socket') ||
        s.contains('connection') ||
        s.contains('timeout') ||
        s.contains('unreachable') ||
        s.contains('refused')) {
      return 'تعذر الوصول للكمبيوتر. تأكد أنه شغّال ومتصل بنفس شبكة الواي فاي وأن العنوان صحيح';
    }
    final msg = raw.replaceFirst('Exception: ', '');
    return msg.length > 140 ? '${msg.substring(0, 140)}...' : msg;
  }

  // ---------------- البحث عن الكمبيوترات ----------------
  /// يبحث في الشبكة المحلية (نفس شبكة الواي فاي) عن أجهزة تفتح منفذ المشاركة 445.
  /// يرجع قائمة عناوين IP مرتبة، لتختار منها بدل كتابة العنوان يدوياً.
  static Future<List<String>> scanLan() async {
    String? base;
    final own = <String>{};
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          final ip = a.address;
          final priv = ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
          if (priv) {
            base = ip.substring(0, ip.lastIndexOf('.'));
            own.add(ip);
          }
        }
      }
    } catch (_) {}
    final found = <String>[];
    if (base == null) return found;

    Future<void> probe(String ip) async {
      try {
        final s = await Socket.connect(ip, 445,
            timeout: const Duration(milliseconds: 900));
        s.destroy();
        found.add(ip);
      } catch (_) {}
    }

    // دفعات صغيرة حتى لا نفتح 254 اتصالاً دفعة واحدة
    for (var start = 1; start < 255; start += 64) {
      final batch = <Future<void>>[];
      for (var i = start; i < start + 64 && i < 255; i++) {
        final ip = '$base.$i';
        if (!own.contains(ip)) batch.add(probe(ip));
      }
      await Future.wait(batch);
    }
    found.sort((a, b) => int.parse(a.split('.').last)
        .compareTo(int.parse(b.split('.').last)));
    return found;
  }

  // ---------------- العمليات ----------------
  /// اختبار الاتصال: يتصل، ينشئ المجلد الفرعي إن لزم، ويكتب ملفاً تجريبياً ثم يحذفه
  static Future<void> test() async {
    await _withConnection((c, t) async {
      await _ensureDir(c, t);
      final f = await c.createFile(
          '${t.dir}/.test_${DateTime.now().millisecondsSinceEpoch}');
      await c.delete(f);
    }).timeout(const Duration(seconds: 40));
  }

  /// رفع ملف نسخة احتياطية إلى الكمبيوتر
  static Future<void> upload(File local) async {
    await _withConnection((c, t) async {
      await _ensureDir(c, t);
      final f = await c.createFile('${t.dir}/${p.basename(local.path)}');
      try {
        final w = await c.openWrite(f);
        await w.addStream(local.openRead());
        await w.flush();
        await w.close();
      } catch (_) {
        try {
          await c.delete(f);
        } catch (_) {}
        rethrow;
      }
    }).timeout(const Duration(minutes: 15));
  }

  /// يحتفظ بآخر [keep] نسخة تلقائية على الكمبيوتر (اليدوية لا تُحذف)
  static Future<void> pruneRemote(int keep) async {
    try {
      await _withConnection((c, t) async {
        final dir = await c.file(t.dir);
        final all = await c.listFiles(dir);
        final autos = all.where((f) {
          final n = p.basename(f.path);
          return n.startsWith('auto_') && n.endsWith('.zip');
        }).toList()
          ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
        for (final f in autos.skip(keep)) {
          try {
            await c.delete(f);
          } catch (_) {}
        }
      }).timeout(const Duration(seconds: 60));
    } catch (_) {}
  }

  static Future<void> _markOk() async {
    await DB.setSetting(_kLast, DateTime.now().toIso8601String());
    await DB.setSetting(_kError, '');
    await DB.setSetting(_kPending, '');
  }

  /// يُستدعى بعد إنشاء كل نسخة محلية.
  /// null = الخيار غير مفعّل | true = تم الرفع | false = فشل (وستُعاد المحاولة لاحقاً)
  static Future<bool?> afterBackup(File f, String prefix) async {
    try {
      if (!await enabled() || !await configured()) return null;
    } catch (_) {
      return null;
    }
    try {
      await upload(f);
      await _markOk();
      if (prefix == 'auto') {
        final keep = int.tryParse(await DB.getSetting('backup_keep') ?? '') ?? 10;
        await pruneRemote(keep);
      }
      return true;
    } catch (e) {
      try {
        await DB.setSetting(_kError, explain(e));
        await DB.setSetting(_kPending, f.path);
      } catch (_) {}
      return false;
    }
  }

  /// يعيد رفع آخر نسخة فشل رفعها (مثلاً كان الكمبيوتر مغلقاً)
  static Future<void> retryPending() async {
    try {
      if (!await enabled() || !await configured()) return;
      final path = (await DB.getSetting(_kPending)) ?? '';
      if (path.isEmpty) return;
      final f = File(path);
      if (!await f.exists()) {
        await DB.setSetting(_kPending, '');
        return;
      }
      try {
        await upload(f);
        await _markOk();
      } catch (e) {
        await DB.setSetting(_kError, explain(e));
      }
    } catch (_) {}
  }
}
