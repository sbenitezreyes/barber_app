import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pantalla que abre al barbero un mapa con:
/// - Su posición en tiempo real (punto azul nativo)
/// - El marcador del cliente
/// - Botón para abrir Google Maps con la navegación real
class ClientRouteScreen extends StatefulWidget {
  final String appointmentId;
  final String clientName;
  final double clientLat;
  final double clientLng;

  const ClientRouteScreen({
    super.key,
    required this.appointmentId,
    required this.clientName,
    required this.clientLat,
    required this.clientLng,
  });

  @override
  State<ClientRouteScreen> createState() => _ClientRouteScreenState();
}

class _ClientRouteScreenState extends State<ClientRouteScreen> {
  final Completer<GoogleMapController> _mapController = Completer();

  Position? _barberPos;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<DocumentSnapshot>? _apptSub;
  double? _distanceKm;
  bool _autoCenter = true; // se desactiva cuando el usuario arrastra el mapa

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Limpiar ruta del mapa home (liveRoute del usuario barbero)
    if (uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'liveRoute': <dynamic>[]}, SetOptions(merge: true))
          .catchError((_) {});
    }
    // NO borramos barberCurrentLat/Lng aquí — si el barbero re-entra a esta
    // pantalla las coords antiguas quedan visibles al cliente hasta que el GPS
    // publique la primera actualización (en segundos).
    _startTracking();
    _listenForCancellation();
  }

  /// Escucha cambios de status — si el cliente cancela, cierra la pantalla.
  void _listenForCancellation() {
    _apptSub = FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final data = doc.data();
      if (data == null) return;
      final status = data['status'] as String? ?? '';
      // Cerrar la pantalla y detener GPS para cualquier estado que no sea 'confirmed'
      if (status != 'confirmed') {
        _apptSub?.cancel();
        _apptSub = null;
        _posSub?.cancel();
        _clearLiveLocation();
        if (!mounted) return;
        if (status == 'cancelled') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El cliente canceló la cita'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 3),
            ),
          );
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _apptSub?.cancel();
    // NO llamamos _clearLiveLocation() aquí:
    // si el barbero sale de la pantalla sin cancelar la cita, las coords
    // deben quedar en Firestore para que el cliente siga viendo la última
    // posición conocida. La limpieza ocurre solo cuando el status cambia
    // (vía _listenForCancellation) o vía Cloud Function.
    super.dispose();
  }

  Future<void> _startTracking() async {
    // Verificar permisos
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) return;

    // Posición inicial
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 6),
      ),
    );
    _updatePosition(pos);

    // Stream de actualizaciones para mostrar la posición en el mapa.
    // La publicación a Firestore en background la maneja barber_settings_tab
    // con su propio foreground service, por lo que aquí usamos LocationSettings
    // estándar solo para la visualización en pantalla.
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_updatePosition);
  }

  void _updatePosition(Position pos) {
    if (!mounted) return;
    final km = _haversine(
          pos.latitude,
          pos.longitude,
          widget.clientLat,
          widget.clientLng,
        ) /
        1000;
    setState(() {
      _barberPos = pos;
      _distanceKm = km;
    });
    if (_autoCenter) _fitBounds();
    // Publicar ubicación en Firestore para que el cliente haga tracking en tiempo real
    FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .update({
      'barberCurrentLat': pos.latitude,
      'barberCurrentLng': pos.longitude,
    }).catchError((_) {});
  }

  /// Cuando el barbero cierra la pantalla, borramos su ubicación en vivo
  /// para que el cliente sepa que ya no está siendo rastreado.
  /// También limpiamos liveRoute del doc del usuario para que el mapa
  /// home del cliente no muestre el recorrido después de la cita.
  Future<void> _clearLiveLocation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await Future.wait([
      // Borrar coords en tiempo real de la cita
      FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .update({
        'barberCurrentLat': FieldValue.delete(),
        'barberCurrentLng': FieldValue.delete(),
      }).catchError((_) {}),
      // Limpiar la ruta acumulada en el doc del usuario barbero
      if (uid != null)
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'liveRoute': <dynamic>[]}, SetOptions(merge: true))
            .catchError((_) {}),
    ]);
  }

  Future<void> _fitBounds() async {
    if (_barberPos == null) return;
    if (!_mapController.isCompleted) return;
    final ctrl = await _mapController.future;
    final b = LatLng(_barberPos!.latitude, _barberPos!.longitude);
    final c = LatLng(widget.clientLat, widget.clientLng);
    final bounds = LatLngBounds(
      southwest: LatLng(
        b.latitude < c.latitude ? b.latitude : c.latitude,
        b.longitude < c.longitude ? b.longitude : c.longitude,
      ),
      northeast: LatLng(
        b.latitude > c.latitude ? b.latitude : c.latitude,
        b.longitude > c.longitude ? b.longitude : c.longitude,
      ),
    );
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(a));
  }

  Future<void> _openGoogleMaps() async {
    final dest = Uri.encodeComponent(widget.clientName);
    final url =
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${widget.clientLat},${widget.clientLng}'
        '&destination_place_id=$dest'
        '&travelmode=driving';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Set<Marker> _buildMarkers(BuildContext context) {
    return {
      Marker(
        markerId: const MarkerId('client'),
        position: LatLng(widget.clientLat, widget.clientLng),
        infoWindow: InfoWindow(title: widget.clientName, snippet: 'Ubicación del cliente'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  Set<Polyline> _buildPolyline() {
    if (_barberPos == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [
          LatLng(_barberPos!.latitude, _barberPos!.longitude),
          LatLng(widget.clientLat, widget.clientLng),
        ],
        color: Colors.blueAccent,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };
  }

  CameraPosition get _initialCamera {
    // Centra entre barbero (o cliente si aún no hay posición) y cliente
    final midLat = _barberPos != null
        ? (_barberPos!.latitude + widget.clientLat) / 2
        : widget.clientLat;
    final midLng = _barberPos != null
        ? (_barberPos!.longitude + widget.clientLng) / 2
        : widget.clientLng;
    return CameraPosition(target: LatLng(midLat, midLng), zoom: 14);
  }

  String _formatDist() {
    if (_distanceKm == null) return '...';
    final km = _distanceKm!;
    return km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
  }

  String _formatWalk() {
    if (_distanceKm == null) return '...';
    final min = (_distanceKm! * 1000 / 83).round();
    return min < 1 ? '< 1 min' : '~$min min';
  }

  String _formatMoto() {
    if (_distanceKm == null) return '...';
    final min = (_distanceKm! * 1000 / 667).round();
    return min < 1 ? '< 1 min' : '~$min min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF111217),
      body: Stack(
        children: [
          // ── Mapa ──────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (ctrl) {
              if (!_mapController.isCompleted) {
                _mapController.complete(ctrl);
                // Centrar al crear si ya tenemos posición
                if (_barberPos != null) _fitBounds();
              }
            },
            onCameraMove: (_) {
              // El usuario está arrastrando: desactivar auto-center
              if (_autoCenter) setState(() => _autoCenter = false);
            },
            markers: _buildMarkers(context),
            polylines: _buildPolyline(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            mapType: MapType.normal,
          ),

          // ── Botón volver ──────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Spacer(),
                  // Botón re-centrar (aparece cuando el usuario ha movido el mapa)
                  if (!_autoCenter)
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        tooltip: 'Centrar ruta',
                        icon: const Icon(Icons.my_location_rounded,
                            color: Colors.black87),
                        onPressed: () {
                          setState(() => _autoCenter = true);
                          _fitBounds();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Panel inferior ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1B22),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_pin_circle,
                          color: Colors.redAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.clientName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          const Text('Cita inmediata · te espera',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // Chips de distancia
                  Row(children: [
                    _InfoChip(
                      icon: Icons.straighten,
                      label: _formatDist(),
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: Icons.directions_walk,
                      label: _formatWalk(),
                      color: Colors.lightBlueAccent,
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: Icons.two_wheeler,
                      label: _formatMoto(),
                      color: Colors.lightBlueAccent,
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Botón navegar
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.navigation_rounded, size: 22),
                      label: const Text('Navegar con Google Maps',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      onPressed: _openGoogleMaps,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
