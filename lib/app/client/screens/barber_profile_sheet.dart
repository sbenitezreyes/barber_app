import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../shared/xp_rank.dart';
import 'book_appointment_screen.dart';
import 'emergency_contacts_dialog.dart';
import '../../shared/auth/phone_verification_screen.dart';
import '../../shared/guest_auth_prompt.dart';
import '../../shared/theme/app_theme.dart';


//  Modelos
class _Service {
  final String id;
  final String name;
  final double price;
  final int durationMinutes;
  final String description;

  const _Service({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    required this.description,
  });

  factory _Service.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _Service(
      id: doc.id,
      name: d['name'] ?? '',
      price: (d['price'] as num).toDouble(),
      durationMinutes: d['durationMinutes'] ?? 30,
      description: d['description'] ?? '',
    );
  }
}

class _Review {
  final String docId;
  final String clientUid;
  final String clientName;
  final double rating;
  final String comment;
  final DateTime createdAt;

  const _Review({
    required this.docId,
    required this.clientUid,
    required this.clientName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory _Review.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _Review(
      docId: doc.id,
      clientUid: d['clientUid'] as String? ?? '',
      clientName: d['clientName'] as String? ?? 'Cliente',
      rating: (d['rating'] as num?)?.toDouble() ?? 5.0,
      comment: d['comment'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

//  Función pública para mostrar el sheet
void showBarberProfileSheet(
  BuildContext context,
  String barberUid,
  Map<String, dynamic> barberData,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) =>
        _BarberProfileSheet(barberUid: barberUid, barberData: barberData),
  );
}

//  Widget principal
class _BarberProfileSheet extends StatefulWidget {
  final String barberUid;
  final Map<String, dynamic> barberData;

  const _BarberProfileSheet({
    required this.barberUid,
    required this.barberData,
  });

  @override
  State<_BarberProfileSheet> createState() => _BarberProfileSheetState();
}

class _BarberProfileSheetState extends State<_BarberProfileSheet> {
  // Caché estática de reseñas compartida entre todas las instancias del sheet.
  // Se invalida cuando el usuario envía o elimina su reseña.
  static final Map<String, ({List<_Review> reviews, DateTime cachedAt})>
  _reviewsCache = {};
  static const _reviewsCacheTtl = Duration(minutes: 5);

  bool _isFavorite = false;
  bool _isBusy = false;
  List<_Review> _reviews = [];
  bool _loadingReviews = true;
  int _completedAppointments = 0;
  int _myReviewsCount = 0;

  int get _remainingReviews =>
      (_completedAppointments - _myReviewsCount).clamp(0, 99);

  // Distance from client to barber
  double? _distanceKm;
  bool _loadingDistance = true;

  late double _rating;
  late int _ratingCount;
  late int _xp;
  StreamSubscription<DocumentSnapshot>? _barberDocSub;

  String? get _clientUid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> get _barberDoc =>
      FirebaseFirestore.instance.collection('users').doc(widget.barberUid);

  DocumentReference<Map<String, dynamic>>? get _favDoc {
    final uid = _clientUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.barberUid);
  }

  @override
  void initState() {
    super.initState();
    _rating = (widget.barberData['rating'] as num?)?.toDouble() ?? 0.0;
    _ratingCount = (widget.barberData['ratingCount'] as num?)?.toInt() ?? 0;
    _xp = (widget.barberData['xp'] as num?)?.toInt() ?? 0;
    _loadFavorite();
    _loadReviews();
    _loadDistance();
    _checkCompletedAppointment();
    _isBusy = (widget.barberData['isBusy'] as bool?) ?? false;
    _barberDocSub = _barberDoc.snapshots().listen((snap) {
      if (!mounted) return;
      final d = snap.data() ?? {};
      setState(() {
        _xp = (d['xp'] as num?)?.toInt() ?? _xp;
        _rating = (d['rating'] as num?)?.toDouble() ?? _rating;
        _ratingCount = (d['ratingCount'] as num?)?.toInt() ?? _ratingCount;
        _isBusy = (d['isBusy'] as bool?) ?? false;
      });
    });
  }

  @override
  void dispose() {
    _barberDocSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDistance() async {
    try {
      final loc = widget.barberData['location'];
      if (loc == null) {
        if (mounted) setState(() => _loadingDistance = false);
        return;
      }
      final barberLat = (loc['lat'] as num?)?.toDouble();
      final barberLng = (loc['lng'] as num?)?.toDouble();
      if (barberLat == null || barberLng == null) {
        if (mounted) setState(() => _loadingDistance = false);
        return;
      }

      // Check/request location permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) setState(() => _loadingDistance = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );

      // Haversine formula (meters)
      final meters = _haversine(
        pos.latitude,
        pos.longitude,
        barberLat,
        barberLng,
      );
      if (mounted) {
        setState(() {
          _distanceKm = meters / 1000;
          _loadingDistance = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDistance = false);
    }
  }

  /// Returns distance in meters between two lat/lng points.
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(a));
  }


  Future<void> _checkCompletedAppointment() async {
    final uid = _clientUid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: uid)
        .where('barberUid', isEqualTo: widget.barberUid)
        .where('status', whereIn: ['completed', 'missed'])
        .get();
    if (mounted) setState(() => _completedAppointments = snap.docs.length);
  }

  Future<void> _loadFavorite() async {
    if (_favDoc == null) return;
    final snap = await _favDoc!.get();
    if (mounted) setState(() => _isFavorite = snap.exists);
  }

  Future<void> _loadReviews() async {
    // Servir desde caché si está fresca (< 5 min)
    final cached = _reviewsCache[widget.barberUid];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _reviewsCacheTtl) {
      final uid = _clientUid;
      final myCount = uid != null
          ? cached.reviews.where((r) => r.clientUid == uid).length
          : 0;
      if (mounted) {
        setState(() {
          _reviews = cached.reviews;
          _myReviewsCount = myCount;
          _loadingReviews = false;
        });
      }
      return;
    }

    try {
      final snap = await _barberDoc
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();
      final reviews = snap.docs.map((d) => _Review.fromDoc(d)).toList();
      _reviewsCache[widget.barberUid] = (
        reviews: reviews,
        cachedAt: DateTime.now(),
      );
      final uid = _clientUid;
      final myCount = uid != null
          ? reviews.where((r) => r.clientUid == uid).length
          : 0;
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _myReviewsCount = myCount;
          _loadingReviews = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favDoc == null) {
      showGuestAuthSheet(
        context,
        title: 'Guarda tus favoritos',
        subtitle: 'Inicia sesión para guardar barberos favoritos',
      );
      return;
    }
    final newVal = !_isFavorite;
    HapticFeedback.lightImpact();
    setState(() => _isFavorite = newVal);
    try {
      if (newVal) {
        await _favDoc!.set({
          'name': widget.barberData['name'] ?? '',
          'email': widget.barberData['email'] ?? '',
          'photoURL': widget.barberData['photoURL'] ?? '',
          'rating': widget.barberData['rating'] ?? 0,
          'totalRatings': widget.barberData['ratingCount'] ?? 0,
          'savedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _favDoc!.delete();
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !newVal);
    }
  }

  Future<void> _deleteReview(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar reseña'),
        content: const Text('¿Seguro que quieres eliminar tu reseña?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _barberDoc.collection('reviews').doc(docId).delete();
    _reviewsCache.remove(widget.barberUid);

    final allReviews = await _barberDoc.collection('reviews').get();
    final count = allReviews.docs.length;
    final sum = allReviews.docs.fold<double>(
      0,
      (acc, d) => acc + ((d.data()['rating'] as num?)?.toDouble() ?? 0),
    );
    final newRating = count > 0 ? sum / count : 0.0;
    await _barberDoc.update({
      'rating': double.parse(newRating.toStringAsFixed(1)),
      'ratingCount': count,
    });

    final barberSnap = await _barberDoc.get();
    final d = barberSnap.data() ?? {};
    if (mounted) {
      setState(() {
        _myReviewsCount = (_myReviewsCount - 1).clamp(0, 99);
        _rating = (d['rating'] as num?)?.toDouble() ?? _rating;
        _ratingCount = (d['ratingCount'] as num?)?.toInt() ?? _ratingCount;
      });
    }
    await _loadReviews();
  }

  Future<void> _showAddReviewDialog() async {
    if (_clientUid == null) {
      showGuestAuthSheet(
        context,
        title: 'Deja tu reseña',
        subtitle: 'Inicia sesión para calificar a este barbero',
      );
      return;
    }
    int selectedStars = 5;
    final commentCtrl = TextEditingController();
    bool submitting = false;
    // Capturar el ScaffoldMessenger antes de abrir el diálogo
    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          scrollable: true,
          title: const Text('Agregar reseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedStars = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        i < selectedStars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Colors.amber,
                        size: 36,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                maxLength: 200,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Escribe tu comentario (opcional)',
                  hintStyle: AppTextStyles.ui(
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: AppTextStyles.caption,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      try {
                        await _submitReview(
                          stars: selectedStars,
                          comment: commentCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        setDialogState(() => submitting = false);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview({
    required int stars,
    required String comment,
  }) async {
    final uid = _clientUid;
    if (uid == null) return;
    HapticFeedback.mediumImpact();
    _reviewsCache.remove(widget.barberUid);
    final clientName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'Cliente';
    await _barberDoc.collection('reviews').add({
      'rating': stars.toDouble(),
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
      'clientName': clientName,
      'clientUid': uid,
    });

    final allReviews = await _barberDoc.collection('reviews').get();
    final count = allReviews.docs.length;
    final sum = allReviews.docs.fold<double>(
      0,
      (acc, d) => acc + ((d.data()['rating'] as num?)?.toDouble() ?? 0),
    );
    final newRating = count > 0 ? sum / count : 0.0;

    await _barberDoc.update({
      'rating': double.parse(newRating.toStringAsFixed(1)),
      'ratingCount': count,
    });

    await _loadReviews();
    final barberSnap = await _barberDoc.get();
    final d = barberSnap.data() ?? {};
    if (mounted) {
      setState(() {
        _rating = (d['rating'] as num?)?.toDouble() ?? _rating;
        _ratingCount = (d['ratingCount'] as num?)?.toInt() ?? _ratingCount;
        _myReviewsCount = _myReviewsCount + 1;
      });
    }
  }

  void _openPhoto(String url, String tag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullscreenPhoto(url: url, heroTag: tag),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.barberData['name'] ?? 'Barbero';
    final photoURL = widget.barberData['photoURL'] as String?;
    final portfolio =
        (widget.barberData['portfolioPhotos'] as List?)?.cast<String>() ?? [];

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      //  Foto + nombre + favorito
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: AppColors.surfaceElevated,
                              backgroundImage:
                                  (photoURL != null && photoURL.isNotEmpty)
                                  ? CachedNetworkImageProvider(photoURL)
                                  : null,
                              child: (photoURL == null || photoURL.isEmpty)
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'B',
                                      style: AppTextStyles.display(size: 38),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: AppTextStyles.headline,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _toggleFavorite,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                          scale: anim,
                                          child: child,
                                        ),
                                    child: Icon(
                                      _isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      key: ValueKey(_isFavorite),
                                      color: _isFavorite
                                          ? Colors.amber
                                          : Colors.white38,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Builder(
                              builder: (context) {
                                final isBusy = _isBusy;
                                final color = isBusy
                                    ? AppColors.error
                                    : theme.colorScheme.primary;
                                final label = isBusy
                                    ? 'En cita ahora'
                                    : 'Disponible ahora';
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.circle, size: 10, color: color),
                                    const SizedBox(width: 6),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            // ── Distancia al barbero ──
                            _loadingDistance
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white38,
                                    ),
                                  )
                                : _distanceKm == null
                                ? const SizedBox.shrink()
                                : _DistanceChips(km: _distanceKm!),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      //  Estadísticas
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_ratingCount ${_ratingCount == 1 ? 'reseña' : 'reseñas'}',
                                      style: AppTextStyles.label,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                color: AppColors.borderSubtle,
                              ),
                              Expanded(child: _LevelStatColumn(xp: _xp)),
                            ],
                          ),
                        ),
                      ),

                      //  Portafolio
                      if (portfolio.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('Portafolio', style: AppTextStyles.subtitle),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                          itemCount: portfolio.length,
                          itemBuilder: (_, i) {
                            final url = portfolio[i];
                            return GestureDetector(
                              onTap: () =>
                                  _openPhoto(url, 'portfolio_client_$i'),
                              child: Hero(
                                tag: 'portfolio_client_$i',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: AppColors.surface,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: AppColors.surface,
                                      child: const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.borderMedium,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 24),

                      //  Servicios
                      Text('Servicios', style: AppTextStyles.subtitle),
                      const SizedBox(height: 10),

                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.barberUid)
                            .collection('services')
                            .orderBy('name')
                            .get(),
                        builder: (ctx, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const _ServicesSkeleton();
                          }
                          if (!snap.hasData || snap.data!.docs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Este barbero aún no tiene servicios publicados.',
                                style: AppTextStyles.caption,
                              ),
                            );
                          }
                          final services = snap.data!.docs
                              .map((d) => _Service.fromDoc(d))
                              .toList();
                          return Column(
                            children: services
                                .map((s) => _ServiceTile(service: s))
                                .toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      //  Reseñas
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Reseñas', style: AppTextStyles.subtitle),
                          if (_remainingReviews > 0)
                            TextButton.icon(
                              onPressed: _showAddReviewDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: Text(
                                _remainingReviews == 1
                                    ? 'Agregar'
                                    : 'Agregar ($_remainingReviews)',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.primary,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_loadingReviews)
                        const _ReviewsSkeleton()
                      else if (_reviews.isEmpty)
                        const _EmptyReviews()
                      else ...[
                        ..._reviews.take(4).toList().asMap().entries.map(
                          (e) => _FadeSlideIn(
                            delay: Duration(milliseconds: e.key * 60),
                            child: _ReviewCard(
                              review: e.value,
                              isOwn: e.value.clientUid == _clientUid,
                              onDelete: () => _deleteReview(e.value.docId),
                            ),
                          ),
                        ),
                        if (_reviews.length > 4) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => _AllReviewsSheet(
                                  reviews: _reviews,
                                  clientUid: _clientUid,
                                  onDelete: _deleteReview,
                                ),
                              ),
                              icon: const Icon(Icons.expand_more, size: 18),
                              label: Text('Ver más (${_reviews.length - 4} más)'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.gold,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(color: AppColors.borderSubtle),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 24),

                      //  Botón solicitar cita
                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.barberUid)
                            .collection('services')
                            .get(),
                        builder: (ctx, snap) {
                          if (!snap.hasData || snap.data!.docs.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final services = snap.data!.docs
                              .map((d) => _Service.fromDoc(d))
                              .toList();
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                HapticFeedback.lightImpact();

                                final user =
                                    FirebaseAuth.instance.currentUser;
                                final isGuest =
                                    user == null || user.isAnonymous;

                                // Solo usuarios registrados pasan por verificación de teléfono y contactos
                                if (!isGuest) {
                                  // 1. Verificar celular
                                  final userDoc =
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(user.uid)
                                          .get();
                                  if (!context.mounted) return;
                                  final phoneVerified =
                                      userDoc.data()?['phoneVerified']
                                          as bool? ??
                                      false;
                                  if (!phoneVerified) {
                                    final phone =
                                        userDoc.data()?['phone']
                                            as String? ??
                                        '';
                                    if (phone.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Agrega tu número de celular en tu perfil para reservar',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PhoneVerificationScreen(
                                          phoneNumber: phone,
                                          returnAfterVerification: true,
                                        ),
                                      ),
                                    );
                                    if (!context.mounted) return;
                                    final updated =
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(user.uid)
                                            .get();
                                    if (!context.mounted) return;
                                    final nowVerified =
                                        updated.data()?['phoneVerified']
                                            as bool? ??
                                        false;
                                    if (!nowVerified) return;
                                  }

                                  // 2. Verificar contactos de emergencia
                                  final canProceed =
                                      await EmergencyContactsDialog.checkAndPrompt(
                                        context,
                                      );
                                  if (!canProceed || !context.mounted) return;
                                }
                                Navigator.pop(context);
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) =>
                                        BookAppointmentScreen(
                                          barberUid: widget.barberUid,
                                          barberName: name,
                                          services: services
                                              .map(
                                                (s) => BookService(
                                                  id: s.id,
                                                  name: s.name,
                                                  price: s.price,
                                                  durationMinutes:
                                                      s.durationMinutes,
                                                  description: s.description,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                    transitionsBuilder: (_, anim, __, child) =>
                                        SlideTransition(
                                          position:
                                              Tween(
                                                    begin: const Offset(
                                                      0.0,
                                                      1.0,
                                                    ),
                                                    end: Offset.zero,
                                                  )
                                                  .chain(
                                                    CurveTween(
                                                      curve: Curves.easeOut,
                                                    ),
                                                  )
                                                  .animate(anim),
                                          child: child,
                                        ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Solicitar cita',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//  Tile de servicio
class _ServiceTile extends StatelessWidget {
  final _Service service;
  const _ServiceTile({required this.service});

  String _formatPrice(double p) {
    return '\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.content_cut,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (service.description.isNotEmpty)
                  Text(
                    service.description,
                    style: AppTextStyles.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPrice(service.price),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${service.durationMinutes} min',
                style: AppTextStyles.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

//  Card de reseña
class _ReviewCard extends StatelessWidget {
  final _Review review;
  final bool isOwn;
  final VoidCallback? onDelete;
  const _ReviewCard({required this.review, this.isOwn = false, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final displayName = isOwn ? '${review.clientName} (tú)' : 'Anónimo';
    final initial = isOwn && review.clientName.isNotEmpty
        ? review.clientName[0].toUpperCase()
        : 'A';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOwn ? AppColors.surfaceInput : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOwn ? AppColors.borderAccent : AppColors.borderSubtle,
        ),
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
                  color: isOwn
                      ? AppColors.goldSubtle
                      : Colors.teal.withValues(alpha: 0.15),
                  border: Border.all(
                    color: isOwn
                        ? AppColors.borderAccent
                        : Colors.teal.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isOwn ? AppColors.gold : Colors.teal[300],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: AppTextStyles.ui(
                        size: 13,
                        weight: FontWeight.w600,
                        color: isOwn ? AppColors.gold : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      DateFormat('d MMM yyyy', 'es').format(review.createdAt),
                      style: AppTextStyles.label,
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 14,
                  );
                }),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isOwn ? onDelete : null,
                child: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: isOwn ? Colors.redAccent : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: AppTextStyles.body.copyWith(height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sheet con todas las reseñas ───────────────────────────────────
class _AllReviewsSheet extends StatefulWidget {
  final List<_Review> reviews;
  final String? clientUid;
  final Future<void> Function(String docId) onDelete;

  const _AllReviewsSheet({
    required this.reviews,
    required this.clientUid,
    required this.onDelete,
  });

  @override
  State<_AllReviewsSheet> createState() => _AllReviewsSheetState();
}

class _AllReviewsSheetState extends State<_AllReviewsSheet> {
  late List<_Review> _localReviews;

  @override
  void initState() {
    super.initState();
    _localReviews = List.from(widget.reviews);
  }

  Future<void> _handleDelete(String docId) async {
    await widget.onDelete(docId);
    if (mounted) {
      setState(() => _localReviews.removeWhere((r) => r.docId == docId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
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
                  gradient: const LinearGradient(
                    colors: [AppColors.goldDark, AppColors.gold, AppColors.goldDark],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.rate_review_rounded, size: 18, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Text(
                    'Todas las reseñas (${_localReviews.length})',
                    style: AppTextStyles.ui(size: 16, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.borderSubtle, height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: _localReviews.length,
                itemBuilder: (_, i) => _ReviewCard(
                  review: _localReviews[i],
                  isOwn: _localReviews[i].clientUid == widget.clientUid,
                  onDelete: () => _handleDelete(_localReviews[i].docId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animación de entrada: fade + slide para items de lista ──────
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FadeSlideIn({required this.child, required this.delay});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ── Skeleton de servicios ───────────────────────────────────────
class _ServicesSkeleton extends StatefulWidget {
  const _ServicesSkeleton();

  @override
  State<_ServicesSkeleton> createState() => _ServicesSkeletonState();
}

class _ServicesSkeletonState extends State<_ServicesSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final opacity = 0.28 + (_ctrl.value * 0.32);
        return Opacity(
          opacity: opacity,
          child: Column(
            children: List.generate(
              3,
              (_) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 100,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 60,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Columna de nivel XP (stats card) ────────────────────────────
class _LevelStatColumn extends StatelessWidget {
  final int xp;
  const _LevelStatColumn({required this.xp});

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${rank.minXp}–${rank.maxXp == -1 ? '∞' : rank.maxXp} XP',
                style: AppTextStyles.label.copyWith(fontSize: 10),
              ),
              Text(
                rank.name,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.surfaceInput,
              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
            ),
          ),
          const SizedBox(height: 4),
          Text(progressLabel, style: AppTextStyles.label.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

// ── Skeleton de reseñas ─────────────────────────────────────────
class _ReviewsSkeleton extends StatefulWidget {
  const _ReviewsSkeleton();

  @override
  State<_ReviewsSkeleton> createState() => _ReviewsSkeletonState();
}

class _ReviewsSkeletonState extends State<_ReviewsSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final opacity = 0.28 + (_ctrl.value * 0.32);
        return Opacity(
          opacity: opacity,
          child: Column(
            children: List.generate(
              2,
              (_) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceElevated,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 90,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 150,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Empty state animado para reseñas ────────────────────────────
class _EmptyReviews extends StatefulWidget {
  const _EmptyReviews();

  @override
  State<_EmptyReviews> createState() => _EmptyReviewsState();
}

class _EmptyReviewsState extends State<_EmptyReviews>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceElevated,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: const Icon(
                  Icons.star_outline_rounded,
                  size: 22,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no hay reseñas. ¡Sé el primero!',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

//  Chips de distancia/tiempo al barbero
class _DistanceChips extends StatelessWidget {
  final double km;
  const _DistanceChips({required this.km});

  @override
  Widget build(BuildContext context) {
    // Caminando: ~5 km/h = 83 m/min
    final walkMin = (km * 1000 / 83).round();
    // Moto: ~40 km/h urbano = 667 m/min
    final motoMin = (km * 1000 / 667).round();

    final distLabel = km < 1
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(1)} km';

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        _Chip(icon: Icons.location_on, label: distLabel, color: Colors.white70),
        _Chip(
          icon: Icons.directions_walk,
          label: walkMin < 1 ? '< 1 min' : '~$walkMin min',
          color: Colors.white70,
        ),
        _Chip(
          icon: Icons.two_wheeler,
          label: motoMin < 1 ? '< 1 min' : '~$motoMin min',
          color: Colors.white70,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

//  Visor fullscreen
class _FullscreenPhoto extends StatelessWidget {
  final String url;
  final String heroTag;
  const _FullscreenPhoto({required this.url, required this.heroTag});

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
