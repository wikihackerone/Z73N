import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'utils.dart';

/// رابط الموقع على خرائط جوجل
Uri mapsUri(double lat, double lng) => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng');

Future<void> openInMaps(BuildContext context, double lat, double lng) async {
  try {
    final ok = await launchUrl(mapsUri(lat, lng), mode: LaunchMode.externalApplication);
    if (!ok) toast(context, 'تعذر فتح الخريطة');
  } catch (_) {
    toast(context, 'تعذر فتح الخريطة');
  }
}

/// شاشة اختيار موقع العقار على خريطة جوجل. ترجع LatLng أو null.
class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _cairo = LatLng(30.0444, 31.2357);
  GoogleMapController? _ctrl;
  LatLng? _picked;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  Future<void> _goToMe() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'صلاحية الموقع مرفوضة. فعّلها من إعدادات الهاتف.');
      } else if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) toast(context, 'فعّل خدمة الموقع (GPS) في الهاتف');
      } else {
        final pos = await Geolocator.getCurrentPosition();
        final ll = LatLng(pos.latitude, pos.longitude);
        setState(() => _picked = ll);
        await _ctrl?.animateCamera(CameraUpdate.newLatLngZoom(ll, 17));
      }
    } catch (_) {
      if (mounted) toast(context, 'تعذر تحديد موقعك الحالي');
    }
    if (mounted) setState(() => _locating = false);
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.initial ?? _cairo;
    return Scaffold(
      appBar: AppBar(title: const Text('تحديد لوكيشن العقار')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: start, zoom: widget.initial == null ? 11 : 16),
            onMapCreated: (c) => _ctrl = c,
            onTap: (ll) => setState(() => _picked = ll),
            markers: {
              if (_picked != null)
                Marker(markerId: const MarkerId('p'), position: _picked!),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          PositionedDirectional(
            top: 12,
            start: 12,
            end: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _picked == null
                      ? 'اضغط على الخريطة لتحديد مكان العقار'
                      : 'الإحداثيات: ${_picked!.latitude.toStringAsFixed(6)}, ${_picked!.longitude.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 90,
            end: 16,
            child: FloatingActionButton.small(
              heroTag: 'me',
              onPressed: _locating ? null : _goToMe,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
            icon: const Icon(Icons.check),
            label: const Text('تأكيد الموقع'),
          ),
        ),
      ),
    );
  }
}
