import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../barber_profile_sheet.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _initialPosition = LatLng(4.7110, -74.0721); // Bogotá
  static const _barbersCacheKey = 'home_barbers_cache';
  static const _barbersCacheTtlMs = 30 * 1000; // 30 seg en ms (era 5 min)
  final _mapReady = Completer<GoogleMapController>();
  bool _locationGranted = false;
  bool _locationChecked = false;
  bool _permissionDeniedForever = false;
  Set<Marker> _markers = {};
  StreamSubscription<QuerySnapshot>? _barbersSub;
  Timer? _scheduleTimer;
  // Caché local de barberos: no necesita tocar Firestore para re-evaluar horario
  final List<({String id, Map<String, dynamic> data})> _cachedBarbers = [];

  @override
  void initState() {
    super.initState();
    // Esperar al primer frame para que la UI esté lista antes de pedir permisos
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestLocation());
    // Limpiar caché viejo de barberos para asegurar datos frescos
    _clearOldCache();
    _loadCachedBarbers(); // Muestra marcadores instantáneamente desde disco
    _listenToBarbers(); // Actualiza con datos frescos de Firestore
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
    _photoCacheOrder.clear();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    final permission = await Geolocator.checkPermission();
    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (mounted) {
      setState(() {
        _locationChecked = true;
        _locationGranted = granted;
        _permissionDeniedForever =
            permission == LocationPermission.deniedForever;
      });
    }
    if (granted) {
      _centerOnUserLocation();
    }
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
      debugPrint('Error centrando mapa cliente: $e');
    }
  }

  // ── Construye un marcador personalizado con inicial del barbero ──
  // LRU cache de fotos: máx 20 entradas, evicta la más antigua al superar límite
  final Map<String, ui.Image?> _photoCache = {};
  final Map<String, String> _photoCacheURL = {}; // UID → URL cacheada
  final List<String> _photoCacheOrder = []; // orden LRU: último = más reciente
  static const _photoCacheMaxSize = 20;

  Future<ui.Image?> _fetchPhoto(String uid, String url) async {
    // Si la URL cambió, invalidar entrada existente
    if (_photoCacheURL[uid] != url) {
      _photoCache[uid]?.dispose();
      _photoCache.remove(uid);
      _photoCacheURL.remove(uid);
      _photoCacheOrder.remove(uid);
    }
    if (_photoCache.containsKey(uid)) {
      // Promover a "más reciente" en el LRU
      _photoCacheOrder.remove(uid);
      _photoCacheOrder.add(uid);
      return _photoCache[uid];
    }
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

      // Evictar la entrada más antigua si se supera el límite
      if (_photoCacheOrder.length >= _photoCacheMaxSize) {
        final evict = _photoCacheOrder.removeAt(0);
        _photoCache[evict]?.dispose();
        _photoCache.remove(evict);
        _photoCacheURL.remove(evict);
      }

      _photoCache[uid] = frame.image;
      _photoCacheURL[uid] = url;
      _photoCacheOrder.add(uid);
      client.close();
      return frame.image;
    } catch (_) {
      _photoCache[uid] = null;
      return null;
    }
  }

  Future<BitmapDescriptor> _buildMarkerIcon(
    String name, {
    String? photoURL,
    String? uid,
  }) async {
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
        ..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: r - 2));
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
      final paragraphBuilder =
          ui.ParagraphBuilder(
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
      canvas.drawParagraph(paragraph, Offset(0, cy - paragraph.height / 2));
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
      'monday', // 1
      'tuesday', // 2
      'wednesday', // 3
      'thursday', // 4
      'friday', // 5
      'saturday', // 6
      'sunday', // 7
    ];

    final schedule = data['schedule'];
    if (schedule == null || schedule is! Map)
      return true; // sin horario → mostrar

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
    final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
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
          _saveCachedBarbers(); // Persiste en disco para el próximo arranque
        });
  }

  // Limpia el caché viejo de barberos para forzar datos frescos
  Future<void> _clearOldCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_barbersCacheKey);
    } catch (_) {}
  }

  // Carga la cache persistida y muestra marcadores sin esperar a Firestore
  Future<void> _loadCachedBarbers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_barbersCacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = decoded['cachedAt'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - cachedAt > _barbersCacheTtlMs)
        return;
      final list = decoded['data'] as List<dynamic>;
      _cachedBarbers.clear();
      for (final item in list) {
        final entry = item as Map<String, dynamic>;
        _cachedBarbers.add((
          id: entry['id'] as String,
          data: Map<String, dynamic>.from(entry['data'] as Map),
        ));
      }
      await _rebuildMarkersFromCache();
    } catch (_) {}
  }

  // Persiste solo los campos usados (tipos JSON-seguros, sin Timestamp/GeoPoint)
  Future<void> _saveCachedBarbers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _cachedBarbers.map((b) {
        final d = b.data;
        return {
          'id': b.id,
          'data': {
            'name': d['name'],
            'photoURL': d['photoURL'],
            'isAvailable': d['isAvailable'],
            'isBusy': d['isBusy'] ?? false,
            'role': d['role'] is List
                ? List<dynamic>.from(d['role'] as List)
                : d['role'],
            'location': d['location'],
            'schedule': d['schedule'],
          },
        };
      }).toList();
      await prefs.setString(
        _barbersCacheKey,
        jsonEncode({
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
          'data': list,
        }),
      );
    } catch (_) {}
  }

  // Reconstruye marcadores usando la caché — sin tocar Firestore
  Future<void> _rebuildMarkersFromCache() async {
    final markers = <Marker>{};
    for (final barber in List.of(_cachedBarbers)) {
      if (!_isWithinSchedule(barber.data)) continue;
      final name = (barber.data['name'] ?? 'Barbero') as String;
      final photoURL = barber.data['photoURL'] as String?;
      final icon = await _buildMarkerIcon(
        name,
        photoURL: photoURL,
        uid: barber.id,
      );
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
          onTap: () => showBarberProfileSheet(context, barber.id, barber.data),
        ),
      );
    }
    if (mounted) setState(() => _markers = markers);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
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
        if (_locationChecked && !_locationGranted)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: _LocationPermissionBanner(
              deniedForever: _permissionDeniedForever,
              onTap: _permissionDeniedForever
                  ? () => Geolocator.openAppSettings()
                  : _requestLocation,
            ),
          ),
      ],
    );
  }
}

// ── Banner de permisos de ubicación ─────────────────────────────
class _LocationPermissionBanner extends StatelessWidget {
  final bool deniedForever;
  final VoidCallback onTap;
  const _LocationPermissionBanner({
    required this.deniedForever,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC9A84C).withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFFC9A84C),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A84C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFC9A84C).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFFC9A84C),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deniedForever
                            ? 'Ubicación bloqueada'
                            : 'Activa tu ubicación',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        deniedForever
                            ? 'Ve a Ajustes para permitir el acceso'
                            : 'Para ver barberos cerca de ti',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC9A84C),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      deniedForever ? 'Ajustes' : 'Activar',
                      style: const TextStyle(
                        color: Color(0xFF0D0D12),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
