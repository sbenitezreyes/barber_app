import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Términos y Condiciones', style: AppTextStyles.title),
        centerTitle: true,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: _TermsContent(),
      ),
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        // ── 1 ─────────────────────────────────────────────────
        _SectionTitle('1. ACEPTACIÓN DE LOS TÉRMINOS'),
        _Body(
          'Al registrarse y utilizar la aplicación móvil YaCut, el usuario declara haber leído, '
          'entendido y aceptado los presentes Términos, Condiciones y Política de Privacidad.\n\n'
          'Si el usuario no está de acuerdo con alguna de las disposiciones aquí establecidas, '
          'deberá abstenerse de utilizar la aplicación.\n\n'
          'El registro implica consentimiento expreso para el tratamiento de datos personales '
          'conforme a este documento.',
        ),

        // ── 2 ─────────────────────────────────────────────────
        _SectionTitle('2. DESCRIPCIÓN DEL SERVICIO'),
        _Body(
          'YaCut es una plataforma tecnológica que conecta clientes con barberos independientes '
          'que prestan servicios de barbería a domicilio.\n\n'
          'La aplicación actúa únicamente como intermediaria digital entre el cliente y el '
          'profesional. YaCut no presta directamente los servicios de barbería.',
        ),

        // ── 3 ─────────────────────────────────────────────────
        _SectionTitle('3. REGISTRO Y CUENTA DE USUARIO'),
        _Body(
          'Para utilizar la plataforma, el usuario deberá proporcionar información veraz y '
          'actualizada, que puede incluir:',
        ),
        _BulletList([
          'Nombre completo',
          'Correo electrónico',
          'Fotografía de perfil (opcional)',
          'Fecha de nacimiento (opcional)',
          'Direcciones guardadas (opcional)',
        ]),
        _Body(
          'El usuario es responsable de la confidencialidad de su cuenta y contraseña.',
        ),

        // ── 4 ─────────────────────────────────────────────────
        _SectionTitle('4. PERMISOS Y ACCESO A FUNCIONES DEL DISPOSITIVO'),

        _SubSectionTitle('4.1 Ubicación en tiempo real'),
        _Body('La aplicación podrá acceder a la ubicación del usuario para:'),
        _BulletList([
          'Mostrar barberos disponibles cerca.',
          'Calcular distancias y tiempos de desplazamiento.',
          'Permitir el seguimiento en tiempo real del barbero durante una cita activa.',
          'Mejorar la asignación de servicios.',
        ]),
        _Body(
          'La ubicación del barbero se transmite únicamente mientras existe una cita confirmada '
          'en curso y se elimina automáticamente al finalizarla.\n\n'
          'El usuario puede desactivar el permiso de ubicación desde la configuración del '
          'dispositivo, entendiendo que esto puede afectar el funcionamiento del servicio.',
        ),

        _SubSectionTitle('4.2 Cámara y galería'),
        _Body(
          'La aplicación podrá solicitar acceso a la cámara y galería para:',
        ),
        _BulletList(['Tomar o cargar una foto de perfil.']),
        _Body(
          'El acceso a la cámara y galería solo se realizará con autorización previa del usuario.',
        ),

        _SubSectionTitle('4.3 Notificaciones push'),
        _Body('La aplicación podrá enviar notificaciones para:'),
        _BulletList([
          'Confirmación, rechazo o cancelación de citas.',
          'Avisos de cita completada.',
          'Mensajes importantes relacionados con la cuenta.',
        ]),
        _Body(
          'El usuario podrá gestionar sus preferencias de notificación individualmente desde '
          'Ajustes → Notificaciones dentro de la aplicación, o desactivarlas desde la '
          'configuración del dispositivo.',
        ),

        // ── 6 ─────────────────────────────────────────────────
        _SectionTitle('6. POLÍTICA DE PRIVACIDAD Y PROTECCIÓN DE DATOS'),
        _Body('La información recopilada podrá incluir:'),
        _BulletList([
          'Datos de identificación (nombre, correo electrónico).',
          'Fecha de nacimiento.',
          'Direcciones guardadas.',
          'Ubicación en tiempo real durante una cita activa.',
          'Historial de citas y valoraciones.',
          'Información técnica del dispositivo y token de notificaciones.',
        ]),
        _Body('Los datos serán utilizados exclusivamente para:'),
        _BulletList([
          'Gestionar y coordinar citas.',
          'Facilitar la comunicación entre cliente y barbero.',
          'Garantizar la seguridad del servicio.',
          'Mejorar la experiencia del usuario.',
          'Cumplir obligaciones legales.',
        ]),
        _Body(
          'YaCut no venderá ni comercializará datos personales a terceros.\n\n'
          'Los datos se almacenan en servidores de Google Firebase (Cloud Firestore y '
          'Firebase Storage) con cifrado en tránsito y en reposo.',
        ),

        // ── 7 ─────────────────────────────────────────────────
        _SectionTitle('7. POLÍTICA DE CANCELACIONES'),
        _Body(
          'El usuario podrá cancelar una cita mientras esté en estado pendiente o confirmada.\n\n'
          'Cancelaciones reiteradas por parte del cliente o el barbero podrán:',
        ),
        _BulletList([
          'Generar penalizaciones visibles en el perfil.',
          'Limitar temporalmente el uso del servicio.',
        ]),

        // ── 8 ─────────────────────────────────────────────────
        _SectionTitle('8. SISTEMA DE VALORACIONES'),
        _Body(
          'Tras cada cita completada, el cliente podrá dejar una valoración al barbero.\n\n'
          'Las valoraciones son públicas y contribuyen a la reputación del profesional en '
          'la plataforma. Está prohibido manipular o falsificar valoraciones.',
        ),

        // ── 9 ─────────────────────────────────────────────────
        _SectionTitle('9. PAGOS Y TRANSACCIONES'),
        _Body(
          'En caso de habilitarse pagos electrónicos dentro de la aplicación:',
        ),
        _BulletList([
          'Los precios serán establecidos por los barberos.',
          'La plataforma podrá actuar como intermediaria del pago.',
          'Podrán aplicarse comisiones por uso del servicio.',
          'Las cancelaciones podrán estar sujetas a políticas de reembolso.',
        ]),

        // ── 10 ────────────────────────────────────────────────
        _SectionTitle('10. RESPONSABILIDAD DEL SERVICIO'),
        _Body(
          'YaCut actúa exclusivamente como intermediaria tecnológica.\n\n'
          'La calidad, puntualidad y resultado del servicio son responsabilidad exclusiva '
          'del barbero contratado.\n\n'
          'La plataforma no será responsable por:',
        ),
        _BulletList([
          'Daños físicos o resultados insatisfactorios.',
          'Conductas indebidas del profesional.',
          'Pérdidas indirectas derivadas del servicio.',
          'Fallos de conectividad o disponibilidad del servicio.',
        ]),

        // ── 11 ────────────────────────────────────────────────
        _SectionTitle('11. USO INDEBIDO'),
        _Body('Está prohibido:'),
        _BulletList([
          'Proporcionar información falsa o documentos de identidad fraudulentos.',
          'Utilizar la aplicación para fines ilícitos.',
          'Realizar conductas ofensivas o discriminatorias.',
          'Manipular el sistema de calificaciones.',
          'Intentar vulnerar la seguridad de la plataforma.',
        ]),
        _Body(
          'El incumplimiento podrá generar suspensión o cancelación definitiva de la cuenta.',
        ),

        // ── 12 ────────────────────────────────────────────────
        _SectionTitle('12. DISPONIBILIDAD DEL SERVICIO'),
        _Body(
          'La plataforma podrá suspender temporalmente el servicio por mantenimiento o '
          'actualizaciones. No se garantiza disponibilidad continua e ininterrumpida.',
        ),

        // ── 13 ────────────────────────────────────────────────
        _SectionTitle('13. MODIFICACIONES'),
        _Body(
          'YaCut podrá modificar estos términos en cualquier momento. El uso continuado de '
          'la aplicación implicará aceptación de las modificaciones.',
        ),

        // ── 14 ────────────────────────────────────────────────
        _SectionTitle('14. LEGISLACIÓN APLICABLE'),
        _Body(
          'Estos términos se regirán conforme a la legislación vigente de la República de '
          'Colombia, incluyendo la Ley 1581 de 2012 de Protección de Datos Personales '
          '(Habeas Data) y sus decretos reglamentarios.',
        ),

        // ── 15 ────────────────────────────────────────────────
        _SectionTitle('15. CONSENTIMIENTO EXPRESO'),
        _Body('Al crear una cuenta y aceptar estos términos, el usuario:'),
        _BulletList([
          'Autoriza el tratamiento de sus datos personales.',
          'Autoriza el uso de ubicación en tiempo real durante citas activas.',
          'Acepta recibir notificaciones relacionadas con el servicio.',
          'Acepta los presentes Términos y Condiciones en su totalidad.',
        ]),

        // ── 16 ────────────────────────────────────────────────
        _SectionTitle('16. PROYECTO ACADÉMICO'),
        _Body(
          'YaCut es un proyecto desarrollado con fines académicos y de investigación. '
          'La aplicación puede encontrarse en fase de desarrollo o pruebas y no constituye '
          'necesariamente una plataforma comercial definitiva.',
        ),

        SizedBox(height: 16),
      ],
    );
  }
}

// ── Widgets privados ───────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: AppTextStyles.label.copyWith(
          color: AppColors.gold,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SubSectionTitle extends StatelessWidget {
  final String text;
  const _SubSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTextStyles.body.copyWith(
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList(this.items);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
