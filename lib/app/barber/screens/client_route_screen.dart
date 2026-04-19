import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  bool _autoCenter = true;
  bool _arrivedDialogShown = false;

  List<LatLng> _routePoints = [];
  LatLng? _lastRouteOrigin;

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
        perm == LocationPermission.denied) {
      return;
    }

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
    final km =
        _haversine(
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
    _fetchRoute(
      LatLng(pos.latitude, pos.longitude),
      LatLng(widget.clientLat, widget.clientLng),
    );
    // Publicar ubicación en Firestore para que el cliente haga tracking en tiempo real
    FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .update({
          'barberCurrentLat': pos.latitude,
          'barberCurrentLng': pos.longitude,
        })
        .catchError((_) {});

    // Detección automática de llegada (< 80 m del cliente)
    if (!_arrivedDialogShown && km * 1000 < 80) {
      _arrivedDialogShown = true;
      _showArrivalDialog();
    }
  }

  Future<void> _confirmArrival() async {
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .update({'status': 'en_servicio'})
        .catchError((_) {});
    // _listenForCancellation detecta el cambio y cierra la pantalla automáticamente
  }

  Future<void> _showArrivalDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.where_to_vote_rounded,
              color: Color(0xFFC9A84C),
              size: 26,
            ),
            SizedBox(width: 10),
            Text(
              '¡Llegaste!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Confirmas que ya estás en la puerta del cliente?',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Aún no',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmArrival();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC9A84C),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Confirmar llegada',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Llama a la Directions API solo si el origen se movió > 40 m desde
  /// la última vez, para no agotar la cuota de la API.
  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    if (_lastRouteOrigin != null) {
      final moved = _haversine(
        origin.latitude,
        origin.longitude,
        _lastRouteOrigin!.latitude,
        _lastRouteOrigin!.longitude,
      );
      if (moved < 80) return;
    }
    _lastRouteOrigin = origin;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getRoute');
      final result = await callable.call({
        'originLat': origin.latitude,
        'originLng': origin.longitude,
        'destLat': destination.latitude,
        'destLng': destination.longitude,
      });
      final encoded = result.data['encodedPolyline'] as String?;
      if (!mounted || encoded == null || encoded.isEmpty) return;
      final points = PolylinePoints().decodePolyline(encoded);
      setState(() {
        _routePoints = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      });
    } catch (_) {}
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
          })
          .catchError((_) {}),
      // Limpiar la ruta acumulada en el doc del usuario barbero
      if (uid != null)
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'liveRoute': <dynamic>[]}, SetOptions(merge: true))
            .catchError((_) {}),
    ]);
  }

  Future<void> _cancelAppointment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1B22),
        title: const Text('Cancelar cita'),
        content: const Text(
          '¿Seguro que quieres cancelar esta cita? El cliente será notificado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Sí, cancelar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .update({
          'status': 'cancelled',
          'cancelledBy': FirebaseAuth.instance.currentUser?.uid,
        });
    // El listener _listenForCancellation detectará el cambio y cerrará la pantalla
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

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(a));
  }

  Set<Marker> _buildMarkers(BuildContext context) {
    return {
      Marker(
        markerId: const MarkerId('client'),
        position: LatLng(widget.clientLat, widget.clientLng),
        infoWindow: InfoWindow(
          title: widget.clientName,
          snippet: 'Ubicación del cliente',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  Set<Polyline> _buildPolyline() {
    if (_barberPos == null) return {};
    final points = _routePoints.isNotEmpty
        ? _routePoints
        : [
            LatLng(_barberPos!.latitude, _barberPos!.longitude),
            LatLng(widget.clientLat, widget.clientLng),
          ];
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.blueAccent,
        width: 5,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
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
                        icon: const Icon(
                          Icons.my_location_rounded,
                          color: Colors.black87,
                        ),
                        onPressed: () {
                          setState(() => _autoCenter = true);
                          _fitBounds();
                        },
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text(
                      'Cancelar cita',
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: _cancelAppointment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.redAccent,
                          size: 22,
                        ),
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
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              'Cita inmediata · te espera',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Chips de distancia
                  Row(
                    children: [
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
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Botón llegada manual
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _arrivedDialogShown = true;
                        _showArrivalDialog();
                      },
                      icon: const Icon(Icons.where_to_vote_rounded, size: 18),
                      label: const Text(
                        'Ya llegué',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC9A84C),
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
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
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

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
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
