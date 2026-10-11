import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'assistant.dart';
import 'auth.dart';
import 'contract.dart';
import 'db.dart';
import 'finance.dart';
import 'map_picker.dart';
import 'paper_picker.dart';
import 'pdf_export.dart';
import 'property_detail.dart';
import 'property_form.dart';
import 'report_screen.dart';
import 'security.dart';
import 'smooth.dart';
import 'tenants_screen.dart';
import 'utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];
  Map<int, Map<String, List<String>>> _atts = {};
  bool _alertsShown = false;
  String _query = '';
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DB.all();
    final pays = await DB.payments();
    final atts = await DB.attachmentMap();
    if (!mounted) return;
    setState(() {
      _items = data;
      _payments = pays;
      _atts = atts;
      _loading = false;
    });
    if (!_alertsShown && (_alerts.isNotEmpty || _contractAlerts.isNotEmpty)) {
      _alertsShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAlerts();
      });
    }
  }

  List<Map<String, dynamic>> get _alerts => computeAlerts(_items);
  List<Map<String, dynamic>> get _contractAlerts => computeContractAlerts(_items);

  Future<void> _renew(Map<String, dynamic> item) async {
    final ok = await showRenewDialog(context, item);
    if (ok) await _load();
  }

  Future<void> _contractMessage(Map<String, dynamic> item) async {
    final saved = await showContractMessageDialog(context, item);
    if (saved) await _load();
  }

  Future<void> _whatsappContract(Map<String, dynamic> item) async {
    final t = item['tenant_name'];
    final n = item['name'];
    final e = contractEndOf(item);
    final left = contractDaysLeft(item) ?? 0;
    final endStr = e == null ? '' : fmtDate(e);
    final msg = left < 0
        ? 'أهلاً $t، نود إحاطتكم بأن عقد إيجار $n انتهى بتاريخ $endStr. برجاء التواصل معنا لتجديد العقد.'
        : 'أهلاً $t، نود تذكيركم بأن عقد إيجار $n ينتهي بتاريخ $endStr. برجاء التواصل معنا لتجديد العقد.';
    await launchWa(context, phoneOf(item), msg);
  }

  Widget _contractTile(BuildContext ctx, Map<String, dynamic> it) {
    final left = contractDaysLeft(it) ?? 0;
    final c = left < 0 ? const Color(0xFFC62828) : const Color(0xFFEF6C00);
    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: c.withAlpha(30),
        child: Icon(Icons.description_outlined, color: c),
      ),
      title: Text('${it['tenant_name']} - ${it['name']}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
          '${left < 0 ? 'العقد منتهي' : 'العقد يقارب على الانتهاء'}\n${contractText(it)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'واتساب',
            icon: const Icon(Icons.chat, color: Color(0xFF2E7D32)),
            onPressed: () => _whatsappContract(it),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PropertyFormScreen(property: item)),
    );
    if (saved == true) {
      await _load();
      if (mounted) toast(context, item == null ? 'تمت إضافة العقار' : 'تم تحديث العقار');
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(propertyId: item['id'] as int)),
    );
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العقار'),
        content: Text('هل تريد حذف "${item['name']}" نهائياً؟\n(سجل الإيصالات القديمة يبقى محفوظاً)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true && mounted && await biometricAuth(context, 'تأكيد حذف العقار')) {
      final id = item['id'] as int;
      final files = [...?_atts[id]?['id'], ...?_atts[id]?['contract']];
      await DB.delete(id);
      for (final f in files) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
      await _load();
      if (mounted) toast(context, 'تم حذف العقار');
    }
  }

  Future<void> _whatsapp(Map<String, dynamic> item, String type) async {
    final a = fmt(totalDue(item));
    final t = item['tenant_name'];
    final n = item['name'];
    final d = parseDue(item['due_date']);
    final dueStr = d == null ? '' : ' (تاريخ الاستحقاق ${fmtDate(d)})';
    String msg;
    if (type == 'reminder') {
      msg = 'أهلاً $t، نود تذكيرك بقرب موعد سداد إيجار $n وقيمته الإجمالية $a$dueStr.';
    } else if (type == 'late') {
      msg = 'عزيزي $t، نود إحاطتكم بتأخر سداد مستحقات $n وقيمتها $a$dueStr. نرجو السداد في أقرب وقت.';
    } else {
      msg = 'شكراً لك $t على التزامك بسداد مستحقات $n.';
    }
    await launchWa(context, phoneOf(item), msg);
  }

  Future<void> _pay(Map<String, dynamic> item) async {
    final ok = await showPayDialog(context, item);
    if (ok) await _load();
  }

  List<Map<String, dynamic>> get _filtered {
    return _items.where((i) {
      if (_filter != null && effStatus(i) != _filter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return '${i['name']} ${i['tenant_name']} ${i['address']} ${i['location']}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  // ---------------- التنبيهات ----------------
  void _showAlerts() {
    final list = _alerts;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('التنبيهات (${list.length + _contractAlerts.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (list.isEmpty && _contractAlerts.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24), child: Text('لا توجد تنبيهات حالياً'))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length + _contractAlerts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, k) {
                      if (k >= list.length) {
                        return _contractTile(ctx, _contractAlerts[k - list.length]);
                      }
                      final it = list[k];
                      final d = daysUntilDue(it);
                      final late = d == null || d < 0;
                      final c = late ? const Color(0xFFC62828) : const Color(0xFFEF6C00);
                      final dd = parseDue(it['due_date']);
                      String sub;
                      if (d == null || dd == null) {
                        sub = 'متأخر (لم يُحدد تاريخ استحقاق)';
                      } else if (d < 0) {
                        sub = 'متأخر منذ ${fmtDate(dd)} (${-d} يوم)';
                      } else if (d == 0) {
                        sub = 'يستحق اليوم';
                      } else {
                        sub = 'يستحق ${fmtDate(dd)} (بعد $d يوم)';
                      }
                      return ListTile(
                        isThreeLine: true,
                        leading: CircleAvatar(
                          backgroundColor: c.withAlpha(30),
                          child: Icon(late ? Icons.warning_amber_rounded : Icons.schedule,
                              color: c),
                        ),
                        title: Text('${it['tenant_name']} - ${it['name']}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('$sub\nالمستحق: ${fmt(totalDue(it))}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'واتساب',
                              icon: const Icon(Icons.chat, color: Color(0xFF2E7D32)),
                              onPressed: () => _whatsapp(it, late ? 'late' : 'reminder'),
                            ),
                            IconButton(
                              tooltip: 'تسجيل سداد',
                              icon: const Icon(Icons.payments_outlined),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _pay(it);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['العقارات', 'المستأجرون', 'التقارير المالية'];
    return Scaffold(
      appBar: _tab == 0
          ? _homeHeader()
          : AppBar(
              title: Text(titles[_tab],
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              actions: [_bellButton(), _settingsButton()],
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, 0.02), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_loading ? 'loading' : 'tab$_tab'),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_tab == 0
                      ? _propertiesTab()
                      : _tab == 1
                          ? TenantsTab(items: _items, onReload: _load)
                          : _reportsTab()),
            ),
          ),
          // زر المساعد العائم (يظهر في كل التبويبات)
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: _assistantFab(),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedScale(
        scale: _tab == 0 ? 1 : 0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        child: _addFab(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: Icon(Icons.home_work_outlined),
              selectedIcon: Icon(Icons.home_work),
              label: 'العقارات'),
          NavigationDestination(
              icon: Badge(
                label: Text('${_alerts.length + _contractAlerts.length}'),
                isLabelVisible: _alerts.isNotEmpty || _contractAlerts.isNotEmpty,
                child: const Icon(Icons.people_outline),
              ),
              selectedIcon: const Icon(Icons.people),
              label: 'المستأجرون'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'التقارير'),
        ],
      ),
    );
  }

  // ---------------- الهيدر والأزرار العائمة ----------------
  String _greeting() {
    final h = DateTime.now().hour;
    return (h >= 5 && h < 12) ? 'صباح الخير' : 'مساء الخير';
  }

  /// اسم المستخدم للترحيب (يُتجاهل الاسم الافتراضي للحسابات الأساسية)
  String _userName() {
    final n = (currentUser?['display_name'] ?? '').toString().trim();
    if (n.isEmpty || n.startsWith('الحساب')) return '';
    return n;
  }

  Widget _bellButton() => IconButton(
        tooltip: 'التنبيهات',
        onPressed: _showAlerts,
        icon: Badge(
          label: Text('${_alerts.length + _contractAlerts.length}'),
          isLabelVisible: _alerts.isNotEmpty || _contractAlerts.isNotEmpty,
          child: const Icon(Icons.notifications_outlined),
        ),
      );

  Widget _settingsButton() => IconButton(
        tooltip: 'الإعدادات',
        onPressed: _openSettings,
        icon: const Icon(Icons.settings_outlined),
      );

  PreferredSizeWidget _homeHeader() {
    final cs = Theme.of(context).colorScheme;
    final name = _userName();
    return AppBar(
      toolbarHeight: 76,
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 16,
      title: Row(
        children: [
          // لوجو البرنامج بدل صورة المستخدم
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withAlpha(60), width: 2),
              boxShadow: [
                BoxShadow(
                    color: cs.primary.withAlpha(40),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/logo.png',
                  width: 46, height: 46, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? _greeting() : '${_greeting()} يا $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600),
                ),
                const Text('العقارات',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          _bellButton(),
          _settingsButton(),
        ],
      ),
    );
  }

  void _openAssistant() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AssistantScreen(items: _items, pays: _payments)));

  Widget _assistantFab() => Tooltip(
        message: 'تحدث مع المساعد',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: const Color(0xFF7C4DFF).withAlpha(120),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openAssistant,
            child: Ink(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF7C4DFF), Color(0xFF2A8AB8)],
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                  SizedBox(height: 1),
                  Text('المساعد',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _addFab() {
    const c = Color(0xFF0E8AA8);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      elevation: 8,
      shadowColor: c.withAlpha(130),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _tab == 0 ? () => _openForm() : null,
        child: Ink(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF17A2C2), Color(0xFF0B7C99)],
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: Colors.white, size: 28),
              Text('إضافة عقار',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- العقارات ----------------
  Future<void> _openFilterSheet() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('تصفية العقارات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: Icon(_filter == null ? Icons.check_circle : Icons.circle_outlined),
              title: const Text('الكل'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final s in kStatuses)
              ListTile(
                leading: Icon(_filter == s ? Icons.check_circle : Icons.circle_outlined,
                    color: statusColor(s)),
                title: Text(s),
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (r != null) setState(() => _filter = r.isEmpty ? null : r);
  }

  Widget _statTile(String label, int n, Color c, String status) {
    final on = _filter == status;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _filter = on ? null : status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: on ? Colors.black87 : Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(color: c.withAlpha(70), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withAlpha(60),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.apartment, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$label: $n',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _propertiesTab() {
    final list = _filtered;
    final al = _alerts;
    final lateCount = al.where((i) => (daysUntilDue(i) ?? -1) < 0).length;
    final soonCount = al.length - lateCount;
    final ca = _contractAlerts;
    final expiredContracts = ca.where((i) => (contractDaysLeft(i) ?? 0) < 0).length;
    final rented = _items.where((i) => effStatus(i) == 'مؤجر').length;
    final vacant = _items.where((i) => effStatus(i) == 'شاغر').length;
    final lateProps = _items.where((i) => effStatus(i) == 'متأخرات').length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'ابحث بالعقار، المستأجر أو الموقع...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'تصفية',
                onPressed: _openFilterSheet,
                icon: Badge(
                  isLabelVisible: _filter != null,
                  smallSize: 8,
                  child: const Icon(Icons.tune),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (al.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF6F6A),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'تنبيهات: $lateCount متأخر • $soonCount قريب الاستحقاق',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _showAlerts,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7F0F1E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('إرسال تذكير',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        if (ca.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _showAlerts,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF6C00).withAlpha(25),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, color: Color(0xFFEF6C00)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'عقود: $expiredContracts منتهي • ${ca.length - expiredContracts} ينتهي خلال شهرين',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.chevron_left),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _statTile('مؤجر', rented, const Color(0xFF43A047), 'مؤجر'),
              const SizedBox(width: 12),
              _statTile('شاغر', vacant, const Color(0xFFF58220), 'شاغر'),
              if (lateProps > 0) ...[
                const SizedBox(width: 12),
                _statTile('متأخرات', lateProps, const Color(0xFFC62828), 'متأخرات'),
              ],
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 214,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => FadeSlideIn(
                      key: ValueKey(list[i]['id']),
                      index: i,
                      child: _propertyCard(list[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    final has = _items.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(has ? Icons.search_off : Icons.apartment, size: 72, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              has ? 'لا توجد نتائج مطابقة' : 'لا توجد عقارات بعد\nاضغط "إضافة عقار" للبدء',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة العقار (شبكة من عمودين) — الضغط عليها يفتح شيت الإجراءات
  Widget _propertyCard(Map<String, dynamic> item) {
    final status = effStatus(item);
    final color = statusColor(status);
    final total = totalDue(item);
    final tenant = '${item['tenant_name'] ?? ''}'.trim();
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showActions(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 76,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [color.withAlpha(45), color.withAlpha(15)],
                  ),
                ),
                child: Icon(propertyTypeIcon(item['ptype']), size: 42, color: color),
              ),
              const SizedBox(height: 8),
              Text('${item['name'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14, height: 1.25)),
              const Spacer(),
              Row(
                children: [
                  _statusChip(status, color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tenant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(fmt(total),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- شيت إجراءات العقار ----------------
  void _showActions(Map<String, dynamic> item) {
    final tenant = '${item['tenant_name'] ?? ''}'.trim();
    final atts = _atts[item['id'] as int];

    void run(BuildContext ctx, VoidCallback f) {
      Navigator.pop(ctx);
      f();
    }

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(t,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFBF5),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('${item['name'] ?? ''}',
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                if (tenant.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('المستأجر: $tenant',
                        style: const TextStyle(fontSize: 15, color: Colors.black87)),
                  ),
                const SizedBox(height: 16),
                // زر السداد الرئيسي
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => run(ctx, () => _pay(item)),
                  child: Ink(
                    height: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                          colors: [Color(0xFF2F8BEA), Color(0xFF1B5CAE)]),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF1B5CAE).withAlpha(90),
                            blurRadius: 14,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.attach_money, color: Colors.white, size: 28),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text('تسجيل سداد الإيجار',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _sheetTile('تجديد العقد', Icons.autorenew,
                            const Color(0xFFE3EEFB), const Color(0xFF1B5CAE),
                            () => run(ctx, () => _renew(item))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _sheetTile('الحساب والمدفوعات والمرافق',
                            Icons.account_balance, const Color(0xFFE3EEFB),
                            const Color(0xFF1B5CAE),
                            () => run(ctx, () => _openDetail(item))),
                      ),
                    ],
                  ),
                ),
                sectionTitle('رسالة العقد'),
                _sheetTile('رسالة بقيمة العقد الجديدة', Icons.forum,
                    const Color(0xFFD9F0EE), const Color(0xFF0E7C86),
                    () => run(ctx, () => _contractMessage(item))),
                sectionTitle('التواصل السريع'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _quickCircle('تذكير', Icons.notifications_active,
                        const Color(0xFFF9A03F), const Color(0xFFFFE4C2),
                        () => run(ctx, () => _whatsapp(item, 'reminder'))),
                    _quickCircle('تأخير', Icons.warning_amber_rounded,
                        const Color(0xFFD32F2F), const Color(0xFFFAC9C9),
                        () => run(ctx, () => _whatsapp(item, 'late'))),
                    _quickCircle('شكر', Icons.favorite, const Color(0xFF2E7D32),
                        const Color(0xFFCDEBCF),
                        () => run(ctx, () => _whatsapp(item, 'thanks'))),
                  ],
                ),
                if (atts != null) ...[
                  _thumbs('صور البطاقة', atts['id'] ?? []),
                  _thumbs('صور العقد', atts['contract'] ?? []),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _sheetTile('تعديل', Icons.edit,
                          const Color(0xFFE4E6EA), Colors.black87,
                          () => run(ctx, () => _openForm(item)), center: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _sheetTile('حذف', Icons.delete_outline,
                          const Color(0xFFFCE4E4), const Color(0xFFC62828),
                          () => run(ctx, () => _delete(item)), center: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(String label, IconData icon, Color bg, Color fg,
      VoidCallback onTap, {bool center = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: fg.withAlpha(35)),
        ),
        child: Row(
          mainAxisAlignment:
              center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (!center) ...[
              CircleAvatar(
                radius: 20,
                backgroundColor: fg.withAlpha(30),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      color: center ? fg : Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.3)),
            ),
            if (center) ...[
              const SizedBox(width: 8),
              Icon(icon, color: fg, size: 22),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickCircle(
      String label, IconData icon, Color fg, Color bg, VoidCallback onTap) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Ink(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(color: fg.withAlpha(110)),
          boxShadow: [
            BoxShadow(color: fg.withAlpha(50), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 30),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String? s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: c.withAlpha(30), borderRadius: BorderRadius.circular(8)),
        child: Text(s ?? '',
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _thumbs(String label, List<String> paths) {
    final ok = paths.where((e) => File(e).existsSync()).toList();
    if (ok.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label (${ok.length})', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ok.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    child: InteractiveViewer(child: Image.file(File(ok[i]))),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(ok[i]), width: 64, height: 64, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- التقارير المالية المجمعة ----------------
  Widget _reportsTab() {
    double rent = 0, utils = 0, deposit = 0, due = 0;
    var rented = 0, vacant = 0, late = 0;
    for (final i in _items) {
      rent += num0(i['rent_amount']);
      utils += utilitiesTotal(i);
      deposit += num0(i['deposit_amount']);
      final es = effStatus(i);
      if (es == 'متأخرات') {
        due += totalDue(i);
        late++;
      } else if (es == 'شاغر') {
        vacant++;
      } else {
        rented++;
      }
    }
    final key = intl.DateFormat('yyyy-MM').format(DateTime.now());
    double month = 0, allPaid = 0;
    for (final pm in _payments) {
      allPaid += num0(pm['amount']);
      if ((pm['paid_at'] ?? '').toString().startsWith(key)) month += num0(pm['amount']);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        FadeSlideIn(
          child: AppCard(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E85), Color(0xFF2A8AB8)]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي الإيجارات الشهرية',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(fmt(rent),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('${_items.length} عقار  •  مؤجر $rented  •  شاغر $vacant  •  متأخرات $late',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        )),
        const SizedBox(height: 12),
        FadeSlideIn(index: 1, child: Row(children: [
          _stat('المرافق والخدمات', fmt(utils), Icons.bolt, const Color(0xFFEF6C00)),
          const SizedBox(width: 12),
          _stat('التأمينات', fmt(deposit), Icons.savings, const Color(0xFF00897B)),
        ])),
        const SizedBox(height: 12),
        FadeSlideIn(index: 2, child: Row(children: [
          _stat('متأخرات مستحقة', fmt(due), Icons.warning_amber_rounded,
              const Color(0xFFC62828)),
          const SizedBox(width: 12),
          _stat('عقارات شاغرة', '$vacant', Icons.key, const Color(0xFF6A1B9A)),
        ])),
        const SizedBox(height: 12),
        FadeSlideIn(index: 3, child: Row(children: [
          _stat('المحصّل هذا الشهر', fmt(month), Icons.account_balance_wallet,
              const Color(0xFF2E7D32)),
          const SizedBox(width: 12),
          _stat('إجمالي المحصّل', fmt(allPaid), Icons.savings_outlined,
              const Color(0xFF1B5E85)),
        ])),
        const SizedBox(height: 16),
        FadeSlideIn(index: 4, child: FilledButton.icon(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      ReportFilterScreen(props: _items, pays: _payments))),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('التقرير الشامل (فلترة وتصدير PDF)'),
        )),
        const SizedBox(height: 24),
        const Text('سجل المدفوعات والإيصالات',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (_payments.isEmpty)
          const Text('لا توجد مدفوعات مسجلة بعد. سجّل سداداً من بطاقة العقار.',
              style: TextStyle(color: Colors.black54))
        else
          for (final pm in _payments.take(50))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: ListTile(
                  title: Text('${receiptNo(pm)} • ${pm['property_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${pm['tenant_name']} • ${fmt(num0(pm['amount']))} • ${fmtDateStr(pm['paid_at'])}'),
                  trailing: IconButton.filledTonal(
                    onPressed: () => printReceiptAsk(context, pm),
                    icon: const Icon(Icons.picture_as_pdf),
                    tooltip: 'طباعة الإيصال',
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _stat(String title, String value, IconData icon, Color c) => Expanded(
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                    radius: 18,
                    backgroundColor: c.withAlpha(30),
                    child: Icon(icon, color: c, size: 20)),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: c)),
                ),
              ],
            ),
          ),
        ),
      );
}
