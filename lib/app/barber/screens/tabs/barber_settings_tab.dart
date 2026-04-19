import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/fcm_service.dart';
import '../../services/gps_service.dart';
import '../barber_emergency_contacts_screen.dart';
import '../work_schedule_screen.dart';
import '../services_screen.dart';

class BarberSettingsTab extends StatefulWidget {
  const BarberSettingsTab({super.key});

  @override
  State<BarberSettingsTab> createState() => _BarberSettingsTabState();
}

class _BarberSettingsTabState extends State<BarberSettingsTab> {
  bool _available = false;
  StreamSubscription<Position>? _locationSub;
  // Mantiene el doc del usuario en caché para que las lecturas posteriores
  // (ej. BarberEmergencyContacts) sean instantáneas.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  // Buffer local: acumula los últimos 50 puntos de ruta sin leer Firestore
  final List<Map<String, double>> _routeBuffer = [];

  DocumentReference<Map<String, dynamic>> get _userDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAvailability();
    // Mantener el doc del usuario en caché local para lecturas instantáneas
    _userDocSub = _userDoc.snapshots().listen((_) {});
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  void _startLocationStream() {
    debugPrint('🚀 [BarberSettings] Iniciando location stream...');
    _locationSub?.cancel();
    _routeBuffer.clear();

    // Usar AndroidSettings con ForegroundService para liveRoute en el mapa.
    // El tracking de la cita (barberCurrentLat/Lng) lo maneja BarberGpsService.
    final locationSettings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Yaccut — Compartiendo ubicación',
              notificationText: 'Tu posición es visible para tus clientes',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          );

    _locationSub =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) {
            // Acumula punto en buffer local (máx 50)
            _routeBuffer.add({'lat': pos.latitude, 'lng': pos.longitude});
            if (_routeBuffer.length > 50) _routeBuffer.removeAt(0);

            // Escribe posición actual + ruta en el doc del usuario barbero
            _userDoc.set({
              'location': {'lat': pos.latitude, 'lng': pos.longitude},
              'liveRoute': List<Map<String, double>>.from(_routeBuffer),
            }, SetOptions(merge: true));
          },
        );
  }

  void _stopLocationStream() {
    _locationSub?.cancel();
    _locationSub = null;
    _routeBuffer.clear();
    // Borra la ruta del barbero cuando se desconecta
    _userDoc.set({'liveRoute': []}, SetOptions(merge: true));
  }

  Future<void> _loadAvailability() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _userDoc.get(const GetOptions(source: Source.cache));
      } catch (_) {
        snap = await _userDoc.get();
      }
      final data = snap.data();
      if (data != null && data['isAvailable'] is bool) {
        final isAvail = data['isAvailable'] as bool;
        FcmService.instance.isAvailable.value = isAvail;
        // Solo actualizar el estado visual — NO reiniciar GPS automáticamente
        // El GPS debe iniciarse SOLO cuando el usuario activa el toggle
        if (mounted) setState(() => _available = isAvail);
      }
    } catch (_) {}
  }

  Future<void> _setAvailability(bool val) async {
    setState(() => _available = val);
    FcmService.instance.isAvailable.value = val;
    try {
      Map<String, dynamic> data = {'isAvailable': val};
      if (val) {
        // ✅ DISPONIBLE: Iniciar GPS
        print('🟢 [BarberSettings] Disponible = true, iniciando GPS service...');
        // Limpiar ruta anterior
        data['liveRoute'] = <Map<String, double>>[];
        // Escribir a Firestore en background (NO esperar)
        _userDoc.set(data, SetOptions(merge: true)).catchError((_) {});
        // Iniciar location stream en background (NO bloquear UI)
        Future.microtask(_startLocationStream);
        // Iniciar GPS service para mapa principal
        Future.microtask(() => BarberGpsService.instance.start());
        return;
      } else {
        // ❌ NO DISPONIBLE: Parar GPS
        print('🔴 [BarberSettings] Disponible = false, deteniendo GPS service...');
        _stopLocationStream();
        // Parar GPS service para ahorrar recursos
        await BarberGpsService.instance.stop();
        // Escribir cambio en background
        _userDoc.set(data, SetOptions(merge: true)).catchError((_) {});
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _available = !val);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Estado de disponibilidad
        _SectionHeader('Disponibilidad'),
        _SettingCard(
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: _available ? Colors.greenAccent : Colors.grey[600],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _available ? 'Disponible' : 'No disponible',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _available
                          ? 'Estás recibiendo solicitudes de clientes'
                          : 'Activa tu disponibilidad para recibir solicitudes',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _available,
                onChanged: _setAvailability,
                activeThumbColor: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Horarios
        _SectionHeader('Horarios de trabajo'),
        _SettingTile(
          icon: Icons.schedule,
          title: 'Horario laboral',
          subtitle: 'Configura tus horas de atención',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const WorkScheduleScreen())),
        ),

        const SizedBox(height: 24),

        // Servicios
        _SectionHeader('Servicios'),
        _SettingTile(
          icon: Icons.content_cut,
          title: 'Mis servicios',
          subtitle: 'Agrega o edita los servicios que ofreces',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ServicesScreen())),
        ),

        const SizedBox(height: 24),

        // Seguridad
        _SectionHeader('Seguridad'),
        _SettingTile(
          icon: Icons.shield_outlined,
          title: 'Contactos de emergencia',
          subtitle: 'Personas de confianza a alertar si algo pasa',
          onTap: () => BarberEmergencyContacts.openFromSettings(context),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white54,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final Widget child;
  const _SettingCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}
