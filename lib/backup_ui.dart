import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:share_plus/share_plus.dart';

import 'auth.dart';
import 'backup.dart';
import 'db.dart';
import 'security.dart';
import 'smb_backup.dart';
import 'utils.dart';

String _fmtDateTime(DateTime d) =>
    intl.DateFormat('yyyy/MM/dd  HH:mm').format(d);

String _fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String lastBackupText(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return d == null ? 'لم يتم عمل نسخة بعد' : 'آخر نسخة: ${_fmtDateTime(d)}';
}

// ---------------------------------------------------------
// شاشة النسخ الاحتياطي والاستعادة
// ---------------------------------------------------------
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _loading = true;
  bool _auto = false;
  int _hours = 24;
  String _next = '';
  final _hoursC = TextEditingController();
  bool _hoursLoaded = false;
  int _keep = 10;
  bool _primaryOk = false;
  String _folder = '';
  String _last = '';
  List<BackupInfo> _list = [];

  // ---- نسخة على كمبيوتر ويندوز (مجلد مشترك على الشبكة) ----
  bool _smbOn = false;
  bool _smbLoaded = false;
  bool _smbHide = true;
  bool _smbPending = false;
  String _smbErr = '';
  String _smbLastText = '';
  final _smbPath = TextEditingController();
  final _smbUser = TextEditingController();
  final _smbPass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hoursC.dispose();
    _smbPath.dispose();
    _smbUser.dispose();
    _smbPass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auto = (await DB.getSetting('backup_auto')) == '1';
    final hours = await BackupService.intervalHours();
    final nextDt = await BackupService.nextAutoBackup();
    final keep = int.tryParse(await DB.getSetting('backup_keep') ?? '') ?? 10;
    final ok = await BackupService.primaryWritable();
    final dir = await BackupService.resolveDir();
    final list = await BackupService.list();
    final last = lastBackupText(await DB.getSetting('backup_last'));
    final smbOn = await SmbBackup.enabled();
    final smbErr = await SmbBackup.lastError();
    final smbPending = await SmbBackup.hasPending();
    final smbLast = await SmbBackup.lastUpload();
    if (!_smbLoaded) {
      _smbPath.text = await SmbBackup.path();
      _smbUser.text = await SmbBackup.user();
      _smbPass.text = await SmbBackup.pass();
      _smbLoaded = true;
    }
    if (!mounted) return;
    setState(() {
      _smbOn = smbOn;
      _smbErr = smbErr;
      _smbPending = smbPending;
      _smbLastText = smbLast == null
          ? 'لم يتم الرفع إلى الكمبيوتر بعد'
          : 'آخر رفع للكمبيوتر: ${_fmtDateTime(smbLast)}';
      _auto = auto;
      _hours = hours;
      if (!_hoursLoaded) {
        _hoursC.text = '$hours';
        _hoursLoaded = true;
      }
      _next = nextDt == null ? '' : 'النسخة التلقائية القادمة تقريباً: ${_fmtDateTime(nextDt)}';
      _keep = [5, 10, 20, 30].contains(keep) ? keep : 10;
      _primaryOk = ok;
      _folder = dir.path;
      _list = list;
      _last = last;
      _loading = false;
    });
  }

  Future<T?> _busy<T>(String msg, Future<T> Function() job) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(msg)),
          ]),
        ),
      ),
    );
    try {
      return await job();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ---------- الصلاحية والمجلد ----------
  Future<void> _requestPermission() async {
    final ok = await BackupService.requestStoragePermission();
    if (mounted && !ok) {
      toast(context,
          'لم تُمنح صلاحية الوصول للملفات. فعّلها من إعدادات الهاتف > التطبيقات > RentPal > الأذونات');
    }
    await _load();
  }

  Future<void> _changeFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;
    final old = await DB.getSetting('backup_dir') ?? '';
    await DB.setSetting('backup_dir', path);
    if (!await BackupService.primaryWritable()) {
      await DB.setSetting('backup_dir', old);
      if (mounted) {
        toast(context, 'تعذرت الكتابة في هذا المجلد. امنح صلاحية الملفات أو اختر مجلداً آخر');
      }
    } else if (mounted) {
      toast(context, 'تم تغيير مجلد النسخ الاحتياطي');
    }
    await _load();
  }

  Future<void> _resetFolder() async {
    await DB.setSetting('backup_dir', '');
    await _load();
  }

  // ---------- النسخ ----------
  Future<void> _saveHours() async {
    final h = int.tryParse(_hoursC.text.trim());
    if (h == null || h < 1 || h > 720) {
      toast(context, 'اكتب عدد ساعات صحيح من 1 إلى 720');
      return;
    }
    FocusScope.of(context).unfocus();
    await BackupService.setIntervalHours(h);
    await BackupService.schedule();
    if (mounted) toast(context, 'تم حفظ التوقيت: نسخة كل $h ساعة');
    await _load();
  }

  Future<void> _share(BackupInfo b) async {
    try {
      await Share.shareXFiles([XFile(b.file.path)],
          text: 'نسخة RentPal الاحتياطية - ${_fmtDateTime(b.modified)}');
    } catch (e) {
      if (mounted) toast(context, 'تعذرت المشاركة: ${_err(e)}');
    }
  }

  Future<void> _scanPcs() async {
    final ips = await _busy<List<String>>(
        'جاري البحث عن الكمبيوترات على شبكة الواي فاي...',
        () => SmbBackup.scanLan());
    if (!mounted || ips == null) return;
    if (ips.isEmpty) {
      toast(context,
          'لم يتم العثور على كمبيوتر. تأكد أن الهاتف على نفس الواي فاي وأن مشاركة الملفات مفعّلة على الكمبيوتر');
      return;
    }
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختر الكمبيوتر'),
        children: [
          for (final i in ips)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Row(children: [
                const Icon(Icons.computer_outlined),
                const SizedBox(width: 12),
                Text(i, textDirection: TextDirection.ltr),
              ]),
            ),
        ],
      ),
    );
    if (ip == null) return;
    _smbPath.text = '\\\\$ip\\';
    _smbPath.selection = TextSelection.collapsed(offset: _smbPath.text.length);
    if (mounted) toast(context, 'أكمل بكتابة اسم المجلد المشترك بعد العنوان ثم اضغط «حفظ واختبار الاتصال»');
  }

  Future<void> _uploadLatest() async {
    if (_list.isEmpty) {
      toast(context, 'لا توجد نسخة لرفعها، اضغط «نسخ احتياطي الآن» أولاً');
      return;
    }
    await _uploadOne(_list.first);
  }

  Future<void> _toggleAuto(bool v) async {
    if (v) {
      if (!_primaryOk) await BackupService.requestStoragePermission();
      await DB.setSetting('backup_auto', '1');
      await BackupService.schedule();
      await _busy('جاري عمل أول نسخة احتياطية...',
          () => BackupService.autoIfDue(force: true));
      if (mounted) toast(context, 'تم تفعيل النسخ الاحتياطي التلقائي');
    } else {
      await DB.setSetting('backup_auto', '0');
      await BackupService.cancel();
    }
    await _load();
  }

  Future<void> _backupNow() async {
    try {
      final f = await _busy('جاري إنشاء النسخة الاحتياطية...',
          () => BackupService.createBackup());
      if (mounted && f != null) {
        var msg = 'تم حفظ النسخة في:\n${f.path}';
        final r = BackupService.lastSmbResult;
        if (r == true) msg += '\nوتم رفع نسخة إلى الكمبيوتر ✅';
        if (r == false) {
          msg +=
              '\nتعذر الرفع للكمبيوتر: ${await SmbBackup.lastError()}\nستُعاد المحاولة تلقائياً';
        }
        if (mounted) toast(context, msg);
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل النسخ الاحتياطي: ${_err(e)}');
    }
    await _load();
  }

  // ---------- كمبيوتر ويندوز (مجلد مشترك) ----------
  Future<void> _toggleSmb(bool v) async {
    await SmbBackup.setEnabled(v);
    await _load();
  }

  Future<bool> _saveSmb() async {
    if (SmbBackup.parseTarget(_smbPath.text) == null) {
      toast(context,
          'اكتب عنوان المجلد المشترك بالشكل: \\\\192.168.1.5\\اسم_المجلد');
      return false;
    }
    if (_smbUser.text.trim().isEmpty) {
      toast(context, 'اكتب اسم مستخدم ويندوز');
      return false;
    }
    await SmbBackup.saveConfig(_smbPath.text, _smbUser.text, _smbPass.text);
    return true;
  }

  Future<void> _testSmb() async {
    if (!await _saveSmb()) return;
    try {
      await _busy<void>(
          'جاري اختبار الاتصال بالكمبيوتر...', () => SmbBackup.test());
      if (mounted) {
        toast(context, 'تم الاتصال بالكمبيوتر والكتابة في المجلد بنجاح ✅');
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل الاتصال: ${SmbBackup.explain(e)}');
    }
  }

  Future<void> _uploadOne(BackupInfo b) async {
    if (!await SmbBackup.configured()) {
      if (mounted) toast(context, 'احفظ بيانات الكمبيوتر أولاً (زر حفظ واختبار الاتصال)');
      return;
    }
    try {
      await _busy<void>(
          'جاري الرفع إلى الكمبيوتر...', () => SmbBackup.upload(b.file));
      if (mounted) toast(context, 'تم رفع النسخة إلى الكمبيوتر ✅');
    } catch (e) {
      if (mounted) toast(context, 'تعذر الرفع: ${SmbBackup.explain(e)}');
    }
    await _load();
  }

  // ---------- الاستعادة ----------
  Future<void> _pickAndRestore() async {
    if (!_checkMain()) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    await _confirmRestore(File(path), path.split('/').last);
  }

  bool _checkMain() {
    if (isMainUser) return true;
    toast(context, 'استعادة النسخ متاحة للحساب الرئيسي فقط');
    return false;
  }

  Future<void> _confirmRestore(File f, String name) async {
    if (!_checkMain()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Text(
            'سيتم استبدال كل البيانات الحالية (العقارات والمدفوعات والحسابات والإعدادات) بمحتوى:\n\n$name\n\n'
            'سيتم حفظ نسخة من البيانات الحالية تلقائياً قبل الاستبدال، وستحتاج لتسجيل الدخول من جديد.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await biometricAuth(context, 'تأكيد استعادة النسخة الاحتياطية')) return;
    try {
      await _busy('جاري استعادة البيانات...', () => BackupService.restore(f));
    } catch (e) {
      if (mounted) toast(context, 'فشلت الاستعادة: ${_err(e)}');
      await _load();
      return;
    }
    if (!mounted) return;
    currentUser = null;
    toast(context, 'تمت استعادة النسخة بنجاح، سجّل الدخول من جديد');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  Future<void> _delete(BackupInfo b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف النسخة'),
        content: Text('حذف ${b.name} نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await biometricAuth(context, 'تأكيد حذف النسخة')) return;
    try {
      await b.file.delete();
    } catch (_) {
      if (mounted) toast(context, 'تعذر حذف الملف');
    }
    await _load();
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
        title: const Text('النسخ الاحتياطي والاستعادة',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                _section('مكان الحفظ (التخزين الداخلي)'),
                AppCard(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('المجلد'),
                        subtitle: SelectableText(_folder,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start),
                      ),
                      if (!_primaryOk)
                        ListTile(
                          leading: const Icon(Icons.error_outline,
                              color: Colors.orange),
                          title: const Text(
                              'لا توجد صلاحية للتخزين الداخلي، تُحفظ النسخ حالياً في مجلد خاص بالتطبيق'),
                          trailing: TextButton(
                              onPressed: _requestPermission,
                              child: const Text('منح الصلاحية')),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _changeFolder,
                                icon: const Icon(Icons.drive_file_move_outline),
                                label: const Text('تغيير المجلد'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                                onPressed: _resetFolder,
                                child: const Text('الافتراضي')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _section('نسخة إضافية على كمبيوتر ويندوز (شبكة)'),
                AppCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.computer_outlined),
                        title: const Text('رفع نسخة إلى كمبيوتر ويندوز'),
                        subtitle: const Text(
                            'بالإضافة للنسخة المحفوظة على الهاتف (أوفلاين)، تُرفع نسخة إلى مجلد مشترك على الكمبيوتر'),
                        value: _smbOn,
                        onChanged: _toggleSmb,
                      ),
                      if (_smbOn) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Column(
                            children: [
                              TextField(
                                controller: _smbPath,
                                textDirection: TextDirection.ltr,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'عنوان المجلد المشترك',
                                  hintText: r'\\192.168.1.5\RealEstateBackups',
                                  prefixIcon: Icon(Icons.folder_shared_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _smbUser,
                                textDirection: TextDirection.ltr,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'اسم مستخدم ويندوز',
                                  hintText: 'user  أو  PCNAME\\user',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _smbPass,
                                textDirection: TextDirection.ltr,
                                obscureText: _smbHide,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: InputDecoration(
                                  labelText: 'كلمة مرور ويندوز',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_smbHide
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () =>
                                        setState(() => _smbHide = !_smbHide),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: _testSmb,
                                  icon: const Icon(Icons.wifi_tethering),
                                  label: const Text('حفظ واختبار الاتصال'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _scanPcs,
                                    icon: const Icon(Icons.search),
                                    label: const Text('بحث عن الكمبيوتر'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _uploadLatest,
                                    icon: const Icon(Icons.cloud_upload_outlined),
                                    label: const Text('رفع آخر نسخة الآن'),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        ListTile(
                          leading: Icon(
                              _smbErr.isNotEmpty
                                  ? Icons.error_outline
                                  : Icons.cloud_done_outlined,
                              color: _smbErr.isNotEmpty
                                  ? Colors.orange
                                  : Colors.green),
                          title: Text(_smbErr.isNotEmpty
                              ? 'آخر محاولة رفع فشلت: $_smbErr'
                              : _smbLastText),
                          subtitle: _smbPending
                              ? const Text(
                                  'ستُعاد المحاولة تلقائياً عند توفر الكمبيوتر على الشبكة')
                              : null,
                        ),
                        const ExpansionTile(
                          leading: Icon(Icons.help_outline),
                          title: Text('كيف أجهّز الكمبيوتر؟'),
                          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '1) على الكمبيوتر أنشئ مجلداً (مثلاً RealEstateBackups) ثم كليك يمين > Properties > Sharing > Advanced Sharing، فعّل Share this folder ثم Permissions وأعطِ مستخدمك Full Control.\n\n'
                                '2) تأكد أن الهاتف والكمبيوتر على نفس شبكة الواي فاي.\n\n'
                                '3) لمعرفة عنوان الكمبيوتر: افتح CMD واكتب ipconfig وخذ IPv4 Address، ثم اكتب هنا: \\\\IP\\RealEstateBackups\n\n'
                                '4) اسم المستخدم وكلمة المرور هما حساب ويندوز الذي تدخل به الكمبيوتر (يجب أن يكون له كلمة مرور). إن كان حسابك Microsoft فاستخدم بريده الإلكتروني وكلمة مروره.'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                _section('النسخ الاحتياطي'),
                AppCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.autorenew),
                        title: const Text('نسخ احتياطي تلقائي'),
                        subtitle: const Text(
                            'يحفظ نسخة كاملة (البيانات + الصور) في المجلد تلقائياً'),
                        value: _auto,
                        onChanged: _toggleAuto,
                      ),
                      if (_auto)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Column(
                            children: [
                              TextField(
                                controller: _hoursC,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _saveHours(),
                                decoration: InputDecoration(
                                  labelText: 'توقيت النسخ الاحتياطي: كل كم ساعة؟',
                                  helperText: 'من 1 إلى 720 ساعة (مثال: 6 = أربع نسخ يومياً)',
                                  prefixIcon: const Icon(Icons.schedule),
                                  suffixText: 'ساعة',
                                  suffixIcon: IconButton(
                                    tooltip: 'حفظ',
                                    icon: const Icon(Icons.check_circle_outline),
                                    onPressed: _saveHours,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    for (final h in const [1, 3, 6, 12, 24, 72, 168])
                                      ChoiceChip(
                                        label: Text(h == 24
                                            ? 'يومياً'
                                            : h == 168
                                                ? 'أسبوعياً'
                                                : h == 72
                                                    ? '3 أيام'
                                                    : '$h ساعة'),
                                        selected: _hours == h,
                                        onSelected: (_) {
                                          _hoursC.text = '$h';
                                          _saveHours();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              if (_next.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(_next,
                                      style: const TextStyle(
                                          color: Colors.black54, fontSize: 12.5)),
                                ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                value: _keep,
                                items: const [5, 10, 20, 30]
                                    .map((n) => DropdownMenuItem(
                                        value: n,
                                        child: Text('الاحتفاظ بآخر $n نسخة')))
                                    .toList(),
                                onChanged: (v) async {
                                  await DB.setSetting('backup_keep', '${v ?? 10}');
                                  setState(() => _keep = v ?? 10);
                                },
                                decoration: const InputDecoration(
                                    labelText: 'عدد النسخ التلقائية المحفوظة',
                                    prefixIcon: Icon(Icons.inventory_2_outlined)),
                              ),
                            ],
                          ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(_last),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _backupNow,
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('نسخ احتياطي الآن'),
                          ),
                        ),
                      ),
                      if (_list.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _share(_list.first),
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('إرسال آخر نسخة (واتساب / Drive / كمبيوتر)'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _section('استيراد نسخة احتياطية'),
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickAndRestore,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('اختيار ملف نسخة احتياطية (ZIP)'),
                      ),
                    ),
                  ),
                ),
                _section('النسخ الموجودة في المجلد (${_list.length})'),
                if (_list.isEmpty)
                  const AppCard(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('لا توجد نسخ احتياطية بعد')),
                    ),
                  ),
                for (final b in _list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.archive_outlined)),
                        title: Text(_fmtDateTime(b.modified)),
                        subtitle: Text('${b.kindLabel} • ${_fmtSize(b.size)}'),
                        onTap: () => _confirmRestore(b.file, b.name),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'restore') _confirmRestore(b.file, b.name);
                            if (v == 'delete') _delete(b);
                            if (v == 'smb') _uploadOne(b);
                            if (v == 'share') _share(b);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'restore', child: Text('استعادة')),
                            if (_smbOn)
                              const PopupMenuItem(
                                  value: 'smb',
                                  child: Text('رفع إلى الكمبيوتر')),
                            const PopupMenuItem(
                                value: 'share',
                                child: Text('مشاركة / إرسال الملف')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
