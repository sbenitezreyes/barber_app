import 'package:flutter_test/flutter_test.dart';

/// Estados posibles de una cita
enum AppointmentStatus {
  pending,
  confirmed,
  rejected,
  cancelled,
  completed
}

/// Lógica de transiciones de estado de citas
class AppointmentStatusLogic {
  /// Valida si una transición de estado es válida
  static bool canTransitionTo(AppointmentStatus from, AppointmentStatus to) {
    switch (from) {
      case AppointmentStatus.pending:
        // Desde pending se puede ir a confirmed, rejected, o cancelled
        return to == AppointmentStatus.confirmed ||
            to == AppointmentStatus.rejected ||
            to == AppointmentStatus.cancelled;
      
      case AppointmentStatus.confirmed:
        // Desde confirmed se puede ir a cancelled o completed
        return to == AppointmentStatus.cancelled ||
            to == AppointmentStatus.completed;
      
      case AppointmentStatus.rejected:
      case AppointmentStatus.cancelled:
      case AppointmentStatus.completed:
        // Estados terminales, no pueden cambiar
        return false;
    }
  }

  /// Determina si un estado es terminal
  static bool isTerminalState(AppointmentStatus status) {
    return status == AppointmentStatus.rejected ||
        status == AppointmentStatus.cancelled ||
        status == AppointmentStatus.completed;
  }

  /// Determina si un estado requiere notificación al otro usuario
  static bool requiresNotification(AppointmentStatus status) {
    return status == AppointmentStatus.confirmed ||
        status == AppointmentStatus.rejected ||
        status == AppointmentStatus.cancelled;
  }

  /// Obtiene el color asociado a un estado
  static String getStatusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'orange';
      case AppointmentStatus.confirmed:
        return 'green';
      case AppointmentStatus.rejected:
      case AppointmentStatus.cancelled:
        return 'red';
      case AppointmentStatus.completed:
        return 'blue';
    }
  }

  /// Convierte string a enum
  static AppointmentStatus? fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppointmentStatus.pending;
      case 'confirmed':
        return AppointmentStatus.confirmed;
      case 'rejected':
        return AppointmentStatus.rejected;
      case 'cancelled':
        return AppointmentStatus.cancelled;
      case 'completed':
        return AppointmentStatus.completed;
      default:
        return null;
    }
  }
}

void main() {
  group('Appointment Status Tests', () {
    group('State Transition Tests', () {
      test('Pending can transition to confirmed', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.pending,
            AppointmentStatus.confirmed,
          ),
          isTrue,
        );
      });

      test('Pending can transition to rejected', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.pending,
            AppointmentStatus.rejected,
          ),
          isTrue,
        );
      });

      test('Pending can transition to cancelled', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.pending,
            AppointmentStatus.cancelled,
          ),
          isTrue,
        );
      });

      test('Pending cannot transition to completed', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.pending,
            AppointmentStatus.completed,
          ),
          isFalse,
        );
      });

      test('Confirmed can transition to cancelled', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.confirmed,
            AppointmentStatus.cancelled,
          ),
          isTrue,
        );
      });

      test('Confirmed can transition to completed', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.confirmed,
            AppointmentStatus.completed,
          ),
          isTrue,
        );
      });

      test('Confirmed cannot transition to pending', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.confirmed,
            AppointmentStatus.pending,
          ),
          isFalse,
        );
      });

      test('Cancelled cannot transition to any state', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.cancelled,
            AppointmentStatus.pending,
          ),
          isFalse,
        );
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.cancelled,
            AppointmentStatus.confirmed,
          ),
          isFalse,
        );
      });

      test('Completed cannot transition to any state', () {
        expect(
          AppointmentStatusLogic.canTransitionTo(
            AppointmentStatus.completed,
            AppointmentStatus.cancelled,
          ),
          isFalse,
        );
      });
    });

    group('Terminal State Tests', () {
      test('Pending is not terminal', () {
        expect(
          AppointmentStatusLogic.isTerminalState(AppointmentStatus.pending),
          isFalse,
        );
      });

      test('Confirmed is not terminal', () {
        expect(
          AppointmentStatusLogic.isTerminalState(AppointmentStatus.confirmed),
          isFalse,
        );
      });

      test('Rejected is terminal', () {
        expect(
          AppointmentStatusLogic.isTerminalState(AppointmentStatus.rejected),
          isTrue,
        );
      });

      test('Cancelled is terminal', () {
        expect(
          AppointmentStatusLogic.isTerminalState(AppointmentStatus.cancelled),
          isTrue,
        );
      });

      test('Completed is terminal', () {
        expect(
          AppointmentStatusLogic.isTerminalState(AppointmentStatus.completed),
          isTrue,
        );
      });
    });

    group('Notification Requirement Tests', () {
      test('Pending does not require notification', () {
        expect(
          AppointmentStatusLogic.requiresNotification(
            AppointmentStatus.pending,
          ),
          isFalse,
        );
      });

      test('Confirmed requires notification', () {
        expect(
          AppointmentStatusLogic.requiresNotification(
            AppointmentStatus.confirmed,
          ),
          isTrue,
        );
      });

      test('Rejected requires notification', () {
        expect(
          AppointmentStatusLogic.requiresNotification(
            AppointmentStatus.rejected,
          ),
          isTrue,
        );
      });

      test('Cancelled requires notification', () {
        expect(
          AppointmentStatusLogic.requiresNotification(
            AppointmentStatus.cancelled,
          ),
          isTrue,
        );
      });
    });

    group('String Conversion Tests', () {
      test('Convert string to enum correctly', () {
        expect(
          AppointmentStatusLogic.fromString('pending'),
          equals(AppointmentStatus.pending),
        );
        expect(
          AppointmentStatusLogic.fromString('confirmed'),
          equals(AppointmentStatus.confirmed),
        );
      });

      test('Handle case-insensitive conversion', () {
        expect(
          AppointmentStatusLogic.fromString('PENDING'),
          equals(AppointmentStatus.pending),
        );
        expect(
          AppointmentStatusLogic.fromString('Confirmed'),
          equals(AppointmentStatus.confirmed),
        );
      });

      test('Return null for invalid string', () {
        expect(
          AppointmentStatusLogic.fromString('invalid_status'),
          isNull,
        );
      });
    });

    group('Color Assignment Tests', () {
      test('Each status has a color assigned', () {
        expect(
          AppointmentStatusLogic.getStatusColor(AppointmentStatus.pending),
          equals('orange'),
        );
        expect(
          AppointmentStatusLogic.getStatusColor(AppointmentStatus.confirmed),
          equals('green'),
        );
        expect(
          AppointmentStatusLogic.getStatusColor(AppointmentStatus.rejected),
          equals('red'),
        );
        expect(
          AppointmentStatusLogic.getStatusColor(AppointmentStatus.cancelled),
          equals('red'),
        );
        expect(
          AppointmentStatusLogic.getStatusColor(AppointmentStatus.completed),
          equals('blue'),
        );
      });
    });
  });
}
