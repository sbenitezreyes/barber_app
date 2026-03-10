import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Pantalla estilo Didi/Uber: el cliente ve la ubicación del barbero
/// moviéndose en tiempo real hacia su casa.
class BarberTrackingScreen extends StatefulWidget {
  /// ID del documento en la colección `appointments`
  final String appointmentId;

  /// Nombre del barbero (para mostrar en el header)
  final String barberName;

  const BarberTrackingScreen({
    super.key,
    required this.appointmentId,
    required this.barberName,
  });

  @override
  State<BarberTrackingScreen> createState() => _BarberTrackingScreenState();
}

class _BarberTrackingScreenState extends State<BarberTrackingScreen> {
  final _mapCompleter = Completer<GoogleMapController>();

  // Posición actual del barbero (actualizada en tiempo real desde Firestore)
  LatLng? _barberLatLng;

  // Ubicación fija del cliente (leída desde el doc de la cita)
  LatLng? _clientLatLng;

  double? _distanceKm;
  String _status = 'confirmed'; // confirmed | completed

  StreamSubscription<DocumentSnapshot>? _apptSub;

  @override
  void initState() {
    super.initState();
    _apptSub = FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .snapshots()
        .listen(_onApptDoc);
  }

  @override
  void dispose() {
    _apptSub?.cancel();
    super.dispose();
  }

  Future<void> _cancelAppointment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181C),
        title: const Text('Cancelar cita'),
        content: const Text(
            '¿Seguro que quieres cancelar la cita? El barbero será notificado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.redAccent)),
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
    if (mounted) {
      // Vuelve al inicio (pop hasta la raiz)
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _onApptDoc(DocumentSnapshot snap) async {
    if (!snap.exists) return;
    final d = snap.data() as Map<String, dynamic>;

    final bLat = (d['barberCurrentLat'] as num?)?.toDouble();
    final bLng = (d['barberCurrentLng'] as num?)?.toDouble();
    final cLat = (d['clientLat'] as num?)?.toDouble();
    final cLng = (d['clientLng'] as num?)?.toDouble();
    final newStatus = d['status'] as String? ?? 'confirmed';

    if (!mounted) return;
    setState(() {
      _status = newStatus;
      if (cLat != null && cLng != null) {
        _clientLatLng = LatLng(cLat, cLng);
      }
      // Si barberCurrentLat/Lng fue borrado de Firestore, limpiar el marcador
      if (bLat != null && bLng != null) {
        _barberLatLng = LatLng(bLat, bLng);
        if (_clientLatLng != null) {
          _distanceKm = _haversine(bLat, bLng, cLat!, cLng!) / 1000;
        }
      } else {
        _barberLatLng = null;
        _distanceKm = null;
      }
    });

    // Si el barbero cancela/rechaza por su lado, volver al inicio
    if (newStatus == 'cancelled' || newStatus == 'rejected') {
      _apptSub?.cancel();
      _apptSub = null;
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    // Animar cámara para mostrar ambos puntos
    if (_barberLatLng != null && _clientLatLng != null) {
      _fitBounds();
    }
  }

  Future<void> _fitBounds() async {
    if (!_mapCompleter.isCompleted) return;
    final ctrl = await _mapCompleter.future;
    final b = _barberLatLng!;
    final c = _clientLatLng!;
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
    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
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

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    if (_barberLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('barber'),
        position: _barberLatLng!,
        infoWindow: InfoWindow(
          title: widget.barberName,
          snippet: 'Tu barbero',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    if (_clientLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('client'),
        position: _clientLatLng!,
        infoWindow: const InfoWindow(title: 'Tu ubicación'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }
    return markers;
  }

  Set<Polyline> _buildPolyline() {
    if (_barberLatLng == null || _clientLatLng == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_barberLatLng!, _clientLatLng!],
        color: Colors.blueAccent,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };
  }

  CameraPosition get _initialCamera {
    final center = _clientLatLng ?? const LatLng(4.7110, -74.0721);
    return CameraPosition(target: center, zoom: 14);
  }

  String _formatDist() {
    if (_distanceKm == null) return '...';
    final km = _distanceKm!;
    return km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
  }

  String _formatEta() {
    if (_distanceKm == null) return '...';
    final min = (_distanceKm! * 1000 / 667).round(); // ~40 km/h moto
    return min < 1 ? 'Llegando' : '~$min min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrived = _status == 'completed';

    return Scaffold(
      backgroundColor: const Color(0xFF111217),
      body: Stack(
        children: [
              // ── Mapa ──────────────────────────────────────────
              GoogleMap(
                initialCameraPosition: _initialCamera,
                onMapCreated: (ctrl) {
                  if (!_mapCompleter.isCompleted) _mapCompleter.complete(ctrl);
                },
                markers: _buildMarkers(),
                polylines: _buildPolyline(),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),

              // ── Botón volver ───────────────────────────────────
SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      // Botón cancelar cita
                      if (_status != 'completed' && _status != 'cancelled')
                        ElevatedButton.icon(
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Cancelar cita',
                              style: TextStyle(fontSize: 13)),
                          onPressed: _cancelAppointment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.redAccent.withValues(alpha: 0.85),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Panel inferior ─────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1B22),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: arrived
                      ? _ArrivedPanel(barberName: widget.barberName)
                      : _EnRoutePanel(
                          barberName: widget.barberName,
                          hasLocation: _barberLatLng != null,
                          distLabel: _formatDist(),
                          etaLabel: _formatEta(),
                          theme: theme,
                        ),
                ),
              ),
            ],
          ),
        );
  }
}

// ── Panel: barbero en camino ─────────────────────────────────────
class _EnRoutePanel extends StatelessWidget {
  final String barberName;
  final bool hasLocation;
  final String distLabel;
  final String etaLabel;
  final ThemeData theme;

  const _EnRoutePanel({
    required this.barberName,
    required this.hasLocation,
    required this.distLabel,
    required this.etaLabel,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.two_wheeler,
                color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barberName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17),
                ),
                Text(
                  hasLocation
                      ? 'Está en camino a tu ubicación'
                      : 'Preparando ruta…',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          // ETA badge
          if (hasLocation)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                etaLabel,
                style: const TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
        ]),

        if (hasLocation) ...[
          const SizedBox(height: 18),
          // Barra de progreso animada
          _PulsingProgressBar(color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          // Chips de distancia
          Row(children: [
            _TrackChip(
              icon: Icons.straighten,
              label: distLabel,
              color: Colors.white70,
            ),
            const SizedBox(width: 8),
            _TrackChip(
              icon: Icons.two_wheeler,
              label: etaLabel,
              color: Colors.blueAccent,
            ),
          ]),
        ] else ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ],
    );
  }
}

// ── Panel: barbero llegó ─────────────────────────────────────────
class _ArrivedPanel extends StatelessWidget {
  final String barberName;
  const _ArrivedPanel({required this.barberName});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded,
            color: Colors.greenAccent, size: 48),
        const SizedBox(height: 12),
        Text(
          '¡$barberName ha llegado!',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Tu servicio de barbería comienza ahora',
          style: TextStyle(color: Colors.white60, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Barra de progreso con pulso ─────────────────────────────────
class _PulsingProgressBar extends StatefulWidget {
  final Color color;
  const _PulsingProgressBar({required this.color});

  @override
  State<_PulsingProgressBar> createState() => _PulsingProgressBarState();
}

class _PulsingProgressBarState extends State<_PulsingProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return LinearProgressIndicator(
          value: null, // indeterminate
          backgroundColor: widget.color.withValues(alpha: 0.12),
          color: widget.color,
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        );
      },
    );
  }
}

// ── Chip pequeño ────────────────────────────────────────────────
class _TrackChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _TrackChip(
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
          Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
