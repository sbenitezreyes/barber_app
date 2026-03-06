import 'package:flutter_test/flutter_test.dart';

/// Simula la lógica de notificaciones cuando se cancela una cita
class NotificationLogic {
  /// Determina quién debe recibir la notificación de cancelación
  /// 
  /// Si el barbero canceló (cancelledBy == barberUid), notificar al cliente
  /// Si el cliente canceló (cancelledBy == clientUid), notificar al barbero
  static String getNotificationRecipient({
    required String cancelledBy,
    required String barberUid,
    required String clientUid,
  }) {
    if (cancelledBy == barberUid) {
      return clientUid;
    } else if (cancelledBy == clientUid) {
      return barberUid;
    }
    // Por defecto, notificar al cliente
    return clientUid;
  }

  /// Genera el mensaje apropiado según quién canceló
  static String getCancellationMessage({
    required String cancelledBy,
    required String barberUid,
    required String clientUid,
    required String barberName,
    required String clientName,
  }) {
    if (cancelledBy == barberUid) {
      // El barbero canceló, mensaje para el cliente
      return '$barberName canceló la cita';
    } else if (cancelledBy == clientUid) {
      // El cliente canceló, mensaje para el barbero
      return '$clientName canceló la cita';
    }
    return 'La cita fue cancelada';
  }

  /// Genera el mensaje de notificación para el barbero en su panel
  static String getBarberPanelMessage({
    required String cancelledBy,
    required String barberUid,
    required String clientName,
  }) {
    if (cancelledBy == barberUid) {
      return 'Haz cancelado la cita a: $clientName';
    }
    return 'Cancelada · $clientName';
  }

  /// Genera el mensaje de notificación para el cliente en su panel
  static String getClientPanelMessage({
    required String cancelledBy,
    required String clientUid,
    required String barberName,
  }) {
    if (cancelledBy == barberName) {
      return '$barberName canceló la cita';
    }
    return 'Cancelada · $barberName';
  }
}

void main() {
  group('Notification Logic Tests', () {
    const barberUid = 'barber123';
    const clientUid = 'client456';
    const barberName = 'Santiago Benitez Reyes';
    const clientName = 'Karen Poenagos';

    group('Notification Recipient Tests', () {
      test('When barber cancels, client should receive notification', () {
        final recipient = NotificationLogic.getNotificationRecipient(
          cancelledBy: barberUid,
          barberUid: barberUid,
          clientUid: clientUid,
        );

        expect(recipient, equals(clientUid));
      });

      test('When client cancels, barber should receive notification', () {
        final recipient = NotificationLogic.getNotificationRecipient(
          cancelledBy: clientUid,
          barberUid: barberUid,
          clientUid: clientUid,
        );

        expect(recipient, equals(barberUid));
      });

      test('When unknown cancels, default to client', () {
        final recipient = NotificationLogic.getNotificationRecipient(
          cancelledBy: 'unknown_user',
          barberUid: barberUid,
          clientUid: clientUid,
        );

        expect(recipient, equals(clientUid));
      });
    });

    group('Cancellation Message Tests', () {
      test('When barber cancels, message should include barber name', () {
        final message = NotificationLogic.getCancellationMessage(
          cancelledBy: barberUid,
          barberUid: barberUid,
          clientUid: clientUid,
          barberName: barberName,
          clientName: clientName,
        );

        expect(message, equals('$barberName canceló la cita'));
        expect(message.contains(barberName), isTrue);
      });

      test('When client cancels, message should include client name', () {
        final message = NotificationLogic.getCancellationMessage(
          cancelledBy: clientUid,
          barberUid: barberUid,
          clientUid: clientUid,
          barberName: barberName,
          clientName: clientName,
        );

        expect(message, equals('$clientName canceló la cita'));
        expect(message.contains(clientName), isTrue);
      });

      test('When unknown cancels, use generic message', () {
        final message = NotificationLogic.getCancellationMessage(
          cancelledBy: 'unknown',
          barberUid: barberUid,
          clientUid: clientUid,
          barberName: barberName,
          clientName: clientName,
        );

        expect(message, equals('La cita fue cancelada'));
      });
    });

    group('Barber Panel Message Tests', () {
      test('When barber cancels, show "Haz cancelado" message', () {
        final message = NotificationLogic.getBarberPanelMessage(
          cancelledBy: barberUid,
          barberUid: barberUid,
          clientName: clientName,
        );

        expect(message, equals('Haz cancelado la cita a: $clientName'));
        expect(message.contains('Haz cancelado'), isTrue);
      });

      test('When client cancels, show "Cancelada" message', () {
        final message = NotificationLogic.getBarberPanelMessage(
          cancelledBy: clientUid,
          barberUid: barberUid,
          clientName: clientName,
        );

        expect(message, equals('Cancelada · $clientName'));
        expect(message.contains('Cancelada'), isTrue);
      });
    });

    group('Edge Cases', () {
      test('Empty UIDs should not crash', () {
        final recipient = NotificationLogic.getNotificationRecipient(
          cancelledBy: '',
          barberUid: barberUid,
          clientUid: clientUid,
        );

        expect(recipient, equals(clientUid)); // Default
      });

      test('Same UID for barber and client should handle gracefully', () {
        const sameUid = 'user123';
        final recipient = NotificationLogic.getNotificationRecipient(
          cancelledBy: sameUid,
          barberUid: sameUid,
          clientUid: sameUid,
        );

        // Debería notificar al "cliente" cuando el barbero cancela
        expect(recipient, equals(sameUid));
      });
    });
  });
}
