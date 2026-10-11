import 'package:flutter/material.dart';

import 'contract.dart';
import 'finance.dart';
import 'smooth.dart';
import 'utils.dart';

/// تبويب «المستأجرون»: كل مستأجر مع عدّاد الأيام المتبقية على الإيجار وعلى تجديد العقد
class TenantsTab extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onReload;
  const TenantsTab({super.key, required this.items, required this.onReload});

  @override
  State<TenantsTab> createState() => _TenantsTabState();
}

enum _Filter { all, late, soon, contract }

enum _Sort { rent, contract, name }

class _TenantsTabState extends State<TenantsTab> {
  String _query = '';
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.rent;

  // ---------- البيانات ----------
  List<Map<String, dynamic>> get _tenants => widget.items.where((i) {
        if (i['status'] == 'شاغر') return false;
        return (i['tenant_name'] ?? '').toString().trim().isNotEmpty;
      }).toList();

  bool _isLate(Map<String, dynamic> i) {
    final d = daysUntilDue(i);
    return i['status'] == 'متأخرات' || (d != null && d < 0);
  }

  bool _isSoon(Map<String, dynamic> i) {
    final d = daysUntilDue(i);
    return d != null && d >= 0 && d <= soonDays;
  }

  bool _match(Map<String, dynamic> i) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.late:
        return _isLate(i);
      case _Filter.soon:
        return _isSoon(i);
      case _Filter.contract:
        return contractNeedsAlert(i);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.toLowerCase();
    final list = _tenants.where((i) {
      if (!_match(i)) return false;
      if (q.isEmpty) return true;
      return '${i['tenant_name']} ${i['name']} ${i['tenant_phone']}'
          .toLowerCase()
          .contains(q);
    }).toList();
    int key(int? n) => n ?? 1 << 30; // غير المحدد في الآخر
    switch (_sort) {
      case _Sort.rent:
        list.sort((a, b) =>
            key(daysUntilDue(a)).compareTo(key(daysUntilDue(b))));
      case _Sort.contract:
        list.sort((a, b) =>
            key(contractDaysLeft(a)).compareTo(key(contractDaysLeft(b))));
      case _Sort.name:
        list.sort((a, b) => '${a['tenant_name']}'.compareTo('${b['tenant_name']}'));
    }
    return list;
  }

  // ---------- الإجراءات ----------
  Future<void> _pay(Map<String, dynamic> it) async {
    final ok = await showPayDialog(context, it);
    if (ok) await widget.onReload();
  }

  Future<void> _message(Map<String, dynamic> it) async {
    final saved = await showContractMessageDialog(context, it);
    if (saved) await widget.onReload();
  }

  // ---------- الواجهة ----------
  @override
  Widget build(BuildContext context) {
    final all = _tenants;
    final late = all.where(_isLate).length;
    final soon = all.where(_isSoon).length;
    final contracts = all.where(contractNeedsAlert).length;
    final list = _visible;

    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'ابحث باسم المستأجر أو العقار',
                    prefixIcon: Icon(Icons.search),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              PopupMenuButton<_Sort>(
                tooltip: 'ترتيب',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: _Sort.rent, child: Text('الأقرب استحقاقاً للإيجار')),
                  PopupMenuItem(
                      value: _Sort.contract, child: Text('الأقرب انتهاءً للعقد')),
                  PopupMenuItem(value: _Sort.name, child: Text('الاسم')),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              chip('الكل (${all.length})', _Filter.all),
              chip('متأخر ($late)', _Filter.late),
              chip('إيجار قريب ($soon)', _Filter.soon),
              chip('عقود قريبة ($contracts)', _Filter.contract),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _empty(all.isNotEmpty)
              : RefreshIndicator(
                  onRefresh: widget.onReload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, k) => FadeSlideIn(
                      key: ValueKey(list[k]['id']),
                      index: k,
                      child: _card(list[k]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _empty(bool hasTenants) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasTenants ? Icons.search_off : Icons.people_outline,
                  size: 72, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                hasTenants
                    ? 'لا توجد نتائج مطابقة'
                    : 'لا يوجد مستأجرون بعد\nأضف عقاراً مؤجَّراً ليظهر مستأجره هنا',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ],
          ),
        ),
      );

  Widget _card(Map<String, dynamic> it) {
    final rentLeft = daysUntilDue(it);
    final contractLeft = contractDaysLeft(it);
    final due = parseDue(it['due_date']);
    final end = contractEndOf(it);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0x1A1B5E85),
                  child: Icon(Icons.person, color: Color(0xFF1B5E85), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${it['tenant_name'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text('${it['name'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('المستحق',
                        style: TextStyle(color: Colors.black54, fontSize: 11)),
                    Text(fmt(totalDue(it)),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _counter('موعد الإيجار', rentLeft, false,
                      rentCounterColor(rentLeft),
                      due == null ? '' : fmtDate(due)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _counter('تجديد العقد', contractLeft, true,
                      contractCounterColor(it), end == null ? '' : fmtDate(end)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _action(Icons.payments_outlined, 'سداد', () => _pay(it))),
                const SizedBox(width: 6),
                Expanded(
                    child: _action(Icons.chat, 'رسالة العقد', () => _message(it),
                        color: const Color(0xFF2E7D32))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _counter(
      String label, int? n, bool contract, Color c, String dateText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.withAlpha(22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(counterBig(n),
                  style: TextStyle(
                      color: c, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(counterCaption(n, contract: contract),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (dateText.isNotEmpty)
            Text(dateText,
                style: const TextStyle(color: Colors.black45, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          minimumSize: const Size(0, 36),
        ),
      );
}
