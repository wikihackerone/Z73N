import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import 'db.dart';
import 'smb_backup.dart';

/// اسم مهمة النسخ الاحتياطي التلقائي في WorkManager
const String backupTaskUnique = 'auto_backup_v1';
const String backupTaskName = 'autoBackup';

/// معلومات نسخة احتياطية موجودة في المجلد
class BackupInfo {
  final File file;
  final String name;
  final int size;
  final DateTime modified;
  BackupInfo(this.file, this.name, this.size, this.modified);

  String get kindLabel {
    if (name.startsWith('auto_')) return 'تلقائية';
    if (name.startsWith('prerestore_')) return 'قبل الاستعادة';
    return 'يدوية';
  }
}

/// النسخة الاحتياطية = ملف ZIP يحتوي:
///   real_estate.db   قاعدة البيانات كاملة (عقارات، مدفوعات، حسابات، إعدادات)
///   files/...        كل الصور المرفقة (بطاقات ومستندات)
///   manifest.json    بيانات النسخة + ربط مسارات الصور
class BackupService {
  static const String defaultDir = '/storage/emulated/0/RealEstateBackups';
  static final RegExp _nameRe = RegExp(r'^(backup|auto|prerestore)_.*\.zip$');

  /// نتيجة آخر رفع للكمبيوتر بعد نسخة: null = غير مفعّل | true = تم | false = فشل
  static bool? lastSmbResult;

  // ---------------- المجلد والصلاحيات ----------------
  static Future<String> folderPath() async {
    final v = (await DB.getSetting('backup_dir'))?.trim() ?? '';
    return v.isEmpty ? defaultDir : v;
  }

  static Future<Directory> _fallbackDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'Backups'));
  }

  static Future<bool> _writable(Directory d) async {
    try {
      await d.create(recursive: true);
      final t = File(p.join(d.path, '.w_${DateTime.now().microsecondsSinceEpoch}'));
      await t.writeAsString('1', flush: true);
      await t.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// هل المجلد المختار (في التخزين الداخلي) قابل للكتابة فعلاً؟
  static Future<bool> primaryWritable() async =>
      _writable(Directory(await folderPath()));

  /// المجلد الفعلي المستخدم: المختار، وإن تعذّر فمجلد التطبيق الخاص
  static Future<Directory> resolveDir() async {
    final main = Directory(await folderPath());
    if (await _writable(main)) return main;
    final fb = await _fallbackDir();
    await fb.create(recursive: true);
    return fb;
  }

  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      await Permission.storage.request();
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    } catch (_) {}
    return primaryWritable();
  }

  // ---------------- إنشاء نسخة ----------------
  /// [prefix]: backup (يدوي) | auto (تلقائي) | prerestore (قبل الاستعادة)
  static Future<File> createBackup({String prefix = 'backup'}) async {
    final dir = await resolveDir();
    await DB.checkpoint();
    final dbFile = File(await DB.dbPath());
    if (!await dbFile.exists()) {
      throw Exception('ملف قاعدة البيانات غير موجود');
    }

    // كل الصور المرتبطة بالسجلات
    final d = await DB.db;
    final paths = <String>{};
    for (final r in await d.query('attachments', columns: ['path'])) {
      paths.add((r['path'] ?? '').toString());
    }
    for (final r
        in await d.query('properties', columns: ['id_card_path', 'contract_path'])) {
      paths.add((r['id_card_path'] ?? '').toString());
      paths.add((r['contract_path'] ?? '').toString());
    }
    final files = <String, String>{}; // المسار الأصلي -> اسم داخل الـ ZIP
    var i = 0;
    for (final path in paths) {
      if (path.isEmpty) continue;
      if (await File(path).exists()) {
        files[path] = 'files/${i++}_${p.basename(path)}';
      }
    }

    final stamp = intl.DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final out = File(p.join(dir.path, '${prefix}_$stamp.zip'));
    final tmp = File('${out.path}.tmp');
    if (await tmp.exists()) await tmp.delete();

    final enc = ZipFileEncoder();
    enc.create(tmp.path);
    try {
      await enc.addFile(dbFile, 'real_estate.db');
      for (final e in files.entries) {
        await enc.addFile(File(e.key), e.value);
      }
      final mf = utf8.encode(jsonEncode({
        'app': 'real_estate_app',
        'db_version': DB.version,
        'created_at': DateTime.now().toIso8601String(),
        'kind': prefix,
        'files': files,
      }));
      enc.addArchiveFile(ArchiveFile('manifest.json', mf.length, mf));
    } finally {
      await enc.close();
    }
    await tmp.rename(out.path);

    final now = DateTime.now().toIso8601String();
    await DB.setSetting('backup_last', now);
    if (prefix == 'auto') {
      await DB.setSetting('backup_last_auto', now);
      await _prune();
    }
    // خيار إضافي: رفع نسخة إلى مجلد مشترك على كمبيوتر ويندوز (النسخة المحلية تُحفظ دائماً)
    lastSmbResult =
        prefix == 'prerestore' ? null : await SmbBackup.afterBackup(out, prefix);
    return out;
  }

  static Future<List<BackupInfo>> list() async {
    final dir = await resolveDir();
    final res = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is File && _nameRe.hasMatch(p.basename(e.path))) {
        final st = await e.stat();
        res.add(BackupInfo(e, p.basename(e.path), st.size, st.modified));
      }
    }
    res.sort((a, b) => b.modified.compareTo(a.modified));
    return res;
  }

  /// يحتفظ بآخر N نسخة تلقائية فقط (النسخ اليدوية لا تُحذف تلقائياً)
  static Future<void> _prune() async {
    final keep = int.tryParse(await DB.getSetting('backup_keep') ?? '') ?? 10;
    final autos = (await list()).where((b) => b.name.startsWith('auto_')).toList();
    for (final b in autos.skip(keep)) {
      try {
        await b.file.delete();
      } catch (_) {}
    }
  }

  // ---------------- الاستعادة ----------------
  static Future<void> restore(File zip) async {
    final tmpRoot = await getTemporaryDirectory();
    final tmp = Directory(
        p.join(tmpRoot.path, 'restore_${DateTime.now().millisecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    InputFileStream? input;
    try {
      // 1) فك الضغط في مجلد مؤقت (أسماء مسطّحة لمنع أي مسارات خبيثة)
      Archive arc;
      try {
        input = InputFileStream(zip.path);
        arc = ZipDecoder().decodeStream(input);
      } catch (_) {
        throw Exception('الملف ليس نسخة احتياطية صالحة');
      }
      for (final f in arc.files) {
        if (!f.isFile) continue;
        final bytes = f.content as List<int>;
        await File(p.join(tmp.path, p.basename(f.name))).writeAsBytes(bytes);
      }
      final tmpDb = p.join(tmp.path, 'real_estate.db');
      if (!await File(tmpDb).exists()) {
        throw Exception('الملف لا يحتوي على قاعدة بيانات التطبيق');
      }

      // 2) التحقق من القاعدة + إعادة ربط مسارات الصور
      await _prepareDb(tmp, tmpDb);

      // 3) نسخة أمان من البيانات الحالية قبل الاستبدال
      try {
        await createBackup(prefix: 'prerestore');
      } catch (_) {}

      // 4) استبدال قاعدة البيانات
      await DB.close();
      final target = await DB.dbPath();
      for (final s in ['', '-wal', '-shm', '-journal']) {
        final f = File('$target$s');
        if (await f.exists()) await f.delete();
      }
      await File(tmpDb).copy(target);
      await loadAppSettings();
    } finally {
      try {
        input?.close();
      } catch (_) {}
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> _prepareDb(Directory tmp, String tmpDb) async {
    final tdb = await openDatabase(tmpDb, singleInstance: false);
    try {
      final ver =
          Sqflite.firstIntValue(await tdb.rawQuery('PRAGMA user_version')) ?? 0;
      if (ver > DB.version) {
        throw Exception('هذه النسخة أحدث من إصدار التطبيق. حدّث التطبيق أولاً');
      }
      final tables = (await tdb
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((e) => e['name'].toString())
          .toSet();
      if (!tables.contains('properties')) {
        throw Exception('قاعدة البيانات داخل النسخة غير صالحة');
      }

      // إعادة الصور إلى مجلد التطبيق وتحديث مساراتها
      final mfFile = File(p.join(tmp.path, 'manifest.json'));
      if (await mfFile.exists()) {
        Map<String, dynamic> files = {};
        try {
          final m = jsonDecode(await mfFile.readAsString());
          files = Map<String, dynamic>.from(m['files'] ?? {});
        } catch (_) {}
        final docs = await getApplicationDocumentsDirectory();
        for (final e in files.entries) {
          final src = File(p.join(tmp.path, p.basename(e.value.toString())));
          if (!await src.exists()) continue;
          final orig = e.key;
          final dest = p.join(docs.path, p.basename(orig));
          if (!await File(dest).exists()) await src.copy(dest);
          if (dest == orig) continue;
          if (tables.contains('attachments')) {
            await tdb.update('attachments', {'path': dest},
                where: 'path = ?', whereArgs: [orig]);
          }
          await tdb.update('properties', {'id_card_path': dest},
              where: 'id_card_path = ?', whereArgs: [orig]);
          await tdb.update('properties', {'contract_path': dest},
              where: 'contract_path = ?', whereArgs: [orig]);
        }
      }
    } finally {
      await tdb.close();
    }
  }

  // ---------------- النسخ التلقائي ----------------
  /// الفاصل بين النسخ التلقائية بالساعات (1 - 720).
  /// الإعداد الجديد backup_hours، وإن لم يوجد يُحوَّل الإعداد القديم (أيام) إلى ساعات.
  static Future<int> intervalHours() async {
    final h = int.tryParse(await DB.getSetting('backup_hours') ?? '');
    if (h != null) return h.clamp(1, 720);
    final d = int.tryParse(await DB.getSetting('backup_days') ?? '');
    if (d != null && d > 0) return (d * 24).clamp(1, 720);
    return 24;
  }

  static Future<void> setIntervalHours(int hours) async {
    await DB.setSetting('backup_hours', '${hours.clamp(1, 720)}');
  }

  /// موعد النسخة التلقائية القادمة (تقريبي)، أو null إن لم تُفعَّل بعد
  static Future<DateTime?> nextAutoBackup() async {
    if ((await DB.getSetting('backup_auto')) != '1') return null;
    final last = DateTime.tryParse(await DB.getSetting('backup_last_auto') ?? '');
    if (last == null) return null;
    return last.add(Duration(hours: await intervalHours()));
  }

  /// ينفّذ نسخة تلقائية إن كانت مفعّلة وحان موعدها
  static Future<bool> autoIfDue({bool force = false}) async {
    try {
      if ((await DB.getSetting('backup_auto')) != '1') return false;
      await SmbBackup.retryPending();
      final hours = await intervalHours();
      final last = DateTime.tryParse(await DB.getSetting('backup_last_auto') ?? '');
      // هامش صغير لأن WorkManager لا يعمل في الدقيقة بالضبط
      final slack = Duration(minutes: hours <= 1 ? 5 : 20);
      if (!force &&
          last != null &&
          DateTime.now().difference(last) < Duration(hours: hours) - slack) {
        return false;
      }
      await createBackup(prefix: 'auto');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يجدول فحص WorkManager حسب الفاصل المختار (بين 15 دقيقة و6 ساعات)؛
  /// الفحص يقرر هل حان موعد النسخة فعلاً أم لا.
  static Future<void> schedule() async {
    try {
      final hours = await intervalHours();
      final minutes = (hours * 60).clamp(15, 360);
      await Workmanager().cancelByUniqueName(backupTaskUnique);
      await Workmanager().registerPeriodicTask(
        backupTaskUnique,
        backupTaskName,
        frequency: Duration(minutes: minutes),
      );
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(backupTaskUnique);
    } catch (_) {}
  }

  /// يُستدعى بعد تسجيل الدخول
  static Future<void> bootstrap() async {
    try {
      await SmbBackup.retryPending();
      if ((await DB.getSetting('backup_auto')) == '1') {
        await schedule();
        await autoIfDue();
      }
    } catch (_) {}
  }
}
