import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'book_appointment_screen.dart';
import '../../shared/guest_auth_prompt.dart';

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
  final double rating;
  final String comment;
  final DateTime createdAt;

  const _Review({
    required this.docId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory _Review.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _Review(
      docId: doc.id,
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
    builder: (_) => _BarberProfileSheet(
      barberUid: barberUid,
      barberData: barberData,
    ),
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
  bool _isFavorite = false;
  List<_Review> _reviews = [];
  bool _loadingReviews = true;
  bool _alreadyReviewed = false;

  // Distance from client to barber
  double? _distanceKm;
  bool _loadingDistance = true;

  late double _rating;
  late int _ratingCount;
  late double _popularity;

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
    _popularity = (widget.barberData['popularity'] as num?)?.toDouble() ?? 0.0;
    _loadFavorite();
    _loadReviews();
    _loadDistance();
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
          pos.latitude, pos.longitude, barberLat, barberLng);
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
  double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(a));
  }

  Future<void> _loadFavorite() async {
    if (_favDoc == null) return;
    final snap = await _favDoc!.get();
    if (mounted) setState(() => _isFavorite = snap.exists);
  }

  Future<void> _loadReviews() async {
    try {
      final snap = await _barberDoc
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();
      final reviews = snap.docs.map((d) => _Review.fromDoc(d)).toList();
      // El docId es el clientUid → permite verificar duplicado sin exponer identidad
      final uid = _clientUid;
      final already = uid != null ? snap.docs.any((d) => d.id == uid) : false;
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _alreadyReviewed = already;
          _loadingReviews = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favDoc == null) {
      showGuestAuthSheet(context,
          title: 'Guarda tus favoritos',
          subtitle: 'Inicia sesión para guardar barberos favoritos');
      return;
    }
    final newVal = !_isFavorite;
    setState(() => _isFavorite = newVal);
    try {
      if (newVal) {
        await _favDoc!.set({
          'name': widget.barberData['name'] ?? '',
          'email': widget.barberData['email'] ?? '',
          'savedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _favDoc!.delete();
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !newVal);
    }
  }

  Future<void> _deleteReview() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar reseña',
            style: TextStyle(color: Colors.white)),
        content: const Text('¿Seguro que quieres eliminar tu reseña?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text('Cancelar', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final uid = _clientUid;
    if (uid == null) return;
    await _barberDoc.collection('reviews').doc(uid).delete();

    // Recalcular promedio sin la reseña eliminada
    final allReviews = await _barberDoc.collection('reviews').get();
    final count = allReviews.docs.length;
    final sum = allReviews.docs.fold<double>(
        0, (acc, d) => acc + ((d.data()['rating'] as num?)?.toDouble() ?? 0));
    final newRating = count > 0 ? sum / count : 0.0;
    await _barberDoc.update({
      'rating': double.parse(newRating.toStringAsFixed(1)),
      'ratingCount': count,
    });

    final barberSnap = await _barberDoc.get();
    final d = barberSnap.data() ?? {};
    if (mounted) {
      setState(() {
        _alreadyReviewed = false;
        _rating = (d['rating'] as num?)?.toDouble() ?? _rating;
        _ratingCount = (d['ratingCount'] as num?)?.toInt() ?? _ratingCount;
      });
    }
    await _loadReviews();
  }

  Future<void> _showAddReviewDialog() async {
    if (_clientUid == null) {
      showGuestAuthSheet(context,
          title: 'Deja tu reseña',
          subtitle: 'Inicia sesión para calificar a este barbero');
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
          backgroundColor: const Color(0xFF18181C),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Agregar reseña',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedStars = i + 1),
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
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Escribe tu comentario (opcional)',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF0F0F14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle:
                      TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  submitting ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: TextStyle(color: Colors.grey[500])),
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
                        messenger.showSnackBar(SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.redAccent,
                        ));
                        setDialogState(() => submitting = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Publicar',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview(
      {required int stars, required String comment}) async {
    // 1. Escribir la reseña (docId = clientUid → impide duplicados)
    final uid = _clientUid;
    if (uid == null) return;
    final reviewRef = _barberDoc.collection('reviews').doc(uid);
    await reviewRef.set({
      'rating': stars.toDouble(),
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Recalcular el promedio leyendo todas las reseñas
    final allReviews =
        await _barberDoc.collection('reviews').get();
    final count = allReviews.docs.length;
    final sum = allReviews.docs.fold<double>(
        0, (acc, d) => acc + ((d.data()['rating'] as num?)?.toDouble() ?? 0));
    final newRating = count > 0 ? sum / count : 0.0;

    // 3. Actualizar rating en el doc del barbero (requiere regla permisiva)
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
        _ratingCount =
            (d['ratingCount'] as num?)?.toInt() ?? _ratingCount;
        _alreadyReviewed = true;
      });
    }
  }

  void _openPhoto(String url, String tag) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          _FullscreenPhoto(url: url, heroTag: tag),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.barberData['name'] ?? 'Barbero';
    final photoURL = widget.barberData['photoURL'] as String?;
    final portfolio =
        (widget.barberData['portfolioPhotos'] as List?)
                ?.cast<String>() ??
            [];

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
              color: Color(0xFF1A1A2E),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
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
                    padding:
                        const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      //  Foto + nombre + favorito 
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.grey[800],
                              backgroundImage: (photoURL != null &&
                                      photoURL.isNotEmpty)
                                  ? NetworkImage(photoURL)
                                  : null,
                              child: (photoURL == null ||
                                      photoURL.isEmpty)
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'B',
                                      style: const TextStyle(
                                        fontSize: 38,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    )),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _toggleFavorite,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(
                                        milliseconds: 250),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                            scale: anim, child: child),
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
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(Icons.circle,
                                    size: 10,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text('Disponible ahora',
                                    style: TextStyle(
                                        color:
                                            theme.colorScheme.primary,
                                        fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // ── Distancia al barbero ──
                            _loadingDistance
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Colors.white38))
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
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18181C),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          color: Colors.amber, size: 20),
                                      const SizedBox(width: 4),
                                      Text(
                                        _ratingCount == 0
                                            ? 'N/A'
                                            : _rating
                                                .toStringAsFixed(1),
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
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                                width: 1,
                                height: 40,
                                color: Colors.white12),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    '${(_popularity * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _popularity,
                                      backgroundColor:
                                          Colors.grey[800],
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              theme.colorScheme
                                                  .primary),
                                      minHeight: 6,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Popularidad',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      //  Portafolio 
                      if (portfolio.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('Portafolio',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
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
                              onTap: () => _openPhoto(
                                  url, 'portfolio_client_$i'),
                              child: Hero(
                                tag: 'portfolio_client_$i',
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  child: Image.network(url,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (_, child, p) =>
                                          p == null
                                              ? child
                                              : Container(
                                                  color:
                                                      Colors.grey[900],
                                                  child: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth:
                                                                  2))),
                                      errorBuilder:
                                          (_, __, ___) => Container(
                                            color: Colors.grey[900],
                                            child: const Icon(
                                                Icons
                                                    .broken_image_outlined,
                                                color: Colors.white24),
                                          )),
                                ),
                              ),
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 24),

                      //  Servicios 
                      const Text('Servicios',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),

                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.barberUid)
                            .collection('services')
                            .orderBy('name')
                            .get(),
                        builder: (ctx, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          if (!snap.hasData ||
                              snap.data!.docs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              child: Text(
                                'Este barbero aún no tiene servicios publicados.',
                                style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 13),
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
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Reseñas',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          if (!_alreadyReviewed)
                            TextButton.icon(
                              onPressed: _showAddReviewDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Agregar'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    theme.colorScheme.primary,
                                padding: EdgeInsets.zero,
                              ),
                            )
                          else
                            Text('Ya reseñaste',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600])),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_loadingReviews)
                        const Center(
                            child: CircularProgressIndicator())
                      else if (_reviews.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Aún no hay reseñas. ¡Sé el primero!',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13),
                          ),
                        )
                      else
                        ..._reviews.map((r) => _ReviewCard(
                              review: r,
                              isOwn: r.docId == (_clientUid ?? '\x00'),
                              onDelete: _deleteReview,
                            )),

                      const SizedBox(height: 24),

                      //  Botón solicitar cita 
                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.barberUid)
                            .collection('services')
                            .get(),
                        builder: (ctx, snap) {
                          if (!snap.hasData ||
                              snap.data!.docs.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final services = snap.data!.docs
                              .map((d) => _Service.fromDoc(d))
                              .toList();
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        BookAppointmentScreen(
                                      barberUid: widget.barberUid,
                                      barberName: name,
                                      services: services
                                          .map((s) => BookService(
                                                id: s.id,
                                                name: s.name,
                                                price: s.price,
                                                durationMinutes:
                                                    s.durationMinutes,
                                                description:
                                                    s.description,
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Solicitar cita',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
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
    return '\$${p.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        )}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.content_cut,
              size: 18, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
                if (service.description.isNotEmpty)
                  Text(service.description,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatPrice(service.price),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
              Text('${service.durationMinutes} min',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[500])),
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
  const _ReviewCard(
      {required this.review, this.isOwn = false, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOwn
            ? const Color(0xFF1E2530)
            : const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    isOwn ? const Color(0xFF00BCD4).withValues(alpha: 0.2) : Colors.grey[850],
                child: Icon(
                  isOwn ? Icons.person : Icons.person_outline,
                  size: 18,
                  color: isOwn
                      ? const Color(0xFF00BCD4)
                      : Colors.white54,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isOwn ? 'Tu reseña' : 'Anónimo',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          isOwn ? const Color(0xFF00BCD4) : Colors.grey[400]),
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
              if (isOwn) ...[  
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                ),
              ],
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment,
                style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 13,
                    height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text(
            '${review.createdAt.day}/${review.createdAt.month}/${review.createdAt.year}',
            style:
                TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
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

    final distLabel =
        km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        _Chip(
          icon: Icons.location_on,
          label: distLabel,
          color: Colors.white70,
        ),
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
              child: Image.network(url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white)),
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64)),
            ),
          ),
        ),
      ),
    );
  }
}
