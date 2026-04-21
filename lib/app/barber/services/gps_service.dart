import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'fcm_service.dart';

// ── Datos mínimos de una cita programada próxima ────────────────
class _UpcomingAppt {
  final String id;
  final String clientName;
  final DateTime scheduledAt;
  final double? clientLat;
  final double? clientLng;

  const _UpcomingAppt({
    required this.id,
    required this.clientName,
    required this.scheduledAt,
    this.clientLat,
    this.clientLng,
  });
}

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

  // ── Recordatorio de proximidad ──────────────────────────────
  List<_UpcomingAppt> _upcomingScheduled = [];
  final Set<String> _notifiedApptIds = {};

  // Throttle: evita escribir a Firestore en cada tick GPS
  DateTime? _lastWriteTime;
  double? _lastWrittenLat;
  double? _lastWrittenLng;
  static const _minWriteIntervalNoCita = Duration(seconds: 60); // Sin cita activa
  static const _minWriteIntervalConCita = Duration(seconds: 30); // Con cita confirmada
  static const _minMovementMeters = 5.0; // Escribir si se movió 5m

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  /// Inicia el servicio. Llamar desde BarberHomeScreen.initState().
  /// Si ya está corriendo, no hace nada.
  Future<void> start() async {
    if (_running) {
      print('🚨 [BarberGpsService] YA ESTÁ CORRIENDO');
      return;
    }
    _running = true;
    print('🚀 [BarberGpsService] INICIANDO...');

    // Verificar permisos
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('📍 [BarberGpsService] GPS habilitado: $serviceEnabled');
    if (!serviceEnabled) {
      _running = false;
      print('❌ [BarberGpsService] GPS NO habilitado, abortando');
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    print('🔐 [BarberGpsService] Permiso actual: $perm');
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      print('🔐 [BarberGpsService] Permiso solicitado: $perm');
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      _running = false;
      print('❌ [BarberGpsService] Permisos denegados: $perm');
      return;
    }

    print('✅ [BarberGpsService] Permisos OK, iniciando stream...');
    // Escuchar cita inmediata activa para publicar coords en ella
    _listenActiveAppointment();

    // Iniciar stream GPS con foreground service en Android
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0, // 0 = recibir eventos cada 5 segundos
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Yaccut — Compartiendo ubicación',
              notificationText: 'Tu posición es visible para tus clientes',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0, // 0 = sin filtro de distancia
          );

    _posSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_onPosition, onError: (e) {
      print('❌ [BarberGpsService] Error en stream GPS: $e');
    });
    print('✅ [BarberGpsService] Stream GPS iniciado correctamente');
  }

  /// Detiene el servicio y limpia la ruta. Llamar al cerrar sesión.
  Future<void> stop() async {
    _running = false;
    await _posSub?.cancel();
    await _apptSub?.cancel();
    _posSub = null;
    _apptSub = null;
    _activeApptId = null;
    _lastWriteTime = null;
    _lastWrittenLat = null;
    _lastWrittenLng = null;
    _upcomingScheduled = [];
    _notifiedApptIds.clear();

    final uid = _uid;
    if (uid == null) return;
    _db
        .collection('users')
        .doc(uid)
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
        .where('status', whereIn: ['confirmed', 'en_servicio'])
        .snapshots()
        .listen((snap) {
          final now = DateTime.now();

          // Cita inmediata → GPS tracking del cliente (prioridad máxima)
          final active = snap.docs
              .where((d) => (d.data()['isImmediate'] as bool?) == true)
              .firstOrNull;

          // Cita programada en camino → también activar GPS tracking
          final departing = active == null
              ? snap.docs.where((d) {
                  final data = d.data();
                  return (data['isImmediate'] as bool?) != true &&
                      (data['barberDeparting'] as bool?) == true;
                }).firstOrNull
              : null;

          _activeApptId = active?.id ?? departing?.id;

          // Citas programadas futuras pendientes de recordatorio
          _upcomingScheduled = snap.docs
              .where((d) {
                final data = d.data();
                if ((data['isImmediate'] as bool?) == true) return false;
                if ((data['barberDeparting'] as bool?) == true)
                  return false; // ya salió
                final ts = data['scheduledAt'] as Timestamp?;
                if (ts == null) return false;
                return ts.toDate().isAfter(now);
              })
              .map((d) {
                final data = d.data();
                return _UpcomingAppt(
                  id: d.id,
                  clientName: data['clientName'] as String? ?? 'Cliente',
                  scheduledAt: (data['scheduledAt'] as Timestamp).toDate(),
                  clientLat: (data['clientLat'] as num?)?.toDouble(),
                  clientLng: (data['clientLng'] as num?)?.toDouble(),
                );
              })
              .toList();
        }, onError: (_) {});
  }

  void _onPosition(Position pos) {
    final uid = _uid;
    if (uid == null) {
      print('❌ [BarberGpsService._onPosition] UID es null');
      return;
    }

    // Throttle dinámico: 30s con cita confirmada, 60s sin cita
    final hasActiveCita = _activeApptId != null;
    final minWriteInterval = hasActiveCita
        ? _minWriteIntervalConCita
        : _minWriteIntervalNoCita;

    final now = DateTime.now();
    if (_lastWriteTime != null && _lastWrittenLat != null && _lastWrittenLng != null) {
      final elapsed = now.difference(_lastWriteTime!);
      final moved = Geolocator.distanceBetween(
        _lastWrittenLat!,
        _lastWrittenLng!,
        pos.latitude,
        pos.longitude,
      );
      if (elapsed < minWriteInterval && moved < _minMovementMeters) {
        print('⏸️ [BarberGpsService] Throttle: elapsed=${elapsed.inSeconds}s, moved=${moved.toStringAsFixed(1)}m, minInterval=${minWriteInterval.inSeconds}s');
        return;
      }
    }
    _lastWriteTime = now;
    _lastWrittenLat = pos.latitude;
    _lastWrittenLng = pos.longitude;

    print('📤 [BarberGpsService] Escribiendo ubicación: lat=${pos.latitude.toStringAsFixed(6)}, lng=${pos.longitude.toStringAsFixed(6)} (cita: $hasActiveCita)');

    // 1. Actualizar posición en el doc del usuario (usar set() con merge en caso que no exista)
    _db
        .collection('users')
        .doc(uid)
        .set({'location': {'lat': pos.latitude, 'lng': pos.longitude}}, SetOptions(merge: true))
        .then((_) => print('✅ [BarberGpsService] Ubicación guardada en users/$uid'))
        .catchError((e) => print('❌ [BarberGpsService] Error guardando ubicación: $e'));

    // 2. Si hay cita activa, publicar coords para tracking del cliente
    final apptId = _activeApptId;
    if (apptId != null) {
      print('🎯 [BarberGpsService] Hay cita activa: $apptId, actualizando tracking...');
      _db
          .collection('appointments')
          .doc(apptId)
          .update({
            'barberCurrentLat': pos.latitude,
            'barberCurrentLng': pos.longitude,
          })
          .then((_) => print('✅ [BarberGpsService] Tracking actualizado en cita $apptId'))
          .catchError((e) => print('❌ [BarberGpsService] Error actualizando tracking: $e'));
    }

    // 3. Verificar si hay que recordar una cita próxima
    _checkUpcomingAppointments(pos);
  }

  /// Compara la posición actual del barbero con sus citas programadas próximas.
  /// Notifica cuando: tiempo_restante ≤ tiempo_de_viaje_estimado + 10 min buffer.
  void _checkUpcomingAppointments(Position pos) {
    final now = DateTime.now();
    // Velocidad ciudad conservadora ~25 km/h = 6.94 m/s
    const citySpeedMps = 6.94;
    const bufferMinutes = 10;

    for (final appt in _upcomingScheduled) {
      if (_notifiedApptIds.contains(appt.id)) continue;
      if (appt.clientLat == null || appt.clientLng == null) continue;

      final minutesUntilAppt = appt.scheduledAt.difference(now).inMinutes;
      if (minutesUntilAppt <= 0) continue; // ya pasó

      final distanceMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        appt.clientLat!,
        appt.clientLng!,
      );

      final travelMinutes = (distanceMeters / citySpeedMps / 60).ceil();

      if (minutesUntilAppt <= travelMinutes + bufferMinutes) {
        _notifiedApptIds.add(appt.id);

        final distStr = distanceMeters < 1000
            ? '${distanceMeters.round()} m'
            : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

        // Solo recordatorio local — el barbero confirma manualmente con "Salir ahora"
        FcmService.instance.showLocalReminder(
          id: appt.id.hashCode,
          title: '⏰ ¡Es hora de salir!',
          body:
              'Tu cita con ${appt.clientName} en $minutesUntilAppt min — '
              'estás a $distStr (~$travelMinutes min en camino).',
        );
      }
    }
  }
}
