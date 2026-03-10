import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/splash_screen.dart';
import '../../../client/screens/welcome_dialog.dart';
import '../edit_profile_screen.dart';

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

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final snap = await _userDoc.get();
      final d = snap.data() ?? {};
      setState(() {
        _name = d['name'] ??
            FirebaseAuth.instance.currentUser?.displayName ??
            'Barbero';
        _photoURL = d['photoURL'] as String?;
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _changeProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galería'),
                onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(context, ImageSource.camera)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
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
      final ref =
          FirebaseStorage.instance.ref('users/$_uid/profile/profile.jpg');
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.redAccent));
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
                backgroundColor: Colors.grey[800],
                backgroundImage:
                    _photoURL != null ? NetworkImage(_photoURL!) : null,
                child: _uploadingPhoto
                    ? const CircularProgressIndicator()
                    : _photoURL == null
                        ? const Icon(Icons.person,
                            size: 50, color: Colors.white54)
                        : null,
              ),
              GestureDetector(
                onTap: _changeProfilePhoto,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF111217), width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 14, color: Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _loadingProfile
              ? const SizedBox(height: 20)
              : Text(
                  _name,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.grey[400]),
          ),
          const SizedBox(height: 24),

          // ── Opciones ────────────────────────────────────
          _ProfileTile(
            icon: Icons.person_outline,
            label: 'Editar perfil',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const EditProfileScreen()),
              );
              // Recargar nombre y foto al volver
              _loadProfile();
            },
          ),
          _ProfileTile(
            icon: Icons.star_border,
            label: 'Mis reseñas',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.bar_chart,
            label: 'Estadísticas',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            label: 'Notificaciones',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            label: 'Ayuda y soporte',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.description_outlined,
            label: 'Términos y condiciones',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12),
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
          Text(
            'YaCut v1.0.0',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
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
        leading: Icon(icon, color: iconColor ?? Colors.white70),
        title: Text(
          label,
          style: TextStyle(color: labelColor ?? Colors.white, fontSize: 15),
        ),
        trailing: const Icon(Icons.chevron_right,
            color: Colors.white38, size: 20),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
