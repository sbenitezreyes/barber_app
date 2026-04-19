import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/theme/app_theme.dart';

class ClientEditProfileScreen extends StatefulWidget {
  const ClientEditProfileScreen({super.key});

  @override
  State<ClientEditProfileScreen> createState() =>
      _ClientEditProfileScreenState();
}

class _ClientEditProfileScreenState extends State<ClientEditProfileScreen>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _photoURL;
  DateTime? _birthDate;
  bool _loadingProfile = true;
  bool _uploadingPhoto = false;
  bool _saving = false;

  int? get _age {
    if (_birthDate == null) return null;
    final today = DateTime.now();
    int age = today.year - _birthDate!.year;
    if (today.month < _birthDate!.month ||
        (today.month == _birthDate!.month && today.day < _birthDate!.day)) {
      age--;
    }
    return age;
  }

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadProfile();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final snap = await _userDoc.get();
      final d = snap.data() ?? {};
      final name =
          d['name'] as String? ??
          FirebaseAuth.instance.currentUser?.displayName ??
          '';
      final photoURL =
          d['photoURL'] as String? ??
          FirebaseAuth.instance.currentUser?.photoURL;
      final birthTs = d['birthDate'] as Timestamp?;

      if (!mounted) return;
      setState(() {
        _photoURL = photoURL;
        _nameCtrl.text = name;
        _birthDate = birthTs?.toDate();
        _loadingProfile = false;
      });
      _fadeCtrl.forward();
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<List<int>> _compress(XFile picked) async {
    final bytes = await picked.readAsBytes();
    return FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      minWidth: 800,
      minHeight: 800,
      format: CompressFormat.webp,
    );
  }

  Future<void> _changePhoto() async {
    final source = await _showSourcePicker();
    if (source == null) return;
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;
    }
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final compressed = await _compress(picked);
      final ref = FirebaseStorage.instance.ref(
        'users/$_uid/profile/profile.webp',
      );
      await ref.putData(
        Uint8List.fromList(compressed),
        SettableMetadata(contentType: 'image/webp'),
      );
      final url = await ref.getDownloadURL();
      await _userDoc.set({'photoURL': url}, SetOptions(merge: true));
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      if (mounted) setState(() => _photoURL = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir foto: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final name = _nameCtrl.text.trim();

      final Map<String, dynamic> data = {'name': name};
      if (_birthDate != null) {
        data['birthDate'] = Timestamp.fromDate(_birthDate!);
      }

      await _userDoc.set(data, SetOptions(merge: true));
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ImageSource?> _showSourcePicker() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.gold,
              ),
              title: Text('Galería', style: AppTextStyles.body),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.gold,
              ),
              title: Text('Cámara', style: AppTextStyles.body),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Editar perfil', style: AppTextStyles.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loadingProfile
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : FadeTransition(
              opacity: _fadeAnim,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Avatar ──────────────────────────────
                      Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _uploadingPhoto
                                      ? AppColors.gold
                                      : AppColors.borderMedium,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 58,
                                backgroundColor: AppColors.surfaceElevated,
                                child: _uploadingPhoto
                                    ? const CircularProgressIndicator(
                                        color: AppColors.gold,
                                        strokeWidth: 2,
                                      )
                                    : _photoURL != null
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: _photoURL!,
                                          width: 116,
                                          height: 116,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person,
                                        size: 58,
                                        color: AppColors.textTertiary,
                                      ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _uploadingPhoto ? null : _changePhoto,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.background,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 16,
                                  color: AppColors.background,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // ── Nombre ──────────────────────────────
                      Text('NOMBRE', style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          hintText: 'Tu nombre completo',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'El nombre es obligatorio';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // ── Fecha de nacimiento ──────────────────
                      Text('FECHA DE NACIMIENTO', style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _birthDate ??
                                DateTime(now.year - 25, now.month, now.day),
                            firstDate: DateTime(now.year - 100),
                            lastDate: DateTime(
                              now.year - 13,
                              now.month,
                              now.day,
                            ),
                            locale: const Locale('es'),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                colorScheme: Theme.of(
                                  ctx,
                                ).colorScheme.copyWith(primary: AppColors.gold),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() => _birthDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceInput,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cake_outlined,
                                color: AppColors.textTertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _birthDate == null
                                    ? Text(
                                        'Selecciona tu fecha de nacimiento',
                                        style: AppTextStyles.body.copyWith(
                                          color: AppColors.textTertiary,
                                        ),
                                      )
                                    : Text(
                                        DateFormat(
                                          'd \'de\' MMMM \'de\' yyyy',
                                          'es',
                                        ).format(_birthDate!),
                                        style: AppTextStyles.body,
                                      ),
                              ),
                              if (_birthDate != null)
                                Text(
                                  '$_age años',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.gold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 44),

                      // ── Guardar ─────────────────────────────
                      ElevatedButton(
                        onPressed: _saving ? null : _saveProfile,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: AppColors.background,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Guardar cambios'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
