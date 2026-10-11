import 'package:flutter/material.dart';

import 'paper_picker.dart';
import 'utils.dart';

/// فلترة المدفوعات بالفترة والعقارات (ids = null تعني كل العقارات)
List<Map<String, dynamic>> filterPayments(List<Map<String, dynamic>> pays,
    {DateTime? from, DateTime? to, Set<int>? ids}) {
  return pays.where((e) {
    if (ids != null && !ids.contains(e['property_id'])) return false;
    final d = DateTime.tryParse((e['paid_at'] ?? '').toString());
    if (from != null || to != null) {
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      if (from != null && day.isBefore(from)) return false;
      if (to != null && day.isAfter(to)) return false;
    }
    return true;
  }).toList();
}

/// شاشة إعداد التقرير الشامل: الفترة الزمنية + اختيار عقار/عقارات أو الكل
class ReportFilterScreen extends StatefulWidget {
  final List<Map<String, dynamic>> props;
  final List<Map<String, dynamic>> pays;
  const ReportFilterScreen({super.key, required this.props, required this.pays});

  @override
  State<ReportFilterScreen> createState() => _ReportFilterScreenState();
}

class _ReportFilterScreenState extends State<ReportFilterScreen> {
  DateTime? _from, _to;
  late final Set<int> _sel = widget.props.map((e) => e['id'] as int).toSet();

  bool get _allSel => _sel.length == widget.props.length;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _quick(String k) {
    final n = DateTime.now();
    setState(() {
      switch (k) {
        case 'month':
          _from = DateTime(n.year, n.month, 1);
          _to = DateTime(n.year, n.month + 1, 0);
          break;
        case 'last':
          _from = DateTime(n.year, n.month - 1, 1);
          _to = DateTime(n.year, n.month, 0);
          break;
        case 'year':
          _from = DateTime(n.year, 1, 1);
          _to = DateTime(n.year, 12, 31);
          break;
        default:
          _from = null;
          _to = null;
      }
    });
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(n.year + 5),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
      helpText: 'اختر الفترة الزمنية',
      saveText: 'تأكيد',
    );
    if (r != null) {
      setState(() {
        _from = _day(r.start);
        _to = _day(r.end);
      });
    }
  }

  List<Map<String, dynamic>> get _selectedProps =>
      widget.props.where((p) => _sel.contains(p['id'])).toList();

  List<Map<String, dynamic>> get _pays => filterPayments(widget.pays,
      from: _from, to: _to, ids: _allSel ? null : _sel);

  @override
  Widget build(BuildContext context) {
    final pays = _pays;
    final total = pays.fold<double>(0, (s, e) => s + num0(e['amount']));
    final range = (_from == null || _to == null)
        ? 'كل الفترات'
        : 'من ${fmtDate(_from!)} إلى ${fmtDate(_to!)}';
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد التقرير الشامل')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('الفترة الزمنية',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range),
                    title: Text(range),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickRange,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(label: const Text('هذا الشهر'), onPressed: () => _quick('month')),
                      ActionChip(label: const Text('الشهر الماضي'), onPressed: () => _quick('last')),
                      ActionChip(label: const Text('هذه السنة'), onPressed: () => _quick('year')),
                      ActionChip(label: const Text('الكل'), onPressed: () => _quick('all')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('العقارات / الأصول',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (_allSel) {
                    _sel.clear();
                  } else {
                    _sel.addAll(widget.props.map((e) => e['id'] as int));
                  }
                }),
                child: Text(_allSel ? 'إلغاء تحديد الكل' : 'تحديد كافة العقارات'),
              ),
            ],
          ),
          AppCard(
            child: widget.props.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16), child: Text('لا توجد عقارات'))
                : Column(
                    children: [
                      for (final p in widget.props)
                        CheckboxListTile(
                          value: _sel.contains(p['id']),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _sel.add(p['id'] as int);
                            } else {
                              _sel.remove(p['id']);
                            }
                          }),
                          title: Text('${p['name'] ?? ''}'),
                          subtitle: Text('${p['tenant_name'] ?? ''}'),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'سيشمل التقرير ${_selectedProps.length} عقار • ${pays.length} إيصال • محصّل ${fmt(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sel.isEmpty
                ? null
                : () => exportAllAsk(context, _selectedProps, pays,
                    from: _from, to: _to, allProps: _allSel),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('إنشاء التقرير PDF'),
          ),
        ],
      ),
    );
  }
}
