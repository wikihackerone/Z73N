import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'backup.dart';
import 'db.dart';
import 'utils.dart';

const String _taskUnique = 'rent_alerts_v1';
const String _taskName = 'rentAlerts';
const String _taskTag = 'rent_alerts_tag';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// نقطة دخول المهام الدورية (تذكير يومي بالإيجارات في وقت محدد + النسخ الاحتياطي التلقائي)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (task == backupTaskName) {
        await BackupService.autoIfDue();
      } else {
        await runAlertCheck();
      }
    } catch (_) {}
    return true;
  });
}

Future<void> runAlertCheck() async {
  if ((await DB.getSetting('notifications_enabled')) != '1') return;
  soonDays = int.tryParse(await DB.getSetting('soon_days') ?? '') ?? 3;
  final items = await DB.all();
  await _rentNotice(items);
  await _contractNotice(items);
}

/// تنبيه العقود التي ينتهي خلال شهرين أو انتهت - مرة واحدة في اليوم
Future<void> _contractNotice(List<Map<String, dynamic>> items) async {
  final list = computeContractAlerts(items);
  if (list.isEmpty) return;
  final today = dateIso(DateTime.now());
  if (await DB.getSetting('contract_alert_last') == today) return;
  final lines = <String>[];
  for (final i in list.take(5)) {
    final left = contractDaysLeft(i) ?? 0;
    final what = left < 0
        ? 'انتهى منذ ${-left} يوم'
        : (left == 0 ? 'ينتهي اليوم' : 'ينتهي بعد $left يوم');
    lines.add('${i['tenant_name'] ?? ''} (${i['name'] ?? ''}): $what');
  }
  if (list.length > 5) lines.add('و${list.length - 5} عقود أخرى');
  await Notifier.show('تنبيه انتهاء العقود', lines.join('\n'), id: 1002);
  await DB.setSetting('contract_alert_last', today);
}

Future<void> _rentNotice(List<Map<String, dynamic>> items) async {
  final alerts = computeAlerts(items);
  if (alerts.isEmpty) return;

  final late = <String>[];
  final soon = <String>[];
  for (final i in alerts) {
    final d = daysUntilDue(i);
    final label = '${i['tenant_name'] ?? ''} (${i['name'] ?? ''})';
    if (d == null || d < 0) {
      late.add(label);
    } else {
      soon.add(label);
    }
  }
  String join(List<String> l) =>
      l.take(3).join('، ') + (l.length > 3 ? ' و${l.length - 3} آخرين' : '');
  final parts = <String>[];
  if (late.isNotEmpty) parts.add('متأخر: ${join(late)}');
  if (soon.isNotEmpty) parts.add('قريب الاستحقاق: ${join(soon)}');
  await Notifier.show('تنبيه الإيجارات', parts.join('\n'));
}

class Notifier {
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _inited = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// صلاحية POST_NOTIFICATIONS (أندرويد 13+)
  static Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  static Future<bool> permissionGranted() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  static Future<void> show(String title, String body, {int id = 1001}) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'rent_alerts',
          'تنبيهات الإيجارات',
          channelDescription: 'تنبيهات الإيجارات المتأخرة وقريبة الاستحقاق',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  /// أقصى عدد لأوقات التذكير في اليوم
  static const int maxReminders = 8;

  static String _norm(String v) {
    final p = v.trim().split(':');
    return '${int.parse(p[0]).toString().padLeft(2, '0')}:${int.parse(p[1]).toString().padLeft(2, '0')}';
  }

  static bool _valid(String v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim());
    if (m == null) return false;
    return int.parse(m.group(1)!) < 24 && int.parse(m.group(2)!) < 60;
  }

  /// أوقات التذكير اليومية (HH:mm) مرتبة - الافتراضي 09:00
  /// (يدعم الإعداد القديم reminder_time تلقائياً)
  static Future<List<String>> reminderTimes() async {
    final out = <String>{};
    final v = await DB.getSetting('reminder_times');
    if (v != null) {
      for (final t in v.split(',')) {
        if (_valid(t)) out.add(_norm(t));
      }
    }
    if (out.isEmpty) {
      final old = await DB.getSetting('reminder_time');
      out.add(old != null && _valid(old) ? _norm(old) : '09:00');
    }
    return out.toList()..sort();
  }

  static Future<void> saveReminderTimes(List<String> times) async {
    final clean = times.where(_valid).map(_norm).toSet().toList()..sort();
    await DB.setSetting('reminder_times', clean.join(','));
  }

  static Duration _delayUntil(String hhmm) {
    final p = hhmm.split(':');
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at.difference(now);
  }

  /// جدولة تذكير يومي لكل وقت من الأوقات المختارة (مهمة مستقلة لكل وقت)
  static Future<void> schedule() async {
    try {
      final times = await reminderTimes();
      await cancel();
      for (final t in times) {
        await Workmanager().registerPeriodicTask(
          '${_taskUnique}_${t.replaceAll(':', '')}',
          _taskName,
          frequency: const Duration(hours: 24),
          initialDelay: _delayUntil(t),
          tag: _taskTag,
        );
      }
    } catch (_) {}
  }

  /// يلغي كل مهام التذكير فقط (ولا يمس مهمة النسخ الاحتياطي)
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByTag(_taskTag);
      await Workmanager().cancelByUniqueName(_taskUnique); // جدولة قديمة
    } catch (_) {}
  }

  /// يُستدعى بعد تسجيل الدخول: أول مرة يطلب الصلاحية ويفعّل الإشعارات
  static Future<void> bootstrap() async {
    try {
      await init();
      var enabled = await DB.getSetting('notifications_enabled');
      if (enabled == null) {
        final ok = await requestPermission();
        enabled = ok ? '1' : '0';
        await DB.setSetting('notifications_enabled', enabled);
      }
      if (enabled == '1') {
        await schedule();
      }
    } catch (_) {}
  }
}
