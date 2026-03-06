const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ── Helper: send a single FCM push ──────────────────────────────
async function sendPush(token, title, body, data = {}) {
  if (!token) return;
  try {
    await messaging.send({
      token,
      notification: { title, body },
      android: {
        priority: 'high',
        notification: { channelId: 'appointments_channel', sound: 'default' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
    });
    console.log(`Push sent to ${token.slice(0, 20)}…`);
  } catch (err) {
    console.error('FCM error:', err.message);
  }
}

// ── 1. Nueva cita → notificar al barbero ────────────────────────
exports.onNewAppointment = onDocumentCreated(
  'appointments/{appointmentId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const appt = snap.data();
    const { barberUid, clientName, serviceName, isImmediate, scheduledAt } = appt;
    const appointmentId = event.params.appointmentId;

    // Fetch barber's FCM token
    const barberDoc = await db.collection('users').doc(barberUid).get();
    const fcmToken = barberDoc.data()?.fcmToken;
    if (!fcmToken) {
      console.log(`Barber ${barberUid} has no FCM token, skipping push.`);
      return;
    }

    const when = isImmediate
      ? 'ahora mismo'
      : scheduledAt?.toDate().toLocaleString('es-CO', {
          timeZone: 'America/Bogota',
          dateStyle: 'short',
          timeStyle: 'short',
        }) ?? '';

    await sendPush(
      fcmToken,
      '📅 Nueva solicitud de cita',
      `${clientName} quiere: ${serviceName} — ${when}`,
      { appointmentId, type: 'new_appointment' }
    );
  }
);

// ── 2. Cita actualizada → notificar al cliente ──────────────────
exports.onAppointmentStatusChanged = onDocumentUpdated(
  'appointments/{appointmentId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.status === after.status) return; // not a status change

    const { clientUid, barberName, serviceName, status } = after;

    // ── Limpiar ubicación en vivo del barbero cuando la cita sale de 'confirmed'
    // Esto cubre el caso en que la app del barbero fue forzada a cerrar
    // sin que dispose() pudiera borrar los campos.
    if (before.status === 'confirmed' && status !== 'confirmed') {
      const ref = db.collection('appointments').doc(event.params.appointmentId);
      await ref.update({
        barberCurrentLat: FieldValue.delete(),
        barberCurrentLng: FieldValue.delete(),
      }).catch(() => {});
      console.log(`Cleaned barber live location for appointment ${event.params.appointmentId}`);
    }
    const appointmentId = event.params.appointmentId;

    // Fetch client's FCM token
    const clientDoc = await db.collection('users').doc(clientUid).get();
    const fcmToken = clientDoc.data()?.fcmToken;

    // ── Notificar al cliente ─────────────────────────────────
    if (status === 'confirmed' || status === 'rejected') {
      let title, body;
      if (status === 'confirmed') {
        title = '✅ Cita confirmada';
        body = `${barberName} confirmó tu cita de ${serviceName}`;
      } else {
        title = '❌ Cita rechazada';
        body = `${barberName} no pudo aceptar tu cita de ${serviceName}`;
      }
      await sendPush(fcmToken, title, body, {
        appointmentId,
        type: 'appointment_status',
        status,
      });
    }

    // ── Notificar a la persona correcta cuando se cancela ───────
    if (status === 'cancelled') {
      const cancelledBy = after.cancelledBy;
      console.log(`Cancellation detected. cancelledBy: ${cancelledBy}, clientUid: ${clientUid}, barberUid: ${after.barberUid}`);
      
      // Si el cliente canceló, notificar al barbero
      if (cancelledBy === clientUid) {
        const barberDoc = await db.collection('users').doc(after.barberUid).get();
        const barberToken = barberDoc.data()?.fcmToken;
        const clientName = after.clientName ?? 'El cliente';
        console.log(`Client cancelled. Notifying barber with token: ${barberToken?.slice(0, 20)}...`);
        await sendPush(
          barberToken,
          '❌ Cita cancelada',
          `${clientName} canceló la cita de ${serviceName}`,
          { appointmentId, type: 'appointment_status', status }
        );
      }
      // Si el barbero canceló, notificar al cliente
      else if (cancelledBy === after.barberUid) {
        console.log(`Barber cancelled. Notifying client with token: ${fcmToken?.slice(0, 20)}...`);
        await sendPush(
          fcmToken,
          '❌ Cita cancelada',
          `${barberName} canceló tu cita de ${serviceName}`,
          { appointmentId, type: 'appointment_status', status }
        );
      }
    }
  }
);

// ── 3. Limpiar citas rechazadas con más de 8 días ───────────────
exports.cleanupRejectedAppointments = onSchedule(
  { schedule: 'every 24 hours', timeZone: 'America/Bogota' },
  async () => {
    const cutoff = Timestamp.fromDate(
      new Date(Date.now() - 8 * 24 * 60 * 60 * 1000)
    );

    const snap = await db
      .collection('appointments')
      .where('status', '==', 'rejected')
      .where('createdAt', '<=', cutoff)
      .get();

    if (snap.empty) {
      console.log('No rejected appointments to delete.');
      return;
    }

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    console.log(`Deleted ${snap.size} rejected appointment(s) older than 8 days.`);
  }
);
