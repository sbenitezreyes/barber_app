import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/splash_screen.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // ── Avatar ──
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[800],
            child: user?.photoURL != null
                ? ClipOval(
                    child: Image.network(
                      user!.photoURL!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.person, size: 50, color: Colors.white54),
          ),
          const SizedBox(height: 14),
          Text(
            user?.displayName ?? 'Cliente',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),

          // ── Opciones ──
          _ProfileTile(
            icon: Icons.person_outline,
            label: 'Editar perfil',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.location_on_outlined,
            label: 'Mis direcciones',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.payment_outlined,
            label: 'Métodos de pago',
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

          // ── Cerrar sesión ──
          _ProfileTile(
            icon: Icons.logout,
            label: 'Cerrar sesión',
            iconColor: Colors.redAccent,
            labelColor: Colors.redAccent,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
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
        trailing: const Icon(
          Icons.chevron_right,
          color: Colors.white38,
          size: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
