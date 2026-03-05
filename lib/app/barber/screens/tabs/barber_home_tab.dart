import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class BarberHomeTab extends StatefulWidget {
  const BarberHomeTab({super.key});

  @override
  State<BarberHomeTab> createState() => _BarberHomeTabState();
}

class _BarberHomeTabState extends State<BarberHomeTab> {
  static const _initialPosition = LatLng(4.7110, -74.0721); // Bogotá
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _requestLocation();
  }

  Future<void> _requestLocation() async {
    final status = await Permission.location.request();
    if (mounted) {
      setState(() => _locationGranted = status.isGranted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: _initialPosition,
        zoom: 15,
      ),
      myLocationButtonEnabled: _locationGranted,
      myLocationEnabled: _locationGranted,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
