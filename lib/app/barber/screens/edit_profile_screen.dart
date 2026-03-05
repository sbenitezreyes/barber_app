import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

// ── Modelo reseña ────────────────────────────────────────────────
class _Review {
  final String clientName;
  final double rating;
  final String comment;
  final DateTime createdAt;

  const _Review({
    required this.clientName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory _Review.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _Review(
      clientName: d['clientName'] ?? 'Cliente',
      rating: (d['rating'] as num?)?.toDouble() ?? 5.0,
      comment: d['comment'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// ── Pantalla editar perfil ───────────────────────────────────────
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _picker = ImagePicker();

  String _name = '';
  String? _photoURL;
  double _rating = 0.0;
  int _ratingCount = 0;
  double _popularity = 0.0;
  List<String> _portfolio = [];
  List<_Review> _reviews = [];
  bool _loadingProfile = true;
  bool _uploadingPhoto = false;
  bool _uploadingPortfolio = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  void _openPhoto(String url, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            _FullscreenPhotoScreen(url: url, heroTag: 'portfolio_$index'),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadReviews();
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
        _rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
        _ratingCount = (d['ratingCount'] as num?)?.toInt() ?? 0;
        _popularity = (d['popularity'] as num?)?.toDouble() ?? 0.0;
        _portfolio = List<String>.from(d['portfolioPhotos'] ?? []);
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadReviews() async {
    try {
      final snap = await _userDoc
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _reviews = snap.docs.map((d) => _Review.fromDoc(d)).toList();
        });
      }
    } catch (_) {}
  }

  Future<List<int>> _compress(XFile picked) async {
    final bytes = await picked.readAsBytes();
    return FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      minWidth: 800,
      minHeight: 800,
    );
  }

  Future<void> _changeProfilePhoto() async {
    final source = await _showSourcePicker();
    if (source == null) return;
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final compressed = await _compress(picked);
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

  Future<void> _addPortfolioPhoto() async {
    if (_portfolio.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Máximo 9 fotos en el portafolio'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final source = await _showSourcePicker();
    if (source == null) return;
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() => _uploadingPortfolio = true);
    try {
      final compressed = await _compress(picked);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref =
          FirebaseStorage.instance.ref('users/$_uid/portfolio/$fileName');
      await ref.putData(
        Uint8List.fromList(compressed),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      final newList = List<String>.from(_portfolio)..add(url);
      await _userDoc.set({'portfolioPhotos': newList}, SetOptions(merge: true));
      if (mounted) setState(() => _portfolio = newList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _uploadingPortfolio = false);
    }
  }

  Future<void> _removePortfolioPhoto(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Eliminar foto'),
        content: const Text('¿Eliminar esta foto del portafolio?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
      final newList = List<String>.from(_portfolio)..remove(url);
      await _userDoc.set({'portfolioPhotos': newList}, SetOptions(merge: true));
      if (mounted) setState(() => _portfolio = newList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Editar nombre'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              hintText: 'Tu nombre', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == _name) return;
    await _userDoc.set({'name': result}, SetOptions(merge: true));
    await FirebaseAuth.instance.currentUser?.updateDisplayName(result);
    if (mounted) setState(() => _name = result);
  }

  Future<ImageSource?> _showSourcePicker() {
    return showModalBottomSheet<ImageSource>(
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
        centerTitle: true,
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Foto + nombre ──────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 55,
                              backgroundColor: Colors.grey[800],
                              backgroundImage: _photoURL != null
                                  ? NetworkImage(_photoURL!)
                                  : null,
                              child: _uploadingPhoto
                                  ? const CircularProgressIndicator()
                                  : _photoURL == null
                                      ? const Icon(Icons.person,
                                          size: 55, color: Colors.white54)
                                      : null,
                            ),
                            GestureDetector(
                              onTap: _changeProfilePhoto,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: const Color(0xFF111217),
                                      width: 2),
                                ),
                                child: const Icon(Icons.camera_alt,
                                    size: 16, color: Colors.black),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _editName,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_name,
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              Icon(Icons.edit,
                                  size: 16, color: Colors.grey[500]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Calificación + Popularidad ─────────────
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 30),
                              const SizedBox(width: 6),
                              Text(_rating.toStringAsFixed(1),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold)),
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text('($_ratingCount)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500])),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Popularidad',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400])),
                                  Text('${(_popularity * 100).toInt()}%',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _popularity,
                                  minHeight: 8,
                                  backgroundColor: Colors.grey[800],
                                  valueColor: AlwaysStoppedAnimation(
                                      theme.colorScheme.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── Portafolio ─────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Portafolio',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${_portfolio.length}/9',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _portfolio.length +
                        (_portfolio.length < 9 ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _portfolio.length) {
                        return GestureDetector(
                          onTap: _uploadingPortfolio
                              ? null
                              : _addPortfolioPhoto,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[700]!),
                            ),
                            child: _uploadingPortfolio
                                ? const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                          Icons
                                              .add_photo_alternate_outlined,
                                          color: Colors.grey[500],
                                          size: 28),
                                      const SizedBox(height: 4),
                                      Text('Agregar',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[500])),
                                    ],
                                  ),
                          ),
                        );
                      }
                      final url = _portfolio[i];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onTap: () => _openPhoto(url, i),
                            child: Hero(
                              tag: 'portfolio_$i',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(url,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, p) =>
                                        p == null
                                            ? child
                                            : Container(
                                                color: Colors.grey[900],
                                                child: const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))),
                                    errorBuilder: (_, __, ___) => Container(
                                        color: Colors.grey[900],
                                        child: const Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.white24))),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removePortfolioPhoto(url),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Reseñas ────────────────────────────────
                  Text('Reseñas y calificaciones',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_reviews.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(Icons.star_border_rounded,
                                size: 48, color: Colors.grey[700]),
                            const SizedBox(height: 8),
                            Text('Aún no tienes reseñas',
                                style:
                                    TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _reviews.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12),
                      itemBuilder: (_, i) =>
                          _ReviewCard(review: _reviews[i]),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

// ── Tarjeta de estadística ───────────────────────────────────────
class _StatCard extends StatelessWidget {
  final Widget child;
  const _StatCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}

// ── Tarjeta de reseña ────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final _Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey[800],
                child: Text(
                  review.clientName.isNotEmpty
                      ? review.clientName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.clientName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      DateFormat('d MMM yyyy', 'es').format(review.createdAt),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating.round()
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 16,
                  );
                }),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment,
                style: TextStyle(color: Colors.grey[300], height: 1.4)),
          ],
        ],
      ),
    );
  }
}

// ── Visor de foto fullscreen ─────────────────────────────────────
class _FullscreenPhotoScreen extends StatelessWidget {
  final String url;
  final String heroTag;

  const _FullscreenPhotoScreen({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Hero(
              tag: heroTag,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, p) => p == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
