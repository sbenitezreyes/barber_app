import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import '../barber_profile_sheet.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _initialPosition = LatLng(4.7110, -74.0721); // Bogotá
  GoogleMapController? _mapController;
  bool _locationGranted = false;
  Set<Marker> _markers = {};
  StreamSubscription<QuerySnapshot>? _barbersSub;
  Timer? _scheduleTimer;
  // Caché local de barberos: no necesita tocar Firestore para re-evaluar horario
  final List<({String id, Map<String, dynamic> data})> _cachedBarbers = [];

  @override
  void initState() {
    super.initState();
    _requestLocation();
    _listenToBarbers();
    // Re-evalúa horarios cada 5 minutos sin llamar a Firestore
    _scheduleTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _rebuildMarkersFromCache(),
    );
  }

  @override
  void dispose() {
    _barbersSub?.cancel();
    _scheduleTimer?.cancel();
    for (final img in _photoCache.values) {
      img?.dispose();
    }
    _photoCache.clear();
    _photoCacheURL.clear();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    final status = await Permission.location.request();
    if (mounted) setState(() => _locationGranted = status.isGranted);
    
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

  // ── Construye un marcador personalizado con inicial del barbero ──
  // Caché de foto por UID → evita re-descargar en cada rebuild
  final Map<String, ui.Image?> _photoCache = {};
  final Map<String, String> _photoCacheURL = {}; // UID → URL cacheada

  Future<ui.Image?> _fetchPhoto(String uid, String url) async {
    // Si la URL cambió, invalidar caché
    if (_photoCacheURL[uid] != url) {
      _photoCache.remove(uid);
      _photoCacheURL[uid] = url;
    }
    if (_photoCache.containsKey(uid)) return _photoCache[uid];
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: 56,
        targetHeight: 56,
      );
      final frame = await codec.getNextFrame();
      _photoCache[uid] = frame.image;
      client.close();
      return frame.image;
    } catch (_) {
      _photoCache[uid] = null;
      return null;
    }
  }

  Future<BitmapDescriptor> _buildMarkerIcon(String name,
      {String? photoURL, String? uid}) async {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    // Intentar obtener foto si hay URL
    ui.Image? photo;
    if (photoURL != null && photoURL.isNotEmpty && uid != null) {
      photo = await _fetchPhoto(uid, photoURL);
    }

    const double diameter = 56;
    const double tailW = 9;
    const double tailH = 16;
    const double totalH = diameter + tailH;
    const double cx = diameter / 2;
    const double cy = diameter / 2;
    const double r = diameter / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black38
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(const Offset(cx + 2, cy + 2), r, shadowPaint);

    // Fondo del círculo
    const circleColor = Color(0xFF00BCD4);
    if (photo != null) {
      // Recortar foto en círculo
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(
            center: const Offset(cx, cy), radius: r - 2));
      canvas.clipPath(clipPath);
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: const Offset(cx, cy), radius: r - 2),
        image: photo,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } else {
      // Fondo cian + inicial
      final bgPaint = Paint()..color = circleColor;
      canvas.drawCircle(const Offset(cx, cy), r, bgPaint);
    }

    // Borde blanco
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const Offset(cx, cy), r - 2, borderPaint);

    // Triángulo / punta de la flechita hacia abajo
    final tailPaint = Paint()..color = circleColor;
    final tailPath = Path()
      ..moveTo(cx - tailW, diameter - 8)
      ..lineTo(cx + tailW, diameter - 8)
      ..lineTo(cx, diameter + tailH - 4)
      ..close();
    canvas.drawPath(tailPath, tailPaint);

    // Borde del triángulo (solo los lados)
    final tailBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final tailBorderPath = Path()
      ..moveTo(cx - tailW + 2, diameter - 8)
      ..lineTo(cx, diameter + tailH - 6)
      ..lineTo(cx + tailW - 2, diameter - 8);
    canvas.drawPath(tailBorderPath, tailBorder);

    // Texto inicial solo si no hay foto
    if (photo == null) {
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 22,
        fontWeight: ui.FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: Colors.white))
      ..addText(initial);
      final paragraph = paragraphBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: diameter));
      canvas.drawParagraph(
        paragraph,
        Offset(0, cy - paragraph.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(diameter.toInt(), totalH.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: diameter / 1.8,
    );
  }

  // ── Verifica si la hora actual cae dentro del horario laboral del barbero ──
  bool _isWithinSchedule(Map<String, dynamic> data) {
    const dayKeys = [
      'monday',    // 1
      'tuesday',   // 2
      'wednesday', // 3
      'thursday',  // 4
      'friday',    // 5
      'saturday',  // 6
      'sunday',    // 7
    ];

    final schedule = data['schedule'];
    if (schedule == null || schedule is! Map) return true; // sin horario → mostrar

    final now = DateTime.now();
    final todayKey = dayKeys[now.weekday - 1]; // weekday: 1=Lun … 7=Dom

    final dayData = schedule[todayKey];
    if (dayData == null || dayData is! Map) return false;

    final enabled = dayData['enabled'] == true;
    if (!enabled) return false;

    final openStr = dayData['open'] as String?;
    final closeStr = dayData['close'] as String?;
    if (openStr == null || closeStr == null) return false;

    final openParts = openStr.split(':');
    final closeParts = closeStr.split(':');
    final openMinutes =
        int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMinutes =
        int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;

    return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
  }

  void _listenToBarbers() {
    _barbersSub = FirebaseFirestore.instance
        .collection('users')
        .where('isAvailable', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      // Actualiza caché con los datos frescos de Firestore
      _cachedBarbers.clear();
      for (final doc in snap.docs) {
        final data = doc.data();
        final roles = data['role'];
        if (roles == null) continue;
        final isBarbero = (roles is List)
            ? roles.contains('barber')
            : roles.toString() == 'barber';
        if (!isBarbero) continue;
        final loc = data['location'];
        if (loc == null) continue;
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        _cachedBarbers.add((id: doc.id, data: data));
      }
      _rebuildMarkersFromCache();
    });
  }

  // Reconstruye marcadores usando la caché — sin tocar Firestore
  Future<void> _rebuildMarkersFromCache() async {
    final markers = <Marker>{};
    for (final barber in List.of(_cachedBarbers)) {
      if (!_isWithinSchedule(barber.data)) continue;
      final name = (barber.data['name'] ?? 'Barbero') as String;
      final photoURL = barber.data['photoURL'] as String?;
      final icon = await _buildMarkerIcon(name,
          photoURL: photoURL, uid: barber.id);
      final loc = barber.data['location'] as Map;
      markers.add(
        Marker(
          markerId: MarkerId(barber.id),
          position: LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          ),
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          onTap: () =>
              showBarberProfileSheet(context, barber.id, barber.data),
        ),
      );
    }
    if (mounted) setState(() => _markers = markers);
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
      markers: _markers,
    );
  }
}
