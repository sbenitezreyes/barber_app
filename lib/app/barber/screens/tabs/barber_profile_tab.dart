import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/help_screen.dart';
import '../../../shared/splash_screen.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/auth/terms_screen.dart';
import '../../../client/screens/welcome_dialog.dart';
import '../barber_notifications_screen.dart';
import '../barber_stats_screen.dart';
import '../edit_profile_screen.dart';

const _barberFaqs = <({String q, String a})>[
  (
    q: '¿Cómo acepto una cita?',
    a: 'Cuando un cliente haga una reserva recibirás una notificación. Ve a la pestaña Agenda, selecciona la cita pendiente y toca "Aceptar". El cliente será notificado al instante.',
  ),
  (
    q: '¿Cómo rechazo una solicitud?',
    a: 'En la pestaña Agenda, selecciona la cita pendiente y toca "Rechazar". El cliente recibirá una notificación informándole que no pudiste aceptar.',
  ),
  (
    q: '¿Cómo marco una cita como completada?',
    a: 'Una vez terminado el servicio, ve a la cita confirmada en la pestaña Agenda y toca "Completar cita". Esto también libera tu estado y te otorga XP.',
  ),
  (
    q: '¿Cómo cancelo una cita ya confirmada?',
    a: 'En la pestaña Agenda, selecciona la cita confirmada y toca "Cancelar". El cliente recibirá una notificación y tu estado volverá a disponible.',
  ),
  (
    q: '¿Cómo activo o desactivo mi disponibilidad?',
    a: 'En la pestaña Agenda usa el interruptor de disponibilidad. Cuando estés desactivado no aparecerás en el mapa de clientes.',
  ),
  (
    q: '¿Qué es el XP y para qué sirve?',
    a: 'El XP (puntos de experiencia) mide tu actividad en la plataforma. Ganas 50 XP por cada cita completada y hasta 30 XP adicionales por reseñas positivas.',
  ),
  (
    q: '¿Cómo edito mis servicios y precios?',
    a: 'Ve a Perfil → Editar perfil. Desde ahí puedes actualizar tu lista de servicios, precios y horario de atención.',
  ),
  (
    q: '¿Mis datos y ubicación están seguros?',
    a: 'Sí. YaCut usa Firebase con cifrado en tránsito y en reposo. Tu ubicación GPS solo se comparte durante una cita confirmada y se elimina automáticamente al completarla.',
  ),
  (
    q: '¿Por qué no me aparecen clientes?',
    a: 'Verifica que tu disponibilidad esté activada y que tu ubicación GPS esté encendida. Los clientes solo ven barberos con disponibilidad activa en su zona.',
  ),
  (
    q: '¿Cómo contacto a soporte?',
    a: 'Puedes escribirnos directamente al correo yacut2026@gmail.com desde la sección de contacto en esta misma pantalla.',
  ),
];

class BarberProfileTab extends StatefulWidget {
  const BarberProfileTab({super.key});

  @override
  State<BarberProfileTab> createState() => _BarberProfileTabState();
}

class _BarberProfileTabState extends State<BarberProfileTab> {
  String _name = '';
  String? _photoURL;
  bool _loadingProfile = true;
  bool _uploadingPhoto = false;
  final _picker = ImagePicker();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _profileSub = _userDoc.snapshots().listen(
      (snap) {
        if (!mounted) return;
        final d = snap.data() ?? {};
        setState(() {
          _name =
              d['name'] as String? ??
              FirebaseAuth.instance.currentUser?.displayName ??
              'Barbero';
          _photoURL = d['photoURL'] as String?;
          _loadingProfile = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loadingProfile = false);
      },
    );
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _changeProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;
    }
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 75,
        minWidth: 800,
        minHeight: 800,
      );
      final ref = FirebaseStorage.instance.ref(
        'users/$_uid/profile/profile.jpg',
      );
      await ref.putData(
        Uint8List.fromList(compressed),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      await _userDoc.set({'photoURL': url}, SetOptions(merge: true));
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      if (mounted) setState(() => _photoURL = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // ── Foto de perfil ──────────────────────────────
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.surfaceElevated,
                backgroundImage: _photoURL != null
                    ? CachedNetworkImageProvider(_photoURL!)
                    : null,
                child: _uploadingPhoto
                    ? const CircularProgressIndicator()
                    : _photoURL == null
                    ? const Icon(
                        Icons.person,
                        size: 50,
                        color: AppColors.textTertiary,
                      )
                    : null,
              ),
              GestureDetector(
                onTap: _changeProfilePhoto,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _loadingProfile
              ? const SizedBox(height: 20)
              : Text(_name, style: AppTextStyles.title),
          const SizedBox(height: 4),
          Text(user?.email ?? '', style: AppTextStyles.caption),
          const SizedBox(height: 24),

          // ── Opciones ────────────────────────────────────
          _ProfileTile(
            icon: Icons.person_outline,
            label: 'Editar perfil',
            onTap: () async {
              await Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const EditProfileScreen(),
                  transitionsBuilder: (_, anim, __, child) => SlideTransition(
                    position: Tween(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOut)).animate(anim),
                    child: child,
                  ),
                ),
              );
            },
          ),
          _ProfileTile(
            icon: Icons.bar_chart,
            label: 'Estadísticas',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => const BarberStatsScreen(),
                transitionsBuilder: (_, animation, __, child) =>
                    SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 1), end: Offset.zero)
                              .chain(CurveTween(curve: Curves.easeOut))
                              .animate(animation),
                      child: child,
                    ),
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            label: 'Notificaciones',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) =>
                    const BarberNotificationsScreen(),
                transitionsBuilder: (_, animation, __, child) =>
                    SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 1), end: Offset.zero)
                              .chain(CurveTween(curve: Curves.easeOut))
                              .animate(animation),
                      child: child,
                    ),
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            label: 'Ayuda y soporte',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) =>
                    const HelpScreen(faqs: _barberFaqs),
                transitionsBuilder: (_, animation, __, child) =>
                    SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 1), end: Offset.zero)
                              .chain(CurveTween(curve: Curves.easeOut))
                              .animate(animation),
                      child: child,
                    ),
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.description_outlined,
            label: 'Términos y condiciones',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => const TermsScreen(),
                transitionsBuilder: (_, animation, __, child) =>
                    SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 1), end: Offset.zero)
                              .chain(CurveTween(curve: Curves.easeOut))
                              .animate(animation),
                      child: child,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.borderSubtle),
          const SizedBox(height: 8),

          // ── Cerrar sesión ────────────────────────────────
          _ProfileTile(
            icon: Icons.logout,
            label: 'Cerrar sesión',
            iconColor: Colors.redAccent,
            labelColor: Colors.redAccent,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              await WelcomeDialog.reset();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashScreen()),
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 24),
          Text('YaCut v1.0.0', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: iconColor ?? AppColors.textSecondary),
        title: Text(
          label,
          style: AppTextStyles.subtitle.copyWith(color: labelColor),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textTertiary,
          size: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
