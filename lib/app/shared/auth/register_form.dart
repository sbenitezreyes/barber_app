import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_config.dart';
import '../theme/app_theme.dart';
import 'google_auth_service.dart';
import 'navigate_to_home.dart';
import 'terms_screen.dart';

class RegisterForm extends StatefulWidget {
  final bool returnAfterAuth;

  const RegisterForm({super.key, this.returnAfterAuth = false});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _acceptTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveUserProfile(User user, AppType appType) async {
    final role = appType == AppType.client ? 'client' : 'barber';
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': [role],
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final credential = await GoogleAuthService.signInWithGoogle();
      if (credential == null) return;
      if (!context.mounted) return;
      navigateToHome(context, returnAfterAuth: widget.returnAfterAuth);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error con Google: $e')),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar los términos y condiciones')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final appConfig = AppConfig.of(context);
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await credential.user?.updateDisplayName(_nameController.text.trim());
      final user = credential.user;
      if (user != null) await _saveUserProfile(user, appConfig.appType);
      try { await credential.user?.sendEmailVerification(); } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada. Revisa tu correo para verificarla.')),
      );
      navigateToHome(context, returnAfterAuth: widget.returnAfterAuth);
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'email-already-in-use') {
        message = 'Este correo ya está registrado';
      } else if (e.code == 'invalid-email') {
        message = 'Correo inválido';
      } else if (e.code == 'weak-password') {
        message = 'La contraseña es demasiado débil';
      } else {
        message = 'Error: ${e.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              style: GoogleFonts.figtree(fontSize: 14, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresa tu nombre';
                if (v.length < 3) return 'Nombre muy corto';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.figtree(fontSize: 14, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresa tu correo';
                if (!v.contains('@')) return 'Correo no válido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: GoogleFonts.figtree(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Crea una contraseña';
                if (v.length < 6) return 'Mínimo 6 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              style: GoogleFonts.figtree(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Confirmar contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirma tu contraseña';
                if (v != _passwordController.text) return 'Las contraseñas no coinciden';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Términos
            GestureDetector(
              onTap: () => setState(() => _acceptTerms = !_acceptTerms),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: _acceptTerms ? AppColors.gold : Colors.transparent,
                      border: Border.all(
                        color: _acceptTerms ? AppColors.gold : AppColors.borderMedium,
                        width: 1.5,
                      ),
                    ),
                    child: _acceptTerms
                        ? const Icon(Icons.check_rounded, size: 14, color: AppColors.background)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.figtree(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        children: [
                          const TextSpan(text: 'Acepto los '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const TermsScreen()),
                              ),
                              child: Text(
                                'términos y condiciones',
                                style: GoogleFonts.figtree(
                                  fontSize: 13,
                                  color: AppColors.gold,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.gold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Botón crear cuenta
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                      )
                    : Text('Crear cuenta', style: AppTextStyles.button),
              ),
            ),

            const SizedBox(height: 20),

            Row(children: [
              const Expanded(child: Divider(color: AppColors.borderMedium)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('o', style: AppTextStyles.caption),
              ),
              const Expanded(child: Divider(color: AppColors.borderMedium)),
            ]),

            const SizedBox(height: 16),

            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => _signInWithGoogle(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('G', style: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF4285F4))),
                    const SizedBox(width: 10),
                    Text('Registrarme con Google', style: AppTextStyles.button.copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
