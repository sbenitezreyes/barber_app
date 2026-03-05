import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../barber_profile_sheet.dart';
import '../../../shared/guest_auth_prompt.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  CollectionReference<Map<String, dynamic>> _favCol(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites');
  }

  Future<void> _removeFavorite(String barberUid, String uid) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(barberUid)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final isGuest = user == null || user.isAnonymous;

    if (isGuest || uid == null) {
      return const GuestAuthPrompt(
        title: 'Guarda tus favoritos',
        subtitle: 'Inicia sesión para guardar y ver tus barberos favoritos',
        icon: Icons.star_outline_rounded,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _favCol(uid).orderBy('savedAt', descending: true).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mis favoritos',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Barberos que marcaste como favoritos',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey[400]),
              ),
              const SizedBox(height: 20),

              if (snap.connectionState == ConnectionState.waiting)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (docs.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_outline,
                            size: 60, color: Colors.grey[700]),
                        const SizedBox(height: 14),
                        Text(
                          'Aún no tienes favoritos',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Toca la ★ en el perfil de un barbero para guardarlo',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      return _FavoriteTile(
                        barberUid: doc.id,
                        barberData: data,
                        onRemove: () => _removeFavorite(doc.id, uid),
                        onTap: () => showBarberProfileSheet(
                            context, doc.id, data),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Tile de un barbero favorito ──────────────────────────────────
class _FavoriteTile extends StatelessWidget {
  final String barberUid;
  final Map<String, dynamic> barberData;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _FavoriteTile({
    required this.barberUid,
    required this.barberData,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (barberData['name'] ?? 'Barbero') as String;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF18181C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.grey[800],
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca para ver perfil',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.star_rounded,
                  color: Colors.amber, size: 26),
              tooltip: 'Quitar de favoritos',
            ),
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Ver', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
