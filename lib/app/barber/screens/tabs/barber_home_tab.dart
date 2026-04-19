import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../shared/theme/app_theme.dart';

// ── Modelo ligero solo para el mapa ──────────────────────────────────────────

class _MapAppt {
  final String id;
  final String clientName;
  final String serviceName;
  final String status;
  final bool isImmediate;
  final DateTime scheduledAt;
  final double lat;
  final double lng;

  const _MapAppt({
    required this.id,
    required this.clientName,
    required this.serviceName,
    required this.status,
    required this.isImmediate,
    required this.scheduledAt,
    required this.lat,
    required this.lng,
  });
}

// ── Tab principal ─────────────────────────────────────────────────────────────

class BarberHomeTab extends StatefulWidget {
  const BarberHomeTab({super.key});

  @override
  State<BarberHomeTab> createState() => _BarberHomeTabState();
}

class _BarberHomeTabState extends State<BarberHomeTab> {
  static const _initialPosition = LatLng(4.7110, -74.0721); // Bogotá
  final _mapReady = Completer<GoogleMapController>();

  bool _locationGranted = false;
  Set<Marker> _markers = {};
  List<_MapAppt> _todayAppts = [];
  StreamSubscription? _apptSub;

  @override
  void initState() {
    super.initState();
    _requestLocation();
    _subscribeToTodayAppts();
  }

  @override
  void dispose() {
    _apptSub?.cancel();
    super.dispose();
  }

  // ── Permiso de ubicación ──────────────────────────────────────────────────

  Future<void> _requestLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (mounted) setState(() => _locationGranted = granted);
    if (granted) { _centerOnUserLocation(); }
  }

  Future<void> _centerOnUserLocation() async {
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      final controller = await _mapReady.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 15,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error centrando mapa: $e');
    }
  }

  // ── Stream citas de hoy ───────────────────────────────────────────────────

  void _subscribeToTodayAppts() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    // Sin filtro de fecha para evitar índice compuesto — filtrado client-side
    _apptSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('barberUid', isEqualTo: uid)
        .snapshots()
        .listen((snap) async {
      final now = DateTime.now();

      final appts = snap.docs
          .map((doc) {
            final d = doc.data();
            final ts = d['scheduledAt'] as Timestamp?;
            final date = ts?.toDate() ?? DateTime.now();

            // Solo citas de hoy
            if (date.year != now.year ||
                date.month != now.month ||
                date.day != now.day) return null;

            final status = d['status'] as String? ?? 'pending';
            // Excluir canceladas y rechazadas
            if (status == 'cancelled' || status == 'rejected') return null;

            final lat = (d['clientLat'] as num?)?.toDouble();
            final lng = (d['clientLng'] as num?)?.toDouble();
            // Solo mostrar si tienen coordenadas
            if (lat == null || lng == null) return null;

            return _MapAppt(
              id: doc.id,
              clientName: d['clientName'] as String? ?? 'Cliente',
              serviceName: d['serviceName'] as String? ?? '',
              status: status,
              isImmediate: d['isImmediate'] as bool? ?? false,
              scheduledAt: date,
              lat: lat,
              lng: lng,
            );
          })
          .whereType<_MapAppt>()
          .toList();

      // Ordenar por hora para asignar los números correctamente
      appts.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      // Construir marcadores numerados
      final markers = <Marker>{};
      for (int i = 0; i < appts.length; i++) {
        final appt = appts[i];
        final number = i + 1;
        final color = _markerColor(appt);
        final icon = await _buildNumberedMarker(number, color);

        final timeStr = appt.isImmediate
            ? 'Inmediata'
            : DateFormat('HH:mm').format(appt.scheduledAt);

        markers.add(
          Marker(
            markerId: MarkerId('appt_${appt.id}'),
            position: LatLng(appt.lat, appt.lng),
            icon: icon,
            infoWindow: InfoWindow(
              title: '$number. ${appt.clientName}',
              snippet: '${appt.serviceName} · $timeStr',
            ),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _markers = markers;
        _todayAppts = appts;
      });

      // Ajustar cámara para mostrar todas las citas
      if (appts.isNotEmpty) _fitMarkersInView(appts);
    });
  }

  Color _markerColor(_MapAppt appt) {
    switch (appt.status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
      case 'rejected':
        return AppColors.error;
      case 'confirmed':
        return AppColors.gold;
      case 'en_servicio':
        return const Color(0xFF2196F3);
      default: // pending
        // Cita perdida: pendiente y la hora ya pasó
        if (!appt.isImmediate && appt.scheduledAt.isBefore(DateTime.now())) {
          return AppColors.error;
        }
        return Colors.grey;
    }
  }

  // ── Ajustar cámara a todos los marcadores ─────────────────────────────────

  Future<void> _fitMarkersInView(List<_MapAppt> appts) async {
    if (appts.isEmpty) return;
    try {
      final controller = await _mapReady.future.timeout(
        const Duration(seconds: 5),
      );

      if (appts.length == 1) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(appts[0].lat, appts[0].lng),
              zoom: 15,
            ),
          ),
        );
        return;
      }

      double minLat = appts[0].lat, maxLat = appts[0].lat;
      double minLng = appts[0].lng, maxLng = appts[0].lng;
      for (final a in appts) {
        if (a.lat < minLat) minLat = a.lat;
        if (a.lat > maxLat) maxLat = a.lat;
        if (a.lng < minLng) minLng = a.lng;
        if (a.lng > maxLng) maxLng = a.lng;
      }

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.005, minLng - 0.005),
            northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
          ),
          72,
        ),
      );
    } catch (_) {}
  }

  // ── Dibujar marcador circular con número ──────────────────────────────────

  static Future<BitmapDescriptor> _buildNumberedMarker(
    int number,
    Color color,
  ) async {
    const double size = 44;
    const double radius = 16;
    const Offset center = Offset(size / 2, size / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center.translate(0, 2), radius, shadowPaint);

    // Relleno del círculo
    canvas.drawCircle(center, radius, Paint()..color = color);

    // Borde blanco
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Número
    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: Colors.white,
          fontSize: number > 9 ? 10 : 13,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mapa
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: _initialPosition,
            zoom: 15,
          ),
          onMapCreated: (controller) {
            if (!_mapReady.isCompleted) _mapReady.complete(controller);
            if (_locationGranted) _centerOnUserLocation();
          },
          myLocationButtonEnabled: _locationGranted,
          myLocationEnabled: _locationGranted,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: _markers,
        ),

        // Pill resumen — parte superior
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: _SummaryPill(appts: _todayAppts),
          ),
        ),
      ],
    );
  }
}

// ── Pill de resumen del día ───────────────────────────────────────────────────

class _SummaryPill extends StatelessWidget {
  final List<_MapAppt> appts;
  const _SummaryPill({required this.appts});

  @override
  Widget build(BuildContext context) {
    if (appts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 14,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              'Sin citas con ubicación hoy',
              style: AppTextStyles.ui(
                size: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // Contar solo estados activos (pendientes y aceptadas)
    final now = DateTime.now();
    final pending = appts.where((a) =>
        a.status == 'pending' &&
        (a.isImmediate || !a.scheduledAt.isBefore(now))).length;
    final confirmed = appts.where((a) =>
        a.status == 'confirmed' || a.status == 'en_servicio').length;
    final activeCount = pending + confirmed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.borderAccent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_outlined, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            activeCount == 0
                ? 'Sin citas activas hoy'
                : '$activeCount cita${activeCount != 1 ? 's' : ''} activa${activeCount != 1 ? 's' : ''} hoy',
            style: AppTextStyles.ui(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (confirmed > 0) ...[
            const SizedBox(width: 10),
            _StatusDot(color: AppColors.gold, count: confirmed),
          ],
          if (pending > 0) ...[
            const SizedBox(width: 6),
            _StatusDot(color: Colors.grey, count: pending),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final int count;
  const _StatusDot({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: AppTextStyles.ui(
            size: 11,
            weight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
