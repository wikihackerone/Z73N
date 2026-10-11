import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'map_picker.dart';
import 'security.dart';
import 'utils.dart';

class PropertyFormScreen extends StatefulWidget {
  final Map<String, dynamic>? property;
  const PropertyFormScreen({super.key, this.property});

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _address, _location, _tenant, _phone, _alt;
  late final TextEditingController _rent, _deposit, _elec, _water, _gas;
  late final TextEditingController _otherNote, _otherAmount, _balance;
  late String _status;
  late String _ptype;
  DateTime? _due;
  DateTime? _cStart, _cEnd;
  late final TextEditingController _cMonths;
  double? _lat, _lng;
  bool _saving = false;

  List<String> _idImgs = [];
  List<String> _contractImgs = [];
  List<String> _origId = [];
  List<String> _origContract = [];

  bool get _isEdit => widget.property != null;

  @override
  void initState() {
    super.initState();
    final x = widget.property;
    String s(String k) => (x?[k] ?? '').toString();
    String n(String k) => x == null ? '' : plain(num0(x[k]));
    _ptype = kPropertyTypes.containsKey(x?['ptype']) ? x!['ptype'] as String : 'apartment';
    _name = TextEditingController(text: s('name'));
    _address = TextEditingController(text: s('address'));
    _location = TextEditingController(text: s('location'));
    _tenant = TextEditingController(text: s('tenant_name'));
    _phone = TextEditingController(text: phoneForInput(x?['tenant_phone']));
    _alt = TextEditingController(text: phoneForInput(x?['alt_phone']));
    _lat = (x?['lat'] as num?)?.toDouble();
    _lng = (x?['lng'] as num?)?.toDouble();
    _rent = TextEditingController(text: n('rent_amount'));
    _deposit = TextEditingController(text: n('deposit_amount'));
    _elec = TextEditingController(text: n('electricity'));
    _water = TextEditingController(text: n('water'));
    _gas = TextEditingController(text: n('gas'));
    _otherNote = TextEditingController(text: s('other_note'));
    _otherAmount = TextEditingController(text: n('other_amount'));
    _balance = TextEditingController(text: n('balance'));
    _status = kStatuses.contains(x?['status']) ? x!['status'] as String : 'مؤجر';
    _due = parseDue(x?['due_date']);
    _cStart = parseDue(x?['contract_start']);
    _cEnd = parseDue(x?['contract_end']);
    final cm = (x?['contract_months'] as num?)?.toInt();
    _cMonths = TextEditingController(text: cm == null || cm <= 0 ? '' : '$cm');
    if (_isEdit) _loadImages();
  }

  Future<void> _loadImages() async {
    final id = widget.property!['id'] as int;
    final a = await DB.attachments(id, 'id');
    final b = await DB.attachments(id, 'contract');
    if (!mounted) return;
    setState(() {
      _idImgs = List.of(a);
      _contractImgs = List.of(b);
      _origId = List.of(a);
      _origContract = List.of(b);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name, _address, _location, _tenant, _phone, _alt, _rent, _deposit,
      _elec, _water, _gas, _otherNote, _otherAmount, _balance, _cMonths
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addImages(String kind) async {
    final list = kind == 'id' ? _idImgs : _contractImgs;
    final remaining = kMaxImages - list.length;
    if (remaining <= 0) {
      toast(context, 'الحد الأقصى $kMaxImages صورة لكل مستند');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط بالكاميرا'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض (عدة صور)'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picker = ImagePicker();
      var picked = <XFile>[];
      if (source == ImageSource.camera) {
        final x = await picker.pickImage(
            source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
        if (x != null) picked = [x];
      } else {
        picked = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80);
      }
      if (picked.isEmpty) return;
      if (picked.length > remaining) {
        picked = picked.sublist(0, remaining);
        if (mounted) {
          toast(context, 'تمت إضافة أول $remaining صورة فقط (الحد الأقصى $kMaxImages)');
        }
      }
      final dir = await getApplicationDocumentsDirectory();
      final added = <String>[];
      var i = 0;
      for (final f in picked) {
        final dest = p.join(dir.path,
            'img_${DateTime.now().microsecondsSinceEpoch}_${i++}${p.extension(f.path)}');
        await File(f.path).copy(dest);
        added.add(dest);
      }
      setState(() => list.addAll(added));
    } catch (_) {
      if (mounted) toast(context, 'تعذر الوصول للصورة');
    }
  }

  // ---------------- العقد ----------------
  void _recalcEnd() {
    final m = int.tryParse(_cMonths.text.trim());
    if (_cStart != null && m != null && m >= 1 && m <= 120) {
      _cEnd = addMonths(_cStart!, m);
    }
  }

  Future<void> _pickContractDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _cStart : _cEnd) ?? _cStart ?? now,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _cStart = picked;
        _recalcEnd();
      } else {
        _cEnd = picked;
        final s = _cStart;
        if (s != null && picked.isAfter(s)) {
          var mm = (picked.year - s.year) * 12 + picked.month - s.month;
          if (picked.day < s.day) mm -= 1;
          if (mm >= 1) _cMonths.text = '$mm';
        }
      }
    });
  }

  Widget _contractDateTile(String label, IconData icon, DateTime? v, bool isStart) =>
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pickContractDate(isStart),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: v == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      if (isStart) {
                        _cStart = null;
                      } else {
                        _cEnd = null;
                      }
                    }),
                  ),
          ),
          child: Text(v == null ? 'اضغط لاختيار التاريخ' : fmtDate(v)),
        ),
      );

  Widget _contractBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _contractDateTile('تاريخ بداية العقد', Icons.event_available_outlined,
              _cStart, true),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cMonths,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(_recalcEnd),
            decoration: const InputDecoration(
              labelText: 'مدة العقد',
              suffixText: 'شهر',
              prefixIcon: Icon(Icons.timelapse),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final x in const [6, 12, 24, 36])
                ChoiceChip(
                  label: Text(x == 12
                      ? 'سنة'
                      : x == 24
                          ? 'سنتان'
                          : x == 36
                              ? '3 سنوات'
                              : '$x أشهر'),
                  selected: _cMonths.text.trim() == '$x',
                  onSelected: (_) => setState(() {
                    _cMonths.text = '$x';
                    _recalcEnd();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _contractDateTile('تاريخ انتهاء العقد', Icons.event_busy_outlined,
              _cEnd, false),
          if (_cEnd != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'سيصلك تنبيه بدءاً من ${fmtDate(addMonths(_cEnd!, -kContractAlertMonths))} (قبل الانتهاء بشهرين)',
                  style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
            ),
          const SizedBox(height: 12),
        ],
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cStart != null && _cEnd != null && !_cEnd!.isAfter(_cStart!)) {
      toast(context, 'تاريخ انتهاء العقد يجب أن يكون بعد تاريخ البداية');
      return;
    }
    if (_isEdit &&
        !await confirmAction(context,
            title: 'تأكيد تعديل العقار',
            message: 'هل تريد حفظ التعديلات على "${_name.text.trim()}"؟')) {
      return;
    }
    setState(() => _saving = true);
    double d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'location': _location.text.trim(),
      'tenant_name': _tenant.text.trim(),
      'tenant_phone': normalizePhone(_phone.text),
      'alt_phone': normalizePhone(_alt.text),
      'lat': _lat,
      'lng': _lng,
      'rent_amount': d(_rent),
      'deposit_amount': d(_deposit),
      'electricity': d(_elec),
      'water': d(_water),
      'gas': d(_gas),
      'other_note': _otherNote.text.trim(),
      'other_amount': d(_otherAmount),
      'balance': d(_balance),
      'status': _status,
      'ptype': _ptype,
      'due_date': _due == null ? '' : dateIso(_due!),
      'contract_start': _cStart == null ? '' : dateIso(_cStart!),
      'contract_end': _cEnd == null ? '' : dateIso(_cEnd!),
      'contract_months': int.tryParse(_cMonths.text.trim()),
      'id_card_path': '',
      'contract_path': '',
    };
    int pid;
    if (_isEdit) {
      pid = widget.property!['id'] as int;
      await DB.update(pid, data);
    } else {
      data['receipt_counter'] = 0;
      pid = await DB.insert(data);
    }
    await DB.replaceAttachments(pid, 'id', _idImgs);
    await DB.replaceAttachments(pid, 'contract', _contractImgs);
    // حذف ملفات الصور التي أُزيلت
    for (final f in [..._origId, ..._origContract]) {
      if (!_idImgs.contains(f) && !_contractImgs.contains(f)) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// اختيار نوع العقار (شقة / محل / مصنع) بالشعار
  Widget _typePicker() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          for (final e in kPropertyTypes.entries) ...[
            if (e.key != kPropertyTypes.keys.first) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _ptype = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _ptype == e.key ? cs.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _ptype == e.key
                            ? cs.primary
                            : Colors.black.withAlpha(30)),
                  ),
                  child: Column(
                    children: [
                      Icon(e.value.icon,
                          size: 34,
                          color: _ptype == e.key ? Colors.white : Colors.black54),
                      const SizedBox(height: 6),
                      Text(e.value.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _ptype == e.key
                                  ? Colors.white
                                  : Colors.black87)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {IconData? icon,
      bool number = false,
      bool phone = false,
      bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : (phone ? TextInputType.phone : TextInputType.text),
        inputFormatters:
            number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
      ),
    );
  }

  /// حقل هاتف: مفتاح مصر +20 ثابت قبل الرقم، ويُخفى لو كتب المستخدم رقماً دولياً (+ أو 00)
  Widget _phoneField(String label, TextEditingController c, IconData icon) {
    final intl0 = c.text.startsWith('+') || c.text.startsWith('00');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        onChanged: (_) => setState(() {}),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          prefixText: intl0 ? null : '+20 ',
          helperText: 'اكتب الرقم مباشرة (مثال 1012345678). لرقم دولي ابدأ بـ + أو 00',
        ),
      ),
    );
  }

  Future<void> _pickOnMap() async {
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
          builder: (_) => MapPickerScreen(
              initial: (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null)),
    );
    if (r != null) setState(() {
      _lat = r.latitude;
      _lng = r.longitude;
    });
  }

  Widget _locationBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field('لوكيشن العقار (المنطقة / وصف الموقع)', _location,
              icon: Icons.location_on_outlined),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickOnMap,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(_lat == null
                        ? 'تحديد الموقع على خريطة جوجل'
                        : 'تعديل الموقع على الخريطة'),
                  ),
                ),
                if (_lat != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'فتح في خرائط جوجل',
                    onPressed: () => openInMaps(context, _lat!, _lng!),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    tooltip: 'إزالة الموقع',
                    onPressed: () => setState(() {
                      _lat = null;
                      _lng = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ],
            ),
          ),
          if (_lat != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                  'الإحداثيات: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ),
        ],
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _imageSection(String title, IconData icon, List<String> list, String kind) {
    final canAdd = list.length < kMaxImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.black54),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${list.length}/$kMaxImages',
                  style: TextStyle(
                      color: list.length >= kMaxImages ? Colors.red : Colors.black54,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final path in list)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: File(path).existsSync()
                        ? Image.file(File(path), width: 76, height: 76, fit: BoxFit.cover)
                        : Container(
                            width: 76,
                            height: 76,
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image)),
                  ),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => list.remove(path)),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (canAdd)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _addImages(kind),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withAlpha(40)),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: Colors.black45),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل عقار' : 'إضافة عقار جديد',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _section('بيانات العقار'),
            if (_isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    'كود العقار: ${widget.property!['id']}  •  تبدأ إيصالاته من ${(widget.property!['id'] as int) * 100000 + 1}',
                    style: const TextStyle(color: Colors.black54)),
              ),
            _typePicker(),
            _field('اسم العقار', _name, icon: propertyTypeIcon(_ptype), required: true),
            _locationBlock(),
            _field('العنوان التفصيلي', _address, icon: Icons.place_outlined),
            DropdownButtonFormField<String>(
              value: _status,
              items: kStatuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
              decoration: const InputDecoration(
                  labelText: 'حالة العقار', prefixIcon: Icon(Icons.flag_outlined)),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _due ?? now,
                  firstDate: DateTime(now.year - 3),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) setState(() => _due = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'تاريخ استحقاق الإيجار',
                  prefixIcon: const Icon(Icons.event_outlined),
                  suffixIcon: _due == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _due = null),
                        ),
                ),
                child: Text(_due == null ? 'اضغط لاختيار التاريخ' : fmtDate(_due!)),
              ),
            ),
            const SizedBox(height: 12),
            _section('بيانات العقد'),
            _contractBlock(),
            _section('بيانات المستأجر'),
            _field('اسم المستأجر', _tenant, icon: Icons.person_outline),
            _phoneField('رقم الهاتف (واتساب)', _phone, Icons.phone_outlined),
            _phoneField('رقم هاتف بديل', _alt, Icons.phone_forwarded_outlined),
            _section('الماليات'),
            _field('الإيجار الشهري', _rent,
                icon: Icons.payments_outlined, number: true),
            _field('قيمة التأمين', _deposit,
                icon: Icons.savings_outlined, number: true),
            _field('رصيد سابق مستحق (إن وجد)', _balance,
                icon: Icons.account_balance_wallet_outlined, number: true),
            _section('المرافق'),
            _field('فاتورة الكهرباء', _elec,
                icon: Icons.bolt_outlined, number: true),
            _field('فاتورة المياه', _water,
                icon: Icons.water_drop_outlined, number: true),
            _field('فاتورة الغاز', _gas,
                icon: Icons.local_fire_department_outlined, number: true),
            _section('خدمات أخرى'),
            _field('ملاحظات الخدمة', _otherNote, icon: Icons.notes_outlined),
            _field('قيمة الخدمة', _otherAmount,
                icon: Icons.room_service_outlined, number: true),
            _section('المرفقات (حد أقصى $kMaxImages صورة لكل مستند)'),
            _imageSection('صور البطاقة', Icons.badge_outlined, _idImgs, 'id'),
            const SizedBox(height: 16),
            _imageSection(
                'صور العقد', Icons.description_outlined, _contractImgs, 'contract'),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_isEdit ? 'تحديث' : 'حفظ',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
