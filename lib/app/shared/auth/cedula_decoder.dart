import 'package:flutter/foundation.dart';

/// Datos extraídos del código de barras PDF417 de la cédula colombiana.
@immutable
class CedulaData {
  final String documentNumber;
  final String lastName;
  final String secondLastName;
  final String firstName;
  final String middleName;
  final String gender;
  final String rawBirthDate; // YYYYMMDD
  final String bloodType;

  const CedulaData({
    required this.documentNumber,
    required this.lastName,
    required this.secondLastName,
    required this.firstName,
    required this.middleName,
    required this.gender,
    required this.rawBirthDate,
    this.bloodType = '',
  });

  /// Nombre completo: nombres + apellidos.
  String get fullName {
    final parts = [
      firstName,
      if (middleName.isNotEmpty) middleName,
      lastName,
      if (secondLastName.isNotEmpty) secondLastName,
    ].join(' ');
    return parts.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  /// Fecha de nacimiento en formato DD/MM/AAAA.
  String get formattedBirthDate {
    if (rawBirthDate.length < 8) return rawBirthDate;
    return '${rawBirthDate.substring(6, 8)}/${rawBirthDate.substring(4, 6)}/${rawBirthDate.substring(0, 4)}';
  }
}

/// Decodifica el contenido binario del PDF417 de la cédula de ciudadanía colombiana.
///
/// Algoritmo basado en https://github.com/Eitol/colombian-cedula-reader
/// El payload (~531 bytes, latin-1) usa bytes nulos como delimitadores de campo.
///
/// Pasos:
///   1. Validar presencia del marcador "PubDSK_"
///   2. Colapsar secuencias de 2+ nulls (\x00) en un único null
///   3. Dividir en campos usando null como separador → lista sp[]
///   4. Extraer campos desde índices específicos de sp[]
class CedulaDecoder {
  static const _marker = 'PubDSK_';

  /// Devuelve [CedulaData] si los bytes corresponden a una cédula colombiana válida,
  /// o `null` en caso contrario.
  static CedulaData? decodeBytes(Uint8List rawBytes) {
    if (rawBytes.length < 400) return null;

    // Validar marcador de cédula colombiana
    if (!_latin1(rawBytes).contains(_marker)) return null;

    try {
      // 1. Colapsar null runs
      final collapsed = <int>[];
      int nullRun = 0;
      for (final b in rawBytes) {
        if (b == 0) {
          nullRun++;
          if (nullRun == 1) collapsed.add(0);
        } else {
          nullRun = 0;
          collapsed.add(b);
        }
      }

      // 2. Split on null bytes → sp[]
      var sp = <List<int>>[];
      var current = <int>[];
      for (final b in collapsed) {
        if (b == 0) {
          sp.add(List.from(current));
          current = [];
        } else {
          current.add(b);
        }
      }
      if (current.isNotEmpty) sp.add(current);

      if (sp.length < 7) return null;

      // 3. Extraer campos
      String docNumber;
      String lastName;

      if (sp[2].length > 8) {
        // Layout normal
        docNumber = _field(sp[2], 10, 18);
        lastName = _field(sp[2], 18);
      } else {
        // Layout alternativo (lectores seriales / Windows)
        sp = sp.sublist(1);
        if (sp.length < 7) return null;
        docNumber = _field(sp[2], 0, 10);
        lastName = _field(sp[2], 10);
      }

      final secondLastName = _field(sp[3]);
      final firstName = _field(sp[4]);
      String middleName = _field(sp[5]);

      // Cuando no hay segundo nombre, el campo termina en '-' o '+'
      if (middleName.endsWith('-') || middleName.endsWith('+')) {
        middleName = '';
        sp.insert(5, [0x78]); // placeholder para mantener índices alineados
      }

      if (sp.length < 7) return null;

      final sp6 = _latin1(sp[6]);
      final gender = sp6.length > 1 ? sp6[1] : '';
      final birthYear = sp6.length >= 6 ? sp6.substring(2, 6) : '';
      final birthMonth = sp6.length >= 8 ? sp6.substring(6, 8) : '';
      final birthDay = sp6.length >= 10 ? sp6.substring(8, 10) : '';
      final bloodType = sp6.length >= 18 ? sp6.substring(16, 18).trim() : '';

      if (docNumber.isEmpty || lastName.isEmpty || firstName.isEmpty)
        return null;

      return CedulaData(
        documentNumber: docNumber,
        lastName: lastName,
        secondLastName: secondLastName,
        firstName: firstName,
        middleName: middleName,
        gender: gender,
        rawBirthDate: '$birthYear$birthMonth$birthDay',
        bloodType: bloodType,
      );
    } catch (e) {
      debugPrint('CedulaDecoder error: $e');
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  static String _latin1(List<int> bytes) => String.fromCharCodes(bytes);

  /// Extrae un campo de [bytes] entre [start] y [end], decodificado en latin-1.
  /// Corta en el primer null byte y hace trim().
  static String _field(List<int> bytes, [int? start, int? end]) {
    final s = _latin1(bytes);
    final a = start ?? 0;
    final b = (end ?? s.length).clamp(a, s.length);
    return s.substring(a, b).split('\x00')[0].trim();
  }
}
