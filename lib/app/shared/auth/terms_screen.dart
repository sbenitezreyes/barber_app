import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        title: const Text('Términos y Condiciones'),
        centerTitle: true,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
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
        _SectionTitle('1. ACEPTACIÓN DE LOS TÉRMINOS'),
        _Body(
          'Al registrarse y utilizar la aplicación móvil Barber App, el usuario declara haber leído, entendido y aceptado los presentes Términos, Condiciones y Política de Privacidad.\n\n'
          'Si el usuario no está de acuerdo con alguna de las disposiciones aquí establecidas, deberá abstenerse de utilizar la aplicación.\n\n'
          'El registro en la aplicación implica consentimiento expreso para el tratamiento de datos personales conforme a este documento.',
        ),

        _SectionTitle('2. DESCRIPCIÓN DEL SERVICIO'),
        _Body(
          'Barber App es una plataforma tecnológica que conecta clientes con barberos independientes que prestan servicios de barbería a domicilio.\n\n'
          'La aplicación actúa únicamente como intermediaria digital entre el cliente y el profesional.\n\n'
          'Barber App no presta directamente los servicios de barbería.',
        ),

        _SectionTitle('3. REGISTRO Y CUENTA DE USUARIO'),
        _Body(
          'Para utilizar la plataforma, el usuario deberá proporcionar información veraz y actualizada, que puede incluir:',
        ),
        _BulletList([
          'Nombre completo',
          'Número de teléfono',
          'Correo electrónico',
          'Dirección del servicio',
          'Fotografía de perfil (opcional)',
        ]),
        _Body(
          'El usuario es responsable de la confidencialidad de su cuenta y contraseña.',
        ),

        _SectionTitle('4. PERMISOS Y ACCESO A FUNCIONES DEL DISPOSITIVO'),
        _Body(
          'Para el correcto funcionamiento del servicio, la aplicación podrá solicitar los siguientes permisos:',
        ),
        _SubSectionTitle('4.1 Ubicación en tiempo real'),
        _Body('La aplicación podrá acceder a la ubicación del usuario:'),
        _BulletList([
          'Para mostrar barberos cercanos.',
          'Para calcular distancias.',
          'Para permitir el seguimiento en tiempo real del barbero hacia el domicilio.',
          'Para mejorar la asignación de servicios.',
        ]),
        _Body(
          'La ubicación podrá utilizarse mientras la aplicación esté activa o en segundo plano cuando exista una cita activa o en curso.\n\n'
          'El usuario puede desactivar el permiso de ubicación desde la configuración del dispositivo, entendiendo que esto puede afectar el funcionamiento del servicio.',
        ),
        _SubSectionTitle('4.2 Cámara y galería'),
        _Body('La aplicación podrá solicitar acceso a:'),
        _BulletList([
          'Cámara (para tomar foto de perfil o referencias de corte).',
          'Galería (para cargar imágenes).',
        ]),
        _Body('El acceso solo se realizará con autorización previa del usuario.'),
        _SubSectionTitle('4.3 Notificaciones push'),
        _Body('La aplicación podrá enviar notificaciones para:'),
        _BulletList([
          'Confirmación de citas.',
          'Recordatorios.',
          'Estado del servicio.',
          'Mensajes importantes relacionados con la cuenta.',
          'Promociones (cuando el usuario lo autorice).',
        ]),
        _Body(
          'El usuario podrá desactivar las notificaciones en cualquier momento desde la configuración del dispositivo.',
        ),

        _SectionTitle('5. POLÍTICA DE PRIVACIDAD Y PROTECCIÓN DE DATOS'),
        _Body('La información recopilada podrá incluir:'),
        _BulletList([
          'Datos de identificación.',
          'Datos de contacto.',
          'Dirección del servicio.',
          'Ubicación en tiempo real.',
          'Información técnica del dispositivo.',
        ]),
        _Body('Los datos serán utilizados exclusivamente para:'),
        _BulletList([
          'Gestionar citas.',
          'Facilitar la comunicación entre cliente y barbero.',
          'Garantizar la seguridad del servicio.',
          'Mejorar la experiencia del usuario.',
          'Cumplir obligaciones legales.',
        ]),
        _Body(
          'Barber App no venderá ni comercializará datos personales a terceros.\n\n'
          'Los datos podrán ser almacenados en servidores seguros y protegidos mediante medidas técnicas y organizativas adecuadas.',
        ),

        _SectionTitle('6. PAGOS Y TRANSACCIONES'),
        _Body('En caso de habilitarse pagos electrónicos dentro de la aplicación:'),
        _BulletList([
          'Los precios serán establecidos por los barberos.',
          'La plataforma podrá actuar como intermediaria del pago.',
          'Podrán aplicarse comisiones por uso del servicio.',
          'Las cancelaciones podrán estar sujetas a políticas de reembolso.',
        ]),

        _SectionTitle('7. POLÍTICA DE CANCELACIONES'),
        _Body(
          'El usuario podrá cancelar una cita antes del tiempo límite establecido en la aplicación.\n\n'
          'Cancelaciones tardías o reiteradas podrán:',
        ),
        _BulletList([
          'Generar penalizaciones.',
          'Limitar temporalmente el uso del servicio.',
          'Aplicar cargos si existieran pagos anticipados.',
        ]),
        _Body('Las políticas específicas serán informadas dentro de la aplicación.'),

        _SectionTitle('8. RESPONSABILIDAD DEL SERVICIO'),
        _Body(
          'Barber App actúa exclusivamente como intermediaria tecnológica.\n\n'
          'La calidad, puntualidad y resultado del servicio son responsabilidad exclusiva del barbero contratado.\n\n'
          'La plataforma no será responsable por:',
        ),
        _BulletList([
          'Daños físicos.',
          'Resultados insatisfactorios.',
          'Conductas indebidas del profesional.',
          'Pérdidas indirectas derivadas del servicio.',
        ]),

        _SectionTitle('9. USO INDEBIDO'),
        _Body('Está prohibido:'),
        _BulletList([
          'Proporcionar información falsa.',
          'Utilizar la aplicación para fines ilícitos.',
          'Realizar conductas ofensivas o discriminatorias.',
          'Manipular el sistema de calificaciones.',
          'Intentar vulnerar la seguridad de la plataforma.',
        ]),
        _Body('El incumplimiento podrá generar suspensión o cancelación de la cuenta.'),

        _SectionTitle('10. DISPONIBILIDAD DEL SERVICIO'),
        _Body(
          'La plataforma podrá suspender temporalmente el servicio por mantenimiento o actualizaciones.\n\n'
          'No se garantiza disponibilidad continua e ininterrumpida.',
        ),

        _SectionTitle('11. MODIFICACIONES'),
        _Body(
          'Barber App podrá modificar estos términos en cualquier momento. El uso continuado de la aplicación implicará aceptación de las modificaciones.',
        ),

        _SectionTitle('12. LEGISLACIÓN APLICABLE'),
        _Body(
          'Estos términos se regirán conforme a la legislación vigente del país donde opere la aplicación.',
        ),

        _SectionTitle('13. CONSENTIMIENTO EXPRESO'),
        _Body('Al crear una cuenta y marcar la casilla de aceptación, el usuario:'),
        _BulletList([
          'Autoriza el tratamiento de sus datos personales.',
          'Autoriza el uso de ubicación en tiempo real.',
          'Acepta recibir notificaciones relacionadas con el servicio.',
          'Acepta los presentes Términos y Condiciones.',
        ]),

        _SectionTitle('14. PROYECTO ACADÉMICO'),
        _Body(
          'Barber App es un proyecto desarrollado con fines académicos y de investigación, en el marco de una tesis universitaria.\n\n'
          'La aplicación puede encontrarse en fase de desarrollo o pruebas y no constituye necesariamente una plataforma comercial definitiva.',
        ),

        SizedBox(height: 32),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFE94560),
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
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
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
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
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
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
      padding: const EdgeInsets.only(left: 12, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(color: Color(0xFFE94560), fontSize: 14),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
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
