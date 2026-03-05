import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_config.dart';
import 'google_auth_service.dart';
import 'navigate_to_home.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final credential = await GoogleAuthService.signInWithGoogle();
      if (credential == null) return; // usuario canceló
      if (!context.mounted) return;
      navigateToHome(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error con Google: $e')),
      );
    }
  }

  /// Agrega el rol de la app actual al usuario si aún no lo tiene.
  Future<void> _ensureRoleExists(User user) async {
    final appConfig = AppConfig.of(context);
    final role = appConfig.isClient ? 'client' : 'barber';

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (doc.exists) {
      final roles = List<String>.from(doc.data()?['role'] ?? []);
      if (!roles.contains(role)) {
        // Agregar el nuevo rol al arreglo existente
        await docRef.update({
          'role': FieldValue.arrayUnion([role]),
        });
      }
    } else {
      // El usuario no tiene perfil en Firestore (registro externo), crearlo
      await docRef.set({
        'email': user.email,
        'name': user.displayName ?? '',
        'role': [role],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Asegurar que el rol de esta app esté en Firestore
      if (credential.user != null) {
        await _ensureRoleExists(credential.user!);
      }

      if (!mounted) return;
      navigateToHome(context);
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = 'Usuario no encontrado';
      } else if (e.code == 'wrong-password') {
        message = 'Contraseña incorrecta';
      } else {
        message = 'Error: ${e.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa tu correo';
                }
                if (!value.contains('@')) {
                  return 'Correo no válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa tu contraseña';
                }
                if (value.length < 6) {
                  return 'Mínimo 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Iniciar sesión'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    'o continúa con',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[400],
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _signInWithGoogle(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.grey[700]!),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
              label: const Text('Continuar con Google'),
            ),
          ],
        ),
      ),
    );
  }
}
