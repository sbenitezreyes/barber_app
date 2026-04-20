import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../barber_profile_sheet.dart';
import '../../../shared/guest_auth_prompt.dart';
import '../../../shared/theme/app_theme.dart';

// ── Tab principal ────────────────────────────────────────────────
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  CollectionReference<Map<String, dynamic>> _favCol(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('favorites');

  Future<void> _removeFavorite(String barberUid, String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .doc(barberUid)
          .delete();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data ?? FirebaseAuth.instance.currentUser;
        final uid = user?.uid;
        final isGuest = user == null || user.isAnonymous;

        if (isGuest || uid == null) {
          return const _GuestDemoFavorites();
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _favCol(uid).orderBy('savedAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _ShimmerList();
            }

            final docs = snap.data?.docs ?? [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(count: docs.length),
                Expanded(
                  child: docs.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final doc = docs[i];
                            final data = doc.data() as Map<String, dynamic>;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _FavoriteTile(
                                key: ValueKey(doc.id),
                                index: i,
                                barberUid: doc.id,
                                barberData: data,
                                onRemove: () => _removeFavorite(doc.id, uid),
                                onTap: () => showBarberProfileSheet(
                                  context,
                                  doc.id,
                                  data,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Mis Barberos',
                  style: AppTextStyles.display(size: 26).copyWith(height: 1.1),
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.goldSubtle,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.borderAccent),
                  ),
                  child: Text(
                    '$count',
                    style: AppTextStyles.ui(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.gold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            count == 0
                ? 'Tu colección de confianza'
                : count == 1
                ? '1 barbero de confianza'
                : '$count barberos de confianza',
            style: AppTextStyles.ui(
              size: 13,
              color: AppColors.textTertiary,
            ).copyWith(letterSpacing: 0.2),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.borderAccent, Colors.transparent],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────
class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(
      begin: 0.15,
      end: 0.45,
    ).animate(CurvedAnimation(parent: _glow, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, child) => Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(
                        alpha: _glowAnim.value * 0.6,
                      ),
                      blurRadius: 48,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: child,
              ),
              child: Icon(
                Icons.star_rounded,
                size: 60,
                color: AppColors.gold.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Sin barberos favoritos',
              style: AppTextStyles.display(
                size: 20,
                weight: FontWeight.w600,
              ).copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Explora los perfiles y toca ★ para guardar a tus barberos de confianza',
              style: AppTextStyles.ui(
                size: 13,
                color: AppColors.textTertiary,
              ).copyWith(height: 1.55),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shimmer loading ──────────────────────────────────────────────
class _ShimmerList extends StatefulWidget {
  const _ShimmerList();

  @override
  State<_ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<_ShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _sweep = Tween<double>(
      begin: -1.6,
      end: 1.6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box({double h = 14, double? w, double r = 8}) => AnimatedBuilder(
    animation: _sweep,
    builder: (_, __) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment(_sweep.value - 1, 0),
          end: Alignment(_sweep.value + 1, 0),
          colors: const [
            Color(0xFF16161C),
            Color(0xFF252532),
            Color(0xFF16161C),
          ],
        ),
      ),
    ),
  );

  Widget _card() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: AppDecorations.card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // accent line placeholder
        Container(
          height: 2,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E28),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _box(h: 52, w: 52, r: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(h: 16, w: 150),
                    const SizedBox(height: 7),
                    _box(h: 12, w: 90),
                    const SizedBox(height: 6),
                    _box(h: 11, w: 120),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _box(h: 34, w: 34, r: 8),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: _box(h: 36, r: 100),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _box(h: 28, w: 180),
              const SizedBox(height: 8),
              _box(h: 13, w: 150),
              const SizedBox(height: 16),
              _box(h: 1, r: 0),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [_card(), _card(), _card()]),
          ),
        ),
      ],
    );
  }
}

// ── Fecha relativa ───────────────────────────────────────────────
String _relativeDate(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inDays == 0) return 'Guardado hoy';
  if (diff.inDays == 1) return 'Guardado ayer';
  if (diff.inDays < 7) return 'Guardado hace ${diff.inDays} días';
  final weeks = (diff.inDays / 7).floor();
  if (diff.inDays < 30) {
    return 'Guardado hace $weeks ${weeks == 1 ? 'semana' : 'semanas'}';
  }
  final months = (diff.inDays / 30).floor();
  if (diff.inDays < 365) {
    return 'Guardado hace $months ${months == 1 ? 'mes' : 'meses'}';
  }
  return 'Guardado hace más de un año';
}

// ── Tile de barbero favorito ─────────────────────────────────────
class _FavoriteTile extends StatefulWidget {
  final int index;
  final String barberUid;
  final Map<String, dynamic> barberData;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _FavoriteTile({
    super.key,
    required this.index,
    required this.barberUid,
    required this.barberData,
    required this.onRemove,
    required this.onTap,
  });

  @override
  State<_FavoriteTile> createState() => _FavoriteTileState();
}

class _FavoriteTileState extends State<_FavoriteTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 55 * widget.index), () {
      if (mounted) _enter.forward();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.barberData;
    final name = (data['name'] ?? 'Barbero') as String;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';
    final photoUrl = data['photoURL'] as String?;
    final rating = (data['rating'] as num?)?.toDouble();
    final totalRatings = data['totalRatings'] as int?;
    final savedAt = data['savedAt'] != null
        ? (data['savedAt'] as Timestamp).toDate()
        : null;
    final dateLabel = savedAt != null
        ? _relativeDate(savedAt)
        : 'Barbero favorito';

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Dismissible(
          key: ValueKey(widget.barberUid),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => widget.onRemove(),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_border_outlined,
                  color: AppColors.error,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  'Eliminar',
                  style: AppTextStyles.ui(
                    size: 10,
                    weight: FontWeight.w600,
                    color: AppColors.error,
                  ).copyWith(letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderAccent),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gold top accent line
                  Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.gold,
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        _BarberAvatar(photoUrl: photoUrl, initial: initial),
                        const SizedBox(width: 13),

                        // Nombre + rating + fecha
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: AppTextStyles.display(size: 15),
                              ),
                              if (rating != null && rating > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 13,
                                      color: AppColors.gold,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: AppTextStyles.ui(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: AppColors.gold,
                                      ),
                                    ),
                                    if (totalRatings != null &&
                                        totalRatings > 0) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '($totalRatings)',
                                        style: AppTextStyles.ui(
                                          size: 11,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ] else
                                const SizedBox(height: 4),
                              const SizedBox(height: 4),
                              Text(
                                dateLabel,
                                style: AppTextStyles.ui(
                                  size: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Remove button
                        _RemoveButton(onRemove: widget.onRemove),
                      ],
                    ),
                  ),

                  // Ver perfil — full width
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: widget.onTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.borderMedium),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: AppTextStyles.ui(
                            size: 13,
                            weight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Ver perfil'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Avatar ───────────────────────────────────────────────────────
class _BarberAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initial;

  const _BarberAvatar({required this.photoUrl, required this.initial});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _GoldInitialAvatar(initial: initial),
        ),
      );
    }
    return _GoldInitialAvatar(initial: initial);
  }
}

class _GoldInitialAvatar extends StatelessWidget {
  final String initial;
  const _GoldInitialAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.goldDark, AppColors.gold],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.display(
          size: 22,
        ).copyWith(color: AppColors.background),
      ),
    );
  }
}

// ── Vista demo para invitados ────────────────────────────────────
class _GuestDemoFavorites extends StatelessWidget {
  const _GuestDemoFavorites();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(count: 2),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: 2,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderAccent),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.gold,
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceElevated,
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 14,
                                  width: 130,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 11,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 10,
                                  width: 100,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.bookmark_remove_outlined,
                              size: 20,
                              color: AppColors.textTertiary.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textTertiary,
                            side: const BorderSide(color: AppColors.borderSubtle),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Ver perfil'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const GuestCtaBanner(
          message: 'Inicia sesión para guardar tus barberos favoritos',
        ),
      ],
    );
  }
}

// ── Botón eliminar favorito ──────────────────────────────────────
class _RemoveButton extends StatefulWidget {
  final VoidCallback onRemove;
  const _RemoveButton({required this.onRemove});

  @override
  State<_RemoveButton> createState() => _RemoveButtonState();
}

class _RemoveButtonState extends State<_RemoveButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onRemove();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.error.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.bookmark_remove_outlined,
          size: 20,
          color: _pressed ? AppColors.error : AppColors.textTertiary,
        ),
      ),
    );
  }
}
