import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import 'navigate_to_home.dart';

class PhoneVerificationScreen extends StatefulWidget {
  /// Número de teléfono sin código de país (10 dígitos colombianos).
  final String phoneNumber;

  /// Si es true, hace pop al terminar en vez de ir al home.
  /// Útil cuando se abre desde un flujo intermedio (ej: antes de reservar).
  final bool returnAfterVerification;

  const PhoneVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.returnAfterVerification = false,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

enum _VerifState { sending, waitingCode, verifying }

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  _VerifState _state = _VerifState.sending;
  String? _verificationId;
  String? _error;

  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  bool _canResend = false;
  int _resendCooldown = 60;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ── Cooldown para reenvío ─────────────────────────────────────

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  // ── Envío del OTP ─────────────────────────────────────────────

  Future<void> _sendOtp() async {
    setState(() {
      _state = _VerifState.sending;
      _error = null;
      _codeController.clear();
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+57${widget.phoneNumber}',
      verificationCompleted: (credential) async {
        // Auto-verificación en algunos Android (sin que el usuario escriba el código)
        if (mounted) await _linkAndProceed(credential);
      },
      verificationFailed: (e) {
        if (!mounted) return;
        setState(() {
          _error = _mapError(e.code);
          _state = _VerifState.waitingCode;
        });
      },
      codeSent: (verificationId, _) {
        if (!mounted) return;
        _verificationId = verificationId;
        setState(() => _state = _VerifState.waitingCode);
        _startCooldown();
        _codeFocus.requestFocus();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // ── Verificación del código ingresado ─────────────────────────

  Future<void> _verifyOtp() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || _verificationId == null) return;

    setState(() {
      _state = _VerifState.verifying;
      _error = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _linkAndProceed(credential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _VerifState.waitingCode;
        _error = _mapError(e.code);
      });
    }
  }

  // ── Vincular credencial y navegar al home ─────────────────────

  Future<void> _linkAndProceed(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        // El número ya está vinculado a OTRA cuenta
        if (!mounted) return;
        setState(() {
          _state = _VerifState.waitingCode;
          _error = 'Este número ya está registrado con otra cuenta.';
        });
        return;
      }
      // 'provider-already-linked': ya vinculado a esta misma cuenta → continuar
      if (e.code != 'provider-already-linked') {
        if (!mounted) return;
        setState(() {
          _state = _VerifState.waitingCode;
          _error = _mapError(e.code);
        });
        return;
      }
    }

    // Marcar teléfono como verificado en Firestore
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'phoneVerified': true,
    });

    if (!mounted) return;
    if (widget.returnAfterVerification) {
      Navigator.of(context).pop(true);
    } else {
      navigateToHome(context);
    }
  }

  // ── Mapeo de errores ──────────────────────────────────────────

  String _mapError(String code) {
    switch (code) {
      case 'invalid-verification-code':
        return 'Código incorrecto. Verifica e intenta de nuevo.';
      case 'invalid-phone-number':
        return 'Número de teléfono inválido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos.';
      case 'credential-already-in-use':
        return 'Este número ya está registrado con otra cuenta.';
      case 'session-expired':
        return 'El código expiró. Reenvía el código.';
      default:
        return 'Error de verificación. Inténtalo de nuevo.';
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.returnAfterVerification,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ícono
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.goldSubtle,
                    border: Border.all(
                      color: AppColors.borderAccent,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: AppColors.gold,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 24),

                Text('Verifica tu celular', style: AppTextStyles.headline),
                const SizedBox(height: 10),

                Text(
                  _state == _VerifState.sending
                      ? 'Enviando código al +57 ${widget.phoneNumber}…'
                      : 'Enviamos un código de 6 dígitos al\n+57 ${widget.phoneNumber}',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                // Estado: enviando
                if (_state == _VerifState.sending)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Enviando código…',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Estado: ingresando / verificando código
                if (_state != _VerifState.sending) ...[
                  TextFormField(
                    controller: _codeController,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.ui(
                      size: 26,
                      weight: FontWeight.w700,
                    ).copyWith(letterSpacing: 10),
                    enabled: _state == _VerifState.waitingCode,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '— — — — — —',
                      hintStyle: AppTextStyles.ui(
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    onChanged: (v) {
                      if (_error != null) setState(() => _error = null);
                      if (v.length == 6) _verifyOtp();
                    },
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 40),

                // Botones (solo visibles cuando no se está enviando)
                if (_state != _VerifState.sending) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _state == _VerifState.waitingCode
                          ? _verifyOtp
                          : null,
                      child: _state == _VerifState.verifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.background,
                              ),
                            )
                          : Text('Verificar', style: AppTextStyles.button),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _canResend ? _sendOtp : null,
                      child: Text(
                        _canResend
                            ? 'Reenviar código'
                            : 'Reenviar en ${_resendCooldown}s',
                        style: AppTextStyles.button.copyWith(
                          color: _canResend
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
