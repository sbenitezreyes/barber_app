import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// Servicio singleton que mantiene el GPS activo en background.
/// Publica la posición del barbero en:
///   - users/{uid}.location  (marcador en mapa de búsqueda)
///   - appointments/{id}.barberCurrentLat/Lng  (tracking en tiempo real del cliente)
///
/// Corre de forma totalmente independiente de la navegación.
class BarberGpsService {
  BarberGpsService._();
  static final BarberGpsService instance = BarberGpsService._();

  StreamSubscription<Position>? _posSub;
  StreamSubscription<QuerySnapshot>? _apptSub;
  String? _activeApptId;
  bool _running = false;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  /// Inicia el servicio. Llamar desde BarberHomeScreen.initState().
  /// Si ya está corriendo, no hace nada.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    // Verificar permisos
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) { _running = false; return; }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      _running = false;
      return;
    }

    // Escuchar cita inmediata activa para publicar coords en ella
    _listenActiveAppointment();

    // Iniciar stream GPS con foreground service en Android
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 8,
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Yaccut — Compartiendo ubicación',
              notificationText:
                  'Tu posición es visible para tus clientes',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 8,
          );

    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (_) {});
  }

  /// Detiene el servicio y limpia la ruta. Llamar al cerrar sesión.
  Future<void> stop() async {
    _running = false;
    await _posSub?.cancel();
    await _apptSub?.cancel();
    _posSub = null;
    _apptSub = null;
    _activeApptId = null;

    final uid = _uid;
    if (uid == null) return;
    _db.collection('users').doc(uid)
        .set({'liveRoute': <dynamic>[]}, SetOptions(merge: true))
        .catchError((_) {});
  }

  void _listenActiveAppointment() {
    final uid = _uid;
    if (uid == null) return;
    _apptSub?.cancel();
    _apptSub = _db
        .collection('appointments')
        .where('barberUid', isEqualTo: uid)
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .listen((snap) {
      final active = snap.docs
          .where((d) => (d.data()['isImmediate'] as bool?) == true)
          .firstOrNull;
      _activeApptId = active?.id;
    }, onError: (_) {});
  }

  void _onPosition(Position pos) {
    final uid = _uid;
    if (uid == null) return;

    // 1. Actualizar posición en el doc del usuario
    _db.collection('users').doc(uid).set({
      'location': {'lat': pos.latitude, 'lng': pos.longitude},
    }, SetOptions(merge: true)).catchError((_) {});

    // 2. Si hay cita activa, publicar coords para tracking del cliente
    final apptId = _activeApptId;
    if (apptId != null) {
      _db.collection('appointments').doc(apptId).update({
        'barberCurrentLat': pos.latitude,
        'barberCurrentLng': pos.longitude,
      }).catchError((_) {});
    }
  }
}
