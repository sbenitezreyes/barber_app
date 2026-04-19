import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/theme/app_theme.dart';

void showClientProfileSheet(
  BuildContext context, {
  required String clientUid,
  required String clientName,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ClientProfileSheet(clientUid: clientUid, clientName: clientName),
  );
}

// ── Modelo de reseña ────────────────────────────────────────────────
class _BarberReview {
  final String id;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const _BarberReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory _BarberReview.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _BarberReview(
      id: doc.id,
      rating: (d['rating'] as num?)?.toInt() ?? 3,
      comment: d['comment'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// ── Sheet principal ─────────────────────────────────────────────────
class _ClientProfileSheet extends StatefulWidget {
  final String clientUid;
  final String clientName;

  const _ClientProfileSheet({
    required this.clientUid,
    required this.clientName,
  });

  @override
  State<_ClientProfileSheet> createState() => _ClientProfileSheetState();
}

class _ClientProfileSheetState extends State<_ClientProfileSheet> {
  String? _photoUrl;
  DateTime? _memberSince;
  List<Map<String, dynamic>> _history = [];
  List<_BarberReview> _reviews = [];
  bool _loading = true;

  CollectionReference<Map<String, dynamic>> get _reviewsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(widget.clientUid)
      .collection('barberReviews');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final barberUid = FirebaseAuth.instance.currentUser!.uid;

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.clientUid)
          .get();
      final data = userSnap.data() ?? {};

      // Historial de citas completadas con este barbero
      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('barberUid', isEqualTo: barberUid)
          .get();

      final history =
          apptSnap.docs
              .where((doc) {
                final d = doc.data();
                return d['clientUid'] == widget.clientUid &&
                    d['status'] == 'completed';
              })
              .map((doc) {
                final d = doc.data();
                return {
                  'serviceName': d['serviceName'] ?? '',
                  'scheduledAt': (d['scheduledAt'] as Timestamp?)?.toDate(),
                };
              })
              .toList()
            ..sort((a, b) {
              final aDate = a['scheduledAt'] as DateTime?;
              final bDate = b['scheduledAt'] as DateTime?;
              if (aDate == null || bDate == null) return 0;
              return bDate.compareTo(aDate);
            });

      // Reseñas anónimas de barberos sobre este cliente
      final reviewSnap = await _reviewsRef
          .orderBy('createdAt', descending: true)
          .get();
      final reviews = reviewSnap.docs.map(_BarberReview.fromDoc).toList();

      if (mounted) {
        setState(() {
          _photoUrl = (data['photoURL'] ?? data['photoUrl']) as String?;
          _memberSince = (data['createdAt'] as Timestamp?)?.toDate();
          _history = history.take(5).toList();
          _reviews = reviews;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Diálogo para agregar reseña ──────────────────────────────────
  Future<void> _showAddReview() async {
    int selectedRating = 3;
    final commentCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          scrollable: true,
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Reseña anónima', style: AppTextStyles.display(size: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Solo otros barberos podrán ver esta reseña. El cliente no sabrá quién la escribió.',
                style: AppTextStyles.ui(
                  size: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
              // Estrellas
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = i < selectedRating;
                    return GestureDetector(
                      onTap: () => setInner(() => selectedRating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 36,
                          color: filled
                              ? AppColors.gold
                              : AppColors.textTertiary,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _ratingLabel(selectedRating),
                  style: AppTextStyles.ui(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Comentario opcional
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                maxLength: 200,
                style: AppTextStyles.ui(size: 13),
                decoration: InputDecoration(
                  hintText: 'Comentario (opcional)',
                  hintStyle: AppTextStyles.ui(
                    size: 13,
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.gold,
                      width: 1.5,
                    ),
                  ),
                  counterStyle: AppTextStyles.ui(
                    size: 11,
                    color: AppColors.textTertiary,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancelar',
                style: AppTextStyles.ui(
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Publicar',
                style: AppTextStyles.ui(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.background,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    HapticFeedback.mediumImpact();
    try {
      await _reviewsRef.add({
        'rating': selectedRating,
        'comment': commentCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Recargar reseñas
      final snap = await _reviewsRef
          .orderBy('createdAt', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _reviews = snap.docs.map(_BarberReview.fromDoc).toList();
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reseña publicada',
              style: AppTextStyles.ui(size: 13),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al publicar la reseña')),
        );
      }
    }
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1:
        return 'Muy malo';
      case 2:
        return 'Malo';
      case 3:
        return 'Regular';
      case 4:
        return 'Bueno';
      case 5:
        return 'Excelente';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.clientName.isNotEmpty
        ? widget.clientName[0].toUpperCase()
        : 'C';

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Avatar + nombre
                  Center(
                    child: Column(
                      children: [
                        _buildAvatar(initial),
                        const SizedBox(height: 12),
                        Text(
                          widget.clientName,
                          style: AppTextStyles.display(size: 22),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cliente',
                          style: AppTextStyles.ui(
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (_memberSince != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Miembro desde ${DateFormat("MMMM yyyy", 'es').format(_memberSince!)}',
                            style: AppTextStyles.ui(
                              size: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Stat: citas completadas contigo
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${_history.length}',
                          style: AppTextStyles.display(
                            size: 32,
                          ).copyWith(color: AppColors.gold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _history.isEmpty
                              ? 'primera visita'
                              : 'cita${_history.length != 1 ? 's' : ''} completada${_history.length != 1 ? 's' : ''} contigo',
                          style: AppTextStyles.ui(
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Historial reciente
                  if (_history.isNotEmpty) ...[
                    _sectionLabel('HISTORIAL RECIENTE'),
                    const SizedBox(height: 10),
                    ..._history.map((h) {
                      final date = h['scheduledAt'] as DateTime?;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                h['serviceName'] as String,
                                style: AppTextStyles.ui(size: 13),
                              ),
                            ),
                            if (date != null)
                              Text(
                                DateFormat('d MMM yyyy', 'es').format(date),
                                style: AppTextStyles.ui(
                                  size: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 36,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Primera visita',
                            style: AppTextStyles.display(
                              size: 15,
                            ).copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Este cliente no tiene\ncitas completadas contigo',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.ui(
                              size: 12,
                              color: AppColors.textTertiary,
                            ).copyWith(height: 1.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Sección de reseñas de barberos ───────────────
                  Row(
                    children: [
                      Expanded(child: _sectionLabel('RESEÑAS DE BARBEROS')),
                      if (_history.isNotEmpty)
                        TextButton.icon(
                          onPressed: _showAddReview,
                          icon: const Icon(
                            Icons.rate_review_outlined,
                            size: 14,
                          ),
                          label: const Text('Agregar'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.gold,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            textStyle: AppTextStyles.ui(
                              size: 12,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_reviews.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.rate_review_outlined,
                            size: 28,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sin reseñas todavía',
                            style: AppTextStyles.ui(
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sé el primero en dejar\nuna reseña anónima',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.ui(
                              size: 11,
                              color: AppColors.textTertiary,
                            ).copyWith(height: 1.4),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._reviews.map((r) => _ReviewTile(review: r)),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: AppTextStyles.ui(
      size: 10,
      weight: FontWeight.w700,
      color: AppColors.gold,
    ).copyWith(letterSpacing: 1.4),
  );

  Widget _buildAvatar(String initial) {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 44,
        backgroundImage: CachedNetworkImageProvider(_photoUrl!),
      );
    }
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.teal.withValues(alpha: 0.5),
            AppColors.teal.withValues(alpha: 0.2),
          ],
        ),
        border: Border.all(
          color: AppColors.teal.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.display(size: 36).copyWith(color: AppColors.teal),
      ),
    );
  }
}

// ── Tarjeta de reseña individual ────────────────────────────────────
class _ReviewTile extends StatelessWidget {
  final _BarberReview review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Estrellas
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 14,
                    color: i < review.rating
                        ? AppColors.gold
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _ratingLabel(review.rating),
                style: AppTextStyles.ui(
                  size: 11,
                  weight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
              const Spacer(),
              // Badge anónimo + fecha
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 10,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Anónimo  ·  ${DateFormat('d MMM', 'es').format(review.createdAt)}',
                      style: AppTextStyles.ui(
                        size: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: AppTextStyles.ui(size: 13, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1:
        return 'Muy malo';
      case 2:
        return 'Malo';
      case 3:
        return 'Regular';
      case 4:
        return 'Bueno';
      case 5:
        return 'Excelente';
      default:
        return '';
    }
  }
}
