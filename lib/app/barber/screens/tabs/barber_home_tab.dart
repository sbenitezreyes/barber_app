import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class BarberHomeTab extends StatefulWidget {
  const BarberHomeTab({super.key});

  @override
  State<BarberHomeTab> createState() => _BarberHomeTabState();
}

class _BarberHomeTabState extends State<BarberHomeTab> {
  static const _initialPosition = LatLng(4.7110, -74.0721); // Bogotá
  GoogleMapController? _mapController;
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
    
    // Si se otorga el permiso, centrar en la ubicación del usuario
    if (status.isGranted) {
      _centerOnUserLocation();
    }
  }

  Future<void> _centerOnUserLocation() async {
    if (_mapController == null) return;
    try {
      // Obtener la ubicación actual del usuario
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // Centrar la cámara en la ubicación del usuario
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 15,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: _initialPosition,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        if (_locationGranted) _centerOnUserLocation();
      },
      myLocationButtonEnabled: _locationGranted,
      myLocationEnabled: _locationGranted,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
