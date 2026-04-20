import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../client/screens/welcome_dialog.dart';

/// Servicio compartido de autenticación con Google.
/// Funciona igual para la app de cliente y la de barbero
/// (ambas usan el mismo proyecto de Firebase).
class GoogleAuthService {
  static bool _initialized = false;

  /// Inicializa GoogleSignIn (debe llamarse una sola vez).
  // Web client ID del proyecto Firebase (client_type: 3 en google-services.json).
  // Necesario para que Google devuelva un ID token que Firebase pueda verificar.
  static const _webClientId =
      '345975115166-gqtuifchttuui1gs2an732uor5v8tq1e.apps.googleusercontent.com';

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _initialized = true;
  }

  /// Inicia sesión con Google y devuelve el [UserCredential] de Firebase.
  /// Retorna `null` si el usuario cancela el flujo.
  static Future<UserCredential?> signInWithGoogle() async {
    await _ensureInitialized();

    // 1. Autenticar con Google (abre selector de cuenta)
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // Si el usuario canceló, devolvemos null
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    // 2. Obtener idToken
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception(
        'Google no devolvió un ID token. Verifica que el SHA-1 del '
        'keystore esté registrado en Firebase Console.',
      );
    }

    // 3. Crear credencial de Firebase con el idToken
    final credential = GoogleAuthProvider.credential(idToken: idToken);

    // 4. Iniciar sesión en Firebase
    return await FirebaseAuth.instance.signInWithCredential(credential);
  }

  /// Cierra sesión de Google y Firebase.
  static Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();

    // Resetear el estado del diálogo de bienvenida para que se muestre cuando vuelva a ser invitado
    await WelcomeDialog.reset();
  }
}
