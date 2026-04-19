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
import 'package:intl/intl.dart';

import '../../shared/xp_rank.dart';

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
  int _xp = 0;
  List<String> _portfolio = [];
  List<_Review> _reviews = [];
  bool _loadingProfile = true;
  bool _uploadingPhoto = false;
  bool _uploadingPortfolio = false;
  StreamSubscription<DocumentSnapshot>? _statsSub;

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
    _loadReviews();
    // snapshots() emite desde caché local inmediatamente → spinner desaparece
    // sin esperar red. Unifica _loadProfile y las actualizaciones en tiempo real.
    _statsSub = _userDoc.snapshots().listen(
      (snap) {
        if (!mounted) return;
        final d = snap.data() ?? {};
        setState(() {
          _name =
              d['name'] as String? ??
              FirebaseAuth.instance.currentUser?.displayName ??
              'Barbero';
          _photoURL = d['photoURL'] as String?;
          _rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
          _ratingCount = (d['ratingCount'] as num?)?.toInt() ?? 0;
          _xp = (d['xp'] as num?)?.toInt() ?? 0;
          _portfolio = List<String>.from(d['portfolioPhotos'] ?? []);
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
    _statsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    try {
      final snap = await _userDoc
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(10)  // Solo últimas 10 reviews
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
      format: CompressFormat.webp,
    );
  }

  Future<void> _changeProfilePhoto() async {
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
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _addPortfolioPhoto() async {
    if (_portfolio.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Máximo 9 fotos en el portafolio'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final source = await _showSourcePicker();
    if (source == null) return;
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;
    }
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() => _uploadingPortfolio = true);
    try {
      final compressed = await _compress(picked);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.webp';
      final ref = FirebaseStorage.instance.ref(
        'users/$_uid/portfolio/$fileName',
      );
      await ref.putData(
        Uint8List.fromList(compressed),
        SettableMetadata(contentType: 'image/webp'),
      );
      final url = await ref.getDownloadURL();

      final newList = List<String>.from(_portfolio)..add(url);
      await _userDoc.set({'portfolioPhotos': newList}, SetOptions(merge: true));
      if (mounted) setState(() => _portfolio = newList);
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
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
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
            hintText: 'Tu nombre',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil'), centerTitle: true),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                                  ? CachedNetworkImageProvider(_photoURL!)
                                  : null,
                              child: _uploadingPhoto
                                  ? const CircularProgressIndicator()
                                  : _photoURL == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 55,
                                      color: Colors.white54,
                                    )
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
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: Colors.black,
                                ),
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
                              Text(
                                _name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.grey[500],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Calificación + Nivel XP ────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _ratingCount == 0
                                            ? 'N/A'
                                            : _rating.toStringAsFixed(1),
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_ratingCount ${_ratingCount == 1 ? 'reseña' : 'reseñas'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(width: 1, color: Colors.white10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: _LevelCard(xp: _xp),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Portafolio ─────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Portafolio',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_portfolio.length}/9',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
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
                    itemCount:
                        _portfolio.length + (_portfolio.length < 9 ? 1 : 0),
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
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: Colors.grey[500],
                                        size: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Agregar',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500],
                                        ),
                                      ),
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
                                child: CachedNetworkImage(
                                  imageUrl: url,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: Colors.grey[900],
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
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
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Reseñas ────────────────────────────────
                  Text(
                    'Reseñas y calificaciones',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_reviews.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(Icons.star_border_rounded, size: 48, color: Colors.grey[700]),
                            const SizedBox(height: 8),
                            Text('Aún no tienes reseñas', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    ...(_reviews.take(4).map((r) => _ReviewCard(review: r))),
                    if (_reviews.length > 4) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _AllReviewsSheet(reviews: _reviews),
                          ),
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: Text('Ver más (${_reviews.length - 4} más)'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFC9A84C),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.white12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

// ── Tarjeta de nivel XP ──────────────────────────────────────────
class _LevelCard extends StatelessWidget {
  final int xp;
  const _LevelCard({required this.xp});

  @override
  Widget build(BuildContext context) {
    final rank = rankFromXp(xp);
    final rankIndex = rankTable.indexOf(rank);
    final nextRank = rankIndex < rankTable.length - 1
        ? rankTable[rankIndex + 1]
        : null;
    final double progress;
    final String progressLabel;
    if (rank.maxXp == -1) {
      progress = 1.0;
      progressLabel = '¡Rango máximo!';
    } else {
      final range = rank.maxXp - rank.minXp + 1;
      progress = ((xp - rank.minXp) / range).clamp(0.0, 1.0);
      final toNext = nextRank != null ? nextRank.minXp - xp : 0;
      progressLabel = '$xp XP · $toNext para ${nextRank?.name ?? ''}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${rank.minXp}–${rank.maxXp == -1 ? '∞' : rank.maxXp} XP',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            Text(
              rank.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9A84C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation(Color(0xFFC9A84C)),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          progressLabel,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

// ── Tarjeta de reseña ────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final _Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final initial = review.clientName.isNotEmpty
        ? review.clientName[0].toUpperCase()
        : 'C';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[300],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.clientName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      DateFormat('d MMM yyyy', 'es').format(review.createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) => Icon(
                  i < review.rating.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber,
                  size: 14,
                )),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment, style: TextStyle(color: Colors.grey[300], height: 1.4)),
          ],
        ],
      ),
    );
  }
}

// ── Sheet con todas las reseñas ───────────────────────────────────
class _AllReviewsSheet extends StatelessWidget {
  final List<_Review> reviews;
  const _AllReviewsSheet({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.rate_review_rounded, size: 18, color: Color(0xFFC9A84C)),
                  const SizedBox(width: 8),
                  Text(
                    'Todas las reseñas (${reviews.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: reviews.length,
                itemBuilder: (_, i) => _ReviewCard(review: reviews[i]),
              ),
            ),
          ],
        ),
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
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
