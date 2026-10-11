import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'contract.dart';
import 'db.dart';
import 'finance.dart';
import 'map_picker.dart';
import 'paper_picker.dart';
import 'pdf_export.dart';
import 'security.dart';
import 'utils.dart';

class PropertyDetailScreen extends StatefulWidget {
  final int propertyId;
  const PropertyDetailScreen({super.key, required this.propertyId});

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  Map<String, dynamic>? _p;
  List<Map<String, dynamic>> _pays = [];
  List<Map<String, dynamic>> _renewals = [];
  bool _loading = true;

  final _elec = TextEditingController();
  final _water = TextEditingController();
  final _gas = TextEditingController();
  final _otherNote = TextEditingController();
  final _otherAmount = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_elec, _water, _gas, _otherNote, _otherAmount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = await DB.property(widget.propertyId);
    final pays = await DB.paymentsOf(widget.propertyId);
    final rens = await DB.renewalsOf(widget.propertyId);
    if (!mounted) return;
    setState(() {
      _p = p;
      _pays = pays;
      _renewals = rens;
      _loading = false;
      if (p != null) {
        _elec.text = plain(num0(p['electricity']));
        _water.text = plain(num0(p['water']));
        _gas.text = plain(num0(p['gas']));
        _otherNote.text = (p['other_note'] ?? '').toString();
        _otherAmount.text = plain(num0(p['other_amount']));
      }
    });
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;

  Future<void> _saveUtilities({bool quiet = false}) async {
    if (!quiet &&
        !await confirmAction(context,
            title: 'تأكيد تعديل المرافق', message: 'حفظ قيم المرافق الجديدة؟')) {
      return;
    }
    await DB.update(widget.propertyId, {
      'electricity': _d(_elec),
      'water': _d(_water),
      'gas': _d(_gas),
      'other_note': _otherNote.text.trim(),
      'other_amount': _d(_otherAmount),
    });
    await _load();
    if (!quiet && mounted) toast(context, 'تم حفظ المرافق');
  }

  Future<void> _payUtilities() async {
    await _saveUtilities(quiet: true);
    final prop = _p;
    if (prop == null || !mounted) return;
    final ok = await showPayDialog(context, prop, kind: 'utilities');
    if (ok) await _load();
  }

  Future<void> _renew() async {
    final prop = _p;
    if (prop == null) return;
    if (await showRenewDialog(context, prop)) await _load();
  }

  Future<void> _payRent() async {
    final prop = _p;
    if (prop == null) return;
    final ok = await showPayDialog(context, prop);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(p == null ? 'العقار' : '${p['name']}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الحساب الخاص'),
              Tab(text: 'المدفوعات'),
              Tab(text: 'المرافق'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (p == null
                ? const Center(child: Text('العقار غير موجود'))
                : TabBarView(children: [
                    _accountTab(p),
                    _paymentsTab(),
                    _utilitiesTab(p),
                  ])),
      ),
    );
  }

  // ---------------- الحساب الخاص ----------------
  Widget _stat(String title, String value, IconData icon, Color c) => Expanded(
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: c.withAlpha(30),
                    child: Icon(icon, color: c, size: 18)),
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: c)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _line(IconData i, String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(i, size: 18, color: Colors.black45),
            const SizedBox(width: 8),
            Text('$a: ', style: const TextStyle(color: Colors.black54)),
            Expanded(
                child: Text(b, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _accountTab(Map<String, dynamic> p) {
    final totalPaid = _pays.fold<double>(0, (s, e) => s + num0(e['amount']));
    final color = statusColor(effStatus(p));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _line(Icons.tag, 'كود العقار', '${p['id']}'),
                _line(Icons.location_on_outlined, 'الموقع', '${p['location'] ?? ''}'),
                if (p['lat'] != null && p['lng'] != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => openInMaps(context,
                          (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('عرض على خريطة جوجل'),
                    ),
                  ),
                _line(Icons.place_outlined, 'العنوان', '${p['address'] ?? ''}'),
                _line(Icons.person_outline, 'المستأجر', '${p['tenant_name'] ?? ''}'),
                _line(Icons.phone_outlined, 'الهاتف', '${p['tenant_phone'] ?? ''}'),
                _line(Icons.phone_forwarded_outlined, 'هاتف بديل', '${p['alt_phone'] ?? ''}'),
                _line(Icons.event_outlined, 'الاستحقاق', dueText(p)),
                _line(Icons.event_available_outlined, 'بداية العقد',
                    contractStartOf(p) == null ? 'غير محدد' : fmtDate(contractStartOf(p)!)),
                _line(Icons.event_busy_outlined, 'نهاية العقد', contractText(p)),
                if ((p['contract_months'] as num?) != null &&
                    (p['contract_months'] as num) > 0)
                  _line(Icons.timelapse, 'مدة العقد', '${p['contract_months']} شهر'),
                _line(Icons.flag_outlined, 'الحالة', effStatus(p)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _stat('المستحق الآن', fmt(totalDue(p)), Icons.request_quote, color),
          const SizedBox(width: 12),
          _stat('رصيد سابق', fmt(num0(p['balance'])), Icons.account_balance_wallet,
              const Color(0xFF6A1B9A)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _stat('إجمالي المسدد', fmt(totalPaid), Icons.check_circle,
              const Color(0xFF2E7D32)),
          const SizedBox(width: 12),
          _stat('عدد الإيصالات', '${_pays.length}', Icons.receipt_long,
              const Color(0xFF1B5E85)),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _payRent,
          icon: const Icon(Icons.payments),
          label: const Text('تسجيل سداد الإيجار'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _renew,
          icon: const Icon(Icons.autorenew),
          label: const Text('تجديد العقد بتاريخ جديد'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => exportAccountAsk(context, p, _pays),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('تصدير كشف الحساب PDF'),
        ),
        if (_renewals.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('سجل تجديدات العقد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final r in _renewals)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                      'من ${fmtDateStr(r['new_start'])} إلى ${fmtDateStr(r['new_end'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      'تجديد بتاريخ ${fmtDateStr(r['renewed_at'])} • ${r['months']} شهر'
                      '${(r['old_end'] ?? '').toString().isNotEmpty ? '\nالعقد السابق انتهى ${fmtDateStr(r['old_end'])}' : ''}'),
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------- المدفوعات ----------------
  Widget _paymentsTab() {
    if (_pays.isEmpty) {
      return const Center(
        child: Text('لا توجد مدفوعات لهذا العقار بعد',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _pays.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final pm = _pays[i];
        final rest = num0(pm['new_balance']);
        return AppCard(
          child: ListTile(
            title: Text('إيصال ${receiptNo(pm)} • ${kindLabel(pm['kind'])}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${fmtDateStr(pm['paid_at'])} • ${fmt(num0(pm['amount']))}'
                '${(pm['kind'] != 'utilities' && rest != 0) ? '\n${rest > 0 ? 'المتبقي' : 'دائن'}: ${fmt(rest.abs())}' : ''}'
                '${(pm['note'] ?? '').toString().isNotEmpty ? '\nملاحظة: ${pm['note']}' : ''}'),
            isThreeLine: rest != 0,
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'print') {
                  await printReceiptAsk(context, pm);
                } else if (v == 'edit') {
                  if (await showEditPaymentDialog(context, pm)) await _load();
                } else if (v == 'delete') {
                  if (await confirmDeletePayment(context, pm)) await _load();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'print', child: Text('طباعة الإيصال')),
                PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- مستحقات المرافق ----------------
  Widget _numField(String label, TextEditingController c, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );

  Widget _utilitiesTab(Map<String, dynamic> p) {
    final total = _d(_elec) + _d(_water) + _d(_gas) + _d(_otherAmount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _numField('الكهرباء', _elec, Icons.bolt_outlined),
        _numField('المياه', _water, Icons.water_drop_outlined),
        _numField('الغاز', _gas, Icons.local_fire_department_outlined),
        const Padding(
          padding: EdgeInsets.only(bottom: 8, top: 4),
          child: Text('خدمات أخرى',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _otherNote,
            decoration: const InputDecoration(
                labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes_outlined)),
          ),
        ),
        _numField('القيمة', _otherAmount, Icons.room_service_outlined),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEF6C00).withAlpha(25),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('إجمالي مستحقات المرافق',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Text(fmt(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFFEF6C00))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _saveUtilities,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ القيم'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: total > 0 ? _payUtilities : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('سداد المرافق وتصفير القيم'),
        ),
      ],
    );
  }
}
