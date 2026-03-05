import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/gps_service.dart';
import '../work_schedule_screen.dart';
import '../services_screen.dart';

class BarberSettingsTab extends StatefulWidget {
  const BarberSettingsTab({super.key});

  @override
  State<BarberSettingsTab> createState() => _BarberSettingsTabState();
}

class _BarberSettingsTabState extends State<BarberSettingsTab> {
  bool _available = false;
  bool _notificationsEnabled = true;
  StreamSubscription<Position>? _locationSub;
  // Buffer local: acumula los últimos 50 puntos de ruta sin leer Firestore
  final List<Map<String, double>> _routeBuffer = [];

  DocumentReference<Map<String, dynamic>> get _userDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAvailability();
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
              notificationText:
                  'Tu posición es visible para tus clientes',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          );

    _locationSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((pos) {
      // Acumula punto en buffer local (máx 50)
      _routeBuffer.add({'lat': pos.latitude, 'lng': pos.longitude});
      if (_routeBuffer.length > 50) _routeBuffer.removeAt(0);

      // Escribe posición actual + ruta en el doc del usuario barbero
      _userDoc.set({
        'location': {'lat': pos.latitude, 'lng': pos.longitude},
        'liveRoute': List<Map<String, double>>.from(_routeBuffer),
      }, SetOptions(merge: true));
    });
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
      final snap = await _userDoc.get();
      final data = snap.data();
      if (data != null && data['isAvailable'] is bool) {
        final isAvail = data['isAvailable'] as bool;
        if (mounted) setState(() => _available = isAvail);
        if (isAvail) {
          final hasPermission = await _ensureLocationPermission();
          if (hasPermission) _startLocationStream();
        }
      }
    } catch (_) {}
  }

  Future<void> _setAvailability(bool val) async {
    setState(() => _available = val);
    try {
      Map<String, dynamic> data = {'isAvailable': val};
      if (val) {
        final hasPermission = await _ensureLocationPermission();
        if (hasPermission) {
          // Posición inmediata + limpiar ruta anterior
          final pos = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.high),
          );
          data['location'] = {'lat': pos.latitude, 'lng': pos.longitude};
          data['liveRoute'] = <Map<String, double>>[];
          await _userDoc.set(data, SetOptions(merge: true));
          _startLocationStream();
          BarberGpsService.instance.start();
          return;
        }
      } else {
        _stopLocationStream();
        BarberGpsService.instance.stop();
      }
      await _userDoc.set(data, SetOptions(merge: true));
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

        // Notificaciones
        _SectionHeader('Notificaciones'),
        _SettingCard(
          child: Row(
            children: [
              const Icon(Icons.notifications_outlined),
              const SizedBox(width: 12),
              const Expanded(child: Text('Notificaciones push')),
              Switch(
                value: _notificationsEnabled,
                onChanged: (val) => setState(() => _notificationsEnabled = val),
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WorkScheduleScreen()),
          ),
        ),

        const SizedBox(height: 24),

        // Servicios
        _SectionHeader('Servicios'),
        _SettingTile(
          icon: Icons.content_cut,
          title: 'Mis servicios',
          subtitle: 'Agrega o edita los servicios que ofreces',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ServicesScreen()),
          ),
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
