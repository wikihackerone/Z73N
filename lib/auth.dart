import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'backup.dart';
import 'backup_ui.dart';
import 'db.dart';
import 'home.dart';
import 'notifications.dart';
import 'security.dart';
import 'smooth.dart';
import 'utils.dart';

/// المستخدم الحالي (في الذاكرة فقط)
Map<String, dynamic>? currentUser;

bool get isMainUser => currentUser?['role'] == 'main';

// ---------------------------------------------------------
// شاشة تسجيل الدخول
// ---------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final LocalAuthentication _auth = LocalAuthentication();
  bool _busy = false;
  bool _hide = true;
  bool _bioAvail = false;
  bool _bioOn = false;
  String? _error;
  List<Map<String, dynamic>> _hints = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final users = await DB.users();
      final last = await DB.getSetting('last_user');
      _user.text = last ?? (users.isNotEmpty ? users.first['username'].toString() : '');
      _hints = users.where((u) => u['must_change'] == 1).toList();
      _bioOn = (await DB.getSetting('biometric_enabled')) == '1';
      try {
        _bioAvail = await _auth.isDeviceSupported();
      } catch (_) {
        _bioAvail = false;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    if (_bioOn && _bioAvail) _biometric();
  }

  String _defaultPass(String username) =>
      username == 'admin' ? '1234' : (username == 'backup' ? '5678' : '');

  Future<void> _login() async {
    final name = _user.text.trim();
    if (name.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final u = await DB.userByName(name);
    if (u != null &&
        hashPw(u['salt'].toString(), _pass.text) == u['pass_hash']) {
      await _enter(u);
    } else {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'اسم المستخدم أو كلمة المرور غير صحيحة';
        });
      }
    }
  }

  Future<void> _biometric() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'سجّل الدخول ببصمتك',
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return;
      final name = await DB.getSetting('biometric_user');
      final u = name == null ? null : await DB.userByName(name);
      if (u == null) {
        if (mounted) setState(() => _error = 'لم يتم ربط حساب بالبصمة');
        return;
      }
      await _enter(u);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر استخدام البصمة على هذا الجهاز');
    }
  }

  Future<void> _enter(Map<String, dynamic> u) async {
    currentUser = Map<String, dynamic>.from(u);
    await DB.setSetting('last_user', u['username'].toString());
    await loadAppSettings();
    await Notifier.bootstrap();
    BackupService.bootstrap(); // نسخ تلقائي إن حان موعده (في الخلفية)
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: FadeSlideIn(
                dy: 24,
                duration: const Duration(milliseconds: 600),
                child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: cs.primary.withAlpha(60),
                            blurRadius: 24,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset('assets/logo.png',
                          width: 104, height: 104, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('RentPal',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: cs.primary)),
                  const SizedBox(height: 6),
                  const Text('تسجيل الدخول',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تسجيل الدخول',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ForgotPasswordScreen(initialUser: _user.text.trim()))),
                      child: const Text('نسيت كلمة المرور؟'),
                    ),
                  ),
                  if (_bioOn && _bioAvail) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('الدخول بالبصمة'),
                    ),
                  ],
                  if (_hints.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('بيانات الدخول الافتراضية (غيّرها من الإعدادات):',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          for (final h in _hints)
                            Text(
                                '${h['display_name']}: ${h['username']} / ${_defaultPass(h['username'].toString())}'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// شاشة إعدادات التطبيق
// ---------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final _company = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _bio = false;
  bool _bioSupported = false;
  bool _notif = false;
  bool _permission = false;
  int _soon = 3;
  List<String> _reminders = ['09:00'];
  String _lastBackup = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await DB.users();
    final bioUser = await DB.getSetting('biometric_user');
    final bioOn = (await DB.getSetting('biometric_enabled')) == '1' &&
        bioUser == currentUser?['username'];
    var supported = false;
    try {
      supported = await _auth.isDeviceSupported();
    } catch (_) {}
    final notif = (await DB.getSetting('notifications_enabled')) == '1';
    var perm = false;
    try {
      perm = await Notifier.permissionGranted();
    } catch (_) {}
    _company.text = await DB.getSetting('company_name') ?? '';
    final lastBackup = lastBackupText(await DB.getSetting('backup_last'));
    final reminders = await Notifier.reminderTimes();
    if (!mounted) return;
    setState(() {
      _lastBackup = lastBackup;
      _users = users;
      _bio = bioOn;
      _bioSupported = supported;
      _notif = notif;
      _permission = perm;
      _soon = soonDays;
      _reminders = reminders;
      _loading = false;
    });
  }

  Future<void> _toggleBio(bool v) async {
    if (!v) {
      await DB.setSetting('biometric_enabled', '0');
      setState(() => _bio = false);
      return;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'تأكيد البصمة لتفعيل الدخول بها',
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return;
      await DB.setSetting('biometric_enabled', '1');
      await DB.setSetting('biometric_user', currentUser!['username'].toString());
      setState(() => _bio = true);
    } catch (_) {
      if (mounted) toast(context, 'تعذر استخدام البصمة على هذا الجهاز');
    }
  }

  Future<void> _toggleNotif(bool v) async {
    if (v) {
      final ok = await Notifier.requestPermission();
      if (!ok) {
        if (mounted) {
          toast(context, 'صلاحية الإشعارات مرفوضة. فعّلها من إعدادات الهاتف.');
        }
        await _load();
        return;
      }
      await DB.setSetting('notifications_enabled', '1');
      await Notifier.schedule();
    } else {
      await DB.setSetting('notifications_enabled', '0');
      await Notifier.cancel();
    }
    await _load();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(String help, [String? initial]) {
    final parts = (initial ?? '09:00').split(':');
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0),
      helpText: help,
    );
  }

  Future<void> _saveReminders(List<String> list, String msg) async {
    await Notifier.saveReminderTimes(list);
    if (_notif) await Notifier.schedule();
    if (mounted) toast(context, msg);
    await _load();
  }

  Future<void> _addReminderTime() async {
    if (_reminders.length >= Notifier.maxReminders) {
      toast(context, 'الحد الأقصى ${Notifier.maxReminders} أوقات في اليوم');
      return;
    }
    final picked = await _pickTime('إضافة وقت تذكير');
    if (picked == null) return;
    final v = _fmtTime(picked);
    if (_reminders.contains(v)) {
      if (mounted) toast(context, 'هذا الوقت مضاف مسبقاً');
      return;
    }
    await _saveReminders([..._reminders, v], 'تمت إضافة تذكير الساعة $v');
  }

  Future<void> _editReminderTime(String old) async {
    final picked = await _pickTime('تعديل وقت التذكير', old);
    if (picked == null) return;
    final v = _fmtTime(picked);
    if (v == old) return;
    if (_reminders.contains(v)) {
      if (mounted) toast(context, 'هذا الوقت مضاف مسبقاً');
      return;
    }
    await _saveReminders(
        [..._reminders.where((t) => t != old), v], 'تم تعديل الوقت إلى $v');
  }

  Future<void> _removeReminderTime(String t) async {
    if (_reminders.length <= 1) {
      toast(context, 'يجب أن يبقى وقت تذكير واحد على الأقل');
      return;
    }
    await _saveReminders(
        _reminders.where((x) => x != t).toList(), 'تم حذف تذكير الساعة $t');
  }

  Future<void> _setupSecurity() async {
    final me = _users.firstWhere((u) => u['id'] == currentUser?['id'],
        orElse: () => {});
    if (me.isEmpty) return;
    if (await showSecuritySetupDialog(context, me)) {
      if (mounted) toast(context, 'تم حفظ أسئلة الأمان');
      await _load();
    }
  }

  Future<void> _saveApp() async {
    await DB.setSetting('company_name', _company.text.trim());
    await DB.setSetting('soon_days', '$_soon');
    await loadAppSettings();
    if (mounted) toast(context, 'تم حفظ الإعدادات');
  }

  Future<void> _editUser(Map<String, dynamic> u) async {
    final own = u['id'] == currentUser?['id'];
    final name = TextEditingController(text: u['display_name'].toString());
    final uname = TextEditingController(text: u['username'].toString());
    final cur = TextEditingController();
    final np = TextEditingController();
    final np2 = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('تعديل ${u['display_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'الاسم')),
                const SizedBox(height: 10),
                TextField(
                    controller: uname,
                    decoration: const InputDecoration(labelText: 'اسم المستخدم')),
                const SizedBox(height: 10),
                if (own)
                  TextField(
                      controller: cur,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور الحالية (لتغييرها)')),
                if (own) const SizedBox(height: 10),
                TextField(
                    controller: np,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة مرور جديدة (اختياري)')),
                const SizedBox(height: 10),
                TextField(
                    controller: np2,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة')),
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
                if (uname.text.trim().isEmpty || name.text.trim().isEmpty) {
                  setS(() => err = 'الاسم واسم المستخدم مطلوبان');
                  return;
                }
                if (np.text.isNotEmpty) {
                  if (np.text.length < 4) {
                    setS(() => err = 'كلمة المرور 4 أحرف على الأقل');
                    return;
                  }
                  if (np.text != np2.text) {
                    setS(() => err = 'تأكيد كلمة المرور غير مطابق');
                    return;
                  }
                  if (own &&
                      hashPw(u['salt'].toString(), cur.text) != u['pass_hash']) {
                    setS(() => err = 'كلمة المرور الحالية غير صحيحة');
                    return;
                  }
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (!await confirmAction(context,
        title: 'تأكيد تعديل الحساب',
        message: 'هل تريد حفظ التعديلات على "${u['display_name']}"؟')) {
      return;
    }
    final upd = <String, dynamic>{
      'display_name': name.text.trim(),
      'username': uname.text.trim(),
    };
    if (np.text.isNotEmpty) {
      final salt = newSalt();
      upd['salt'] = salt;
      upd['pass_hash'] = hashPw(salt, np.text);
      upd['must_change'] = 0;
    }
    try {
      await DB.updateUser(u['id'] as int, upd);
      if (own) {
        currentUser = {...currentUser!, ...upd};
        if ((await DB.getSetting('biometric_user')) == u['username']) {
          await DB.setSetting('biometric_user', upd['username'].toString());
        }
      }
      if (mounted) toast(context, 'تم حفظ بيانات الحساب');
    } catch (_) {
      if (mounted) toast(context, 'اسم المستخدم مستخدم بالفعل');
    }
    await _load();
  }

  Future<void> _logout() async {
    currentUser = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات التطبيق',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                _section('الحسابات'),
                for (final u in _users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(u['role'] == 'main'
                              ? Icons.admin_panel_settings
                              : Icons.person),
                        ),
                        title: Text('${u['display_name']}'),
                        subtitle: Text(
                            '${u['username']}${u['id'] == currentUser?['id'] ? ' (أنت)' : ''}'),
                        trailing: (isMainUser || u['id'] == currentUser?['id'])
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editUser(u),
                              )
                            : null,
                      ),
                    ),
                  ),
                _section('الأمان'),
                AppCard(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('الدخول بالبصمة'),
                    subtitle: Text(_bioSupported
                        ? 'للحساب الحالي: ${currentUser?['username']}'
                        : 'غير مدعومة على هذا الجهاز'),
                    value: _bio,
                    onChanged: _bioSupported ? _toggleBio : null,
                  ),
                ),
                const SizedBox(height: 8),
                AppCard(
                  child: ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('أسئلة الأمان (استعادة كلمة السر)'),
                    subtitle: Text(hasSecurityQuestions(_users.firstWhere(
                            (u) => u['id'] == currentUser?['id'],
                            orElse: () => {}))
                        ? 'مُفعّلة - اضغط للتغيير'
                        : 'غير مضبوطة - اضغط لاختيار سؤالين'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: _setupSecurity,
                  ),
                ),
                _section('الإشعارات'),
                AppCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_active_outlined),
                        title: const Text('إشعارات المتأخرات والاستحقاق'),
                        subtitle: const Text('تذكير يومي في الأوقات المحددة أدناه (يمكن أكثر من وقت)'),
                        value: _notif,
                        onChanged: _toggleNotif,
                      ),
                      ListTile(
                        leading: Icon(
                            _permission ? Icons.check_circle : Icons.error_outline,
                            color: _permission ? Colors.green : Colors.orange),
                        title: Text(_permission
                            ? 'صلاحية الإشعارات ممنوحة'
                            : 'صلاحية الإشعارات غير ممنوحة'),
                        trailing: _permission
                            ? null
                            : TextButton(
                                onPressed: () async {
                                  await Notifier.requestPermission();
                                  await _load();
                                },
                                child: const Text('طلب الصلاحية'),
                              ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: Text(
                            'أوقات التذكير اليومي (${_reminders.length})'),
                        subtitle: const Text(
                            'يصلك تنبيه في كل وقت من هذه الأوقات يومياً. يعمل في الخلفية وقد يتأخر قليلاً حسب نظام الهاتف'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final t in _reminders)
                                InputChip(
                                  avatar: const Icon(Icons.alarm, size: 18),
                                  label: Text(t,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15)),
                                  onPressed: () => _editReminderTime(t),
                                  onDeleted: () => _removeReminderTime(t),
                                ),
                              ActionChip(
                                avatar: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة وقت'),
                                onPressed: _addReminderTime,
                              ),
                            ],
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.send_outlined),
                        title: const Text('إرسال إشعار تجريبي'),
                        onTap: () async {
                          await Notifier.show('تنبيه تجريبي', 'الإشعارات تعمل بنجاح ✅');
                        },
                      ),
                    ],
                  ),
                ),
                _section('النسخ الاحتياطي'),
                AppCard(
                  child: ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('النسخ الاحتياطي والاستعادة'),
                    subtitle: Text(_lastBackup),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BackupScreen()));
                      if (mounted) await _load();
                    },
                  ),
                ),
                _section('بيانات التطبيق'),
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _company,
                          decoration: const InputDecoration(
                              labelText: 'اسم المكتب/المالك (يظهر في الإيصالات)',
                              prefixIcon: Icon(Icons.business_outlined)),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _soon,
                          items: const [1, 2, 3, 5, 7, 10]
                              .map((d) => DropdownMenuItem(
                                  value: d, child: Text('قبل الاستحقاق بـ $d يوم')))
                              .toList(),
                          onChanged: (v) => setState(() => _soon = v ?? 3),
                          decoration: const InputDecoration(
                              labelText: 'موعد تنبيه قرب الاستحقاق',
                              prefixIcon: Icon(Icons.schedule)),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: _saveApp, child: const Text('حفظ')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                ),
              ],
            ),
    );
  }
}
