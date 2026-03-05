import 'package:flutter/material.dart';

import 'auth/auth_screen.dart';

/// Widget inline que muestra un mensaje para invitar al guest a iniciar sesión.
class GuestAuthPrompt extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const GuestAuthPrompt({
    super.key,
    this.title = 'Inicia sesión',
    this.subtitle = 'Crea una cuenta o inicia sesión para continuar',
    this.icon = Icons.lock_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AuthScreen()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Iniciar sesión',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AuthScreen()),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Crear cuenta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra [GuestAuthPrompt] como modal bottom sheet.
void showGuestAuthSheet(
  BuildContext context, {
  String title = 'Inicia sesión',
  String subtitle = 'Crea una cuenta o inicia sesión para continuar',
  IconData icon = Icons.lock_outline_rounded,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AuthScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Iniciar sesión',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AuthScreen()));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side:
                    BorderSide(color: Theme.of(context).colorScheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Crear cuenta'),
            ),
          ),
        ],
      ),
    ),
  );
}
