import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_config.dart';
import '../theme/app_theme.dart';
import 'cedula_decoder.dart';
import 'cedula_scanner_screen.dart';
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
  // Datos de la cédula escaneada (solo barberos)
  CedulaData? _cedulaData;

  final _formKey = GlobalKey<FormState>();

  // Controllers (nombre solo para cliente; barbero usa _cedulaData.fullName)
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Focus nodes
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _acceptTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ── Escaneo de cédula ─────────────────────────────────────────

  Future<void> _launchScanner(BuildContext context) async {
    final result = await Navigator.push<CedulaData>(
      context,
      MaterialPageRoute(builder: (_) => const CedulaScannerScreen()),
    );
    if (result != null && mounted) {
      setState(() => _cedulaData = result);
    }
  }

  // ── Guardado del perfil en Firestore ──────────────────────────

  Future<void> _saveUserProfile(User user, AppType appType) async {
    final isBarber = appType != AppType.client;
    final data = <String, dynamic>{
      'name': isBarber ? _cedulaData!.fullName : _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim(),
      'role': [isBarber ? 'barber' : 'client'],
      'createdAt': FieldValue.serverTimestamp(),
      'phoneVerified': false,
    };
    if (isBarber && _cedulaData != null) {
      data['documentNumber'] = _cedulaData!.documentNumber;
      data['birthDate'] = _cedulaData!.rawBirthDate;
      data['gender'] = _cedulaData!.gender;
      if (_cedulaData!.bloodType.isNotEmpty) {
        data['bloodType'] = _cedulaData!.bloodType;
      }
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(data, SetOptions(merge: true));
  }

  // ── Google Sign-In (solo clientes) ────────────────────────────

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final credential = await GoogleAuthService.signInWithGoogle();
      if (credential == null) return;
      if (!context.mounted) return;

      if (widget.returnAfterAuth) {
        Navigator.of(context).pop(true);
        return;
      }

      final uid = credential.user?.uid;
      if (uid == null) return;

      if (credential.additionalUserInfo?.isNewUser == true) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': credential.user?.displayName ?? '',
          'email': credential.user?.email ?? '',
          'role': ['client'],
          'createdAt': FieldValue.serverTimestamp(),
          'phoneVerified': false,
        }, SetOptions(merge: true));
        if (!context.mounted) return;
      }

      // Sincronizar usuario después de Google SignIn
      await FirebaseAuth.instance.currentUser?.reload();
      await Future.delayed(const Duration(milliseconds: 300));
      await FirebaseAuth.instance.currentUser?.reload();

      if (!context.mounted) return;
      navigateToHome(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error con Google: $e')));
    }
  }

  // ── Submit ────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar los términos y condiciones'),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final appConfig = AppConfig.of(context);
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final displayName = appConfig.isBarber && _cedulaData != null
          ? _cedulaData!.fullName
          : _nameController.text.trim();

      // Actualizar displayName
      await credential.user?.updateDisplayName(displayName);

      // Reload para sincronizar el displayName
      await FirebaseAuth.instance.currentUser?.reload();

      // Esperar un poco para asegurar que Firebase sincronizó el displayName
      await Future.delayed(const Duration(milliseconds: 300));

      // Usar currentUser (después del reload) en lugar de credential.user (snapshot anterior)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Guardar perfil en Firestore CON el displayName actualizado
        await _saveUserProfile(user, appConfig.appType);

        // Hacer reload nuevamente para estar completamente sincronizado
        await user.reload();
      }

      if (!mounted) return;
      if (widget.returnAfterAuth) {
        Navigator.of(context).pop(true);
        return;
      }

      navigateToHome(context);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isBarber = AppConfig.of(context).isBarber;

    // Barbero sin cédula escaneada → pantalla de escaneo
    if (isBarber && _cedulaData == null) {
      return _buildScanPrompt(context);
    }

    return _buildForm(context);
  }

  // ── Prompt de escaneo (barbero) ───────────────────────────────

  Widget _buildScanPrompt(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.goldSubtle,
              border: Border.all(color: AppColors.borderAccent, width: 1.5),
            ),
            child: const Icon(
              Icons.badge_rounded,
              color: AppColors.gold,
              size: 24,
            ),
          ),
          const SizedBox(height: 20),
          Text('Registro de barbero', style: AppTextStyles.title),
          const SizedBox(height: 8),
          Text(
            'Para registrarte como barbero, primero debes verificar tu '
            'identidad escaneando tu cédula de ciudadanía colombiana.',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.shield_outlined,
                    color: AppColors.gold,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Esto garantiza la seguridad de los clientes que '
                    'nos confían su domicilio.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _launchScanner(context),
              icon: const Icon(Icons.document_scanner_rounded, size: 20),
              label: Text('Escanear mi cédula', style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );
  }

  // ── Formulario ────────────────────────────────────────────────

  Widget _buildForm(BuildContext context) {
    final isBarber = AppConfig.of(context).isBarber;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Campos bloqueados (barbero, desde cédula) ────────
            if (isBarber && _cedulaData != null) ...[
              _LockedField(
                label: 'Nombre completo',
                value: _cedulaData!.fullName,
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 12),
              _LockedField(
                label: 'Número de cédula',
                value: _cedulaData!.documentNumber,
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 12),
              _LockedField(
                label: 'Fecha de nacimiento',
                value: _cedulaData!.formattedBirthDate,
                icon: Icons.calendar_today_outlined,
              ),
              const SizedBox(height: 12),
              _LockedField(
                label: 'Sexo',
                value: _cedulaData!.gender == 'M'
                    ? 'Masculino'
                    : _cedulaData!.gender == 'F'
                    ? 'Femenino'
                    : _cedulaData!.gender,
                icon: Icons.wc_rounded,
              ),
              if (_cedulaData!.bloodType.isNotEmpty) ...[
                const SizedBox(height: 12),
                _LockedField(
                  label: 'Tipo de sangre',
                  value: _cedulaData!.bloodType,
                  icon: Icons.water_drop_outlined,
                ),
              ],
              const SizedBox(height: 12),
            ],

            // ── Nombre (solo clientes) ───────────────────────────
            if (!isBarber) ...[
              TextFormField(
                controller: _nameController,
                style: AppTextStyles.ui(size: 14),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_phoneFocus),
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
            ],

            // ── Teléfono ─────────────────────────────────────────
            TextFormField(
              controller: _phoneController,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_emailFocus),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: AppTextStyles.ui(size: 14),
              decoration: const InputDecoration(
                labelText: 'Número de celular',
                prefixText: '+57 ',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty)
                  return 'Ingresa tu número de celular';
                final digits = v.replaceAll(RegExp(r'\D'), '');
                if (digits.length != 10) return 'Debe tener 10 dígitos';
                if (!digits.startsWith('3')) {
                  return 'Ingresa un número celular válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Correo ───────────────────────────────────────────
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_passwordFocus),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: AppTextStyles.ui(size: 14),
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

            // ── Contraseña ───────────────────────────────────────
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_confirmFocus),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: AppTextStyles.ui(size: 14),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Crea una contraseña';
                if (v.length < 6) return 'Mínimo 6 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Confirmar contraseña ─────────────────────────────
            TextFormField(
              controller: _confirmPasswordController,
              focusNode: _confirmFocus,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: AppTextStyles.ui(size: 14),
              decoration: InputDecoration(
                labelText: 'Confirmar contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirma tu contraseña';
                if (v != _passwordController.text) {
                  return 'Las contraseñas no coinciden';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Términos ─────────────────────────────────────────
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
                        color: _acceptTerms
                            ? AppColors.gold
                            : AppColors.borderMedium,
                        width: 1.5,
                      ),
                    ),
                    child: _acceptTerms
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: AppColors.background,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.ui(
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        children: [
                          const TextSpan(text: 'Acepto los '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ),
                              child: Text(
                                'términos y condiciones',
                                style:
                                    AppTextStyles.ui(
                                      size: 13,
                                      color: AppColors.gold,
                                    ).copyWith(
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

            // ── Botón crear cuenta ───────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : Text('Crear cuenta', style: AppTextStyles.button),
              ),
            ),

            // ── Google (solo clientes) ───────────────────────────
            if (!isBarber) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.borderMedium)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('o', style: AppTextStyles.caption),
                  ),
                  const Expanded(child: Divider(color: AppColors.borderMedium)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _signInWithGoogle(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'G',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4285F4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Registrarme con Google',
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Widget: campo bloqueado (datos de la cédula) ──────────────────

class _LockedField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _LockedField({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.ui(
                    size: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
