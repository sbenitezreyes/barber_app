const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');

const googleMapsKey = defineSecret('GOOGLE_MAPS_KEY');

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ── Helper: send a single FCM push ──────────────────────────────
// Mensajes data-only: sin campo notification para que Flutter
// siempre muestre la notificación vía flutter_local_notifications.
// Esto evita el DEVELOPER_ERROR del emulador y es más confiable en producción.
async function sendPush(token, title, body, data = {}) {
  if (!token) return;
  try {
    await messaging.send({
      token,
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { 'content-available': 1 } },
      },
      data: {
        title,
        body,
        ...Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
      },
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

    // ── Otorgar XP base al barbero cuando la cita se completa ───
    if (before.status !== 'completed' && after.status === 'completed') {
      await db.collection('users').doc(after.barberUid).update({
        xp: FieldValue.increment(20),
      });
      console.log(`Awarded 20 XP to barber ${after.barberUid} for completed appointment`);
    }

    // ── Marcar barbero como ocupado/libre según estado de la cita ──
    if (before.status !== 'confirmed' && status === 'confirmed') {
      await db.collection('users').doc(after.barberUid).update({ isBusy: true })
        .catch(() => {});
      console.log(`Barber ${after.barberUid} marked as busy`);
    }
    // Barbero libre solo cuando la cita termina (no cuando llega al sitio)
    if (status === 'completed' || status === 'cancelled' || status === 'missed') {
      await db.collection('users').doc(after.barberUid).update({ isBusy: false })
        .catch(() => {});
      console.log(`Barber ${after.barberUid} marked as available`);
    }
    // Limpiar tracking GPS cuando el barbero llega (confirmed→en_servicio) o la cita termina
    const leavingTracking =
      (before.status === 'confirmed' && (status === 'en_servicio' || status === 'cancelled' || status === 'completed')) ||
      (before.status === 'en_servicio' && (status === 'completed' || status === 'cancelled'));
    if (leavingTracking) {
      const ref = db.collection('appointments').doc(event.params.appointmentId);
      await ref.update({
        barberCurrentLat: FieldValue.delete(),
        barberCurrentLng: FieldValue.delete(),
        barberDeparting: FieldValue.delete(),
        barberDepartingEtaMin: FieldValue.delete(),
      }).catch(() => {});
      console.log(`Cleaned barber live location for appointment ${event.params.appointmentId}`);
    }
    const appointmentId = event.params.appointmentId;

    // Fetch client's FCM token and notification preferences
    const clientDoc = await db.collection('users').doc(clientUid).get();
    const clientData = clientDoc.data() ?? {};
    const fcmToken = clientData.fcmToken;
    const notifPrefs = clientData.notifPrefs ?? {};
    const notifsEnabled = notifPrefs.allEnabled !== false;
    console.log(`Client ${clientUid} has token: ${fcmToken ? fcmToken.slice(0, 20) + '...' : 'NONE'}`);

    // ── Notificar al cliente ─────────────────────────────────
    if (status === 'confirmed' || status === 'en_servicio' || status === 'rejected' || status === 'completed' || status === 'missed') {
      let title, body, prefKey;
      if (status === 'confirmed') {
        title = '✅ Cita confirmada';
        body = `${barberName} confirmó tu cita de ${serviceName}`;
        prefKey = 'confirmed';
      } else if (status === 'en_servicio') {
        title = '🪒 ¡Tu barbero llegó!';
        body = `${barberName} está en la puerta esperando para tu ${serviceName}. ¡Ábrele la puerta!`;
        prefKey = 'confirmed';
      } else if (status === 'completed') {
        title = '🎉 ¡Cita completada!';
        body = `${barberName} marcó tu cita de ${serviceName} como completada`;
        prefKey = 'completed';
      } else if (status === 'missed') {
        title = '😔 Tu barbero no se presentó';
        body = `${barberName} no pudo llegar a tu cita de ${serviceName}. Puedes dejar una reseña.`;
        prefKey = 'completed';
      } else {
        title = '❌ Cita rechazada';
        body = `${barberName} no pudo aceptar tu cita de ${serviceName}`;
        prefKey = 'rejected';
      }

      const individualEnabled = notifPrefs[prefKey] !== false;
      if (notifsEnabled && individualEnabled) {
        console.log(`Sending push to client: ${title} - ${body}`);
        await sendPush(fcmToken, title, body, {
          appointmentId,
          type: 'appointment_status',
          status,
        });
      } else {
        console.log(`Push skipped for client ${clientUid} (pref: allEnabled=${notifsEnabled}, ${prefKey}=${individualEnabled})`);
      }
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
      // Si el barbero canceló, notificar al cliente (respeta preferencias)
      else if (cancelledBy === after.barberUid) {
        const cancelPrefEnabled = notifPrefs.cancelledByBarber !== false;
        if (notifsEnabled && cancelPrefEnabled) {
          console.log(`Barber cancelled. Notifying client with token: ${fcmToken?.slice(0, 20)}...`);
          await sendPush(
            fcmToken,
            '❌ Cita cancelada',
            `${barberName} canceló tu cita de ${serviceName}`,
            { appointmentId, type: 'appointment_status', status }
          );
        } else {
          console.log(`Push skipped for client ${clientUid} (cancelledByBarber pref disabled)`);
        }
      }
    }
  }
);

// ── 3. Verificación de identidad → confirmar que se subieron las 3 fotos ──
exports.onVerificationSubmitted = onDocumentUpdated(
  'users/{uid}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.verificationStatus === after.verificationStatus) return;
    if (after.verificationStatus !== 'pending') return;

    const uid = event.params.uid;
    const userRef = db.collection('users').doc(uid);
    console.log(`Verification submitted for user ${uid}`);

    try {
      const bucket = getStorage().bucket();
      const basePath = `identity_verification/${uid}`;

      // Verificar que las 3 fotos existen en Storage
      const [frontExists, backExists, selfieExists] = await Promise.all([
        bucket.file(`${basePath}/id_front.jpg`).exists(),
        bucket.file(`${basePath}/id_back.jpg`).exists(),
        bucket.file(`${basePath}/selfie.jpg`).exists(),
      ]);

      console.log(`User ${uid} — front: ${frontExists[0]}, back: ${backExists[0]}, selfie: ${selfieExists[0]}`);

      if (!frontExists[0] || !backExists[0] || !selfieExists[0]) {
        await userRef.update({
          verificationStatus: 'rejected',
          verificationRejectionReason: 'No se recibieron todas las fotos requeridas. Por favor inténtalo de nuevo.',
          verificationReviewedAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      await userRef.update({
        verificationStatus: 'approved',
        verificationReviewedAt: FieldValue.serverTimestamp(),
      });
      console.log(`User ${uid} approved`);

    } catch (err) {
      console.error(`Verification error for user ${uid}:`, err.message);
    }
  }
);

// ── 4. Nueva reseña → otorgar XP al barbero según estrellas ────
exports.onReviewCreated = onDocumentCreated(
  'users/{barberUid}/reviews/{reviewId}',
  async (event) => {
    const review = event.data?.data();
    if (!review) return;

    const rating = Math.round(review.rating ?? 0);
    const xpTable = { 5: 60, 4: 45, 3: 30, 2: 15, 1: 5 };
    const xpGained = xpTable[rating] ?? 0;
    if (xpGained === 0) return;

    await db.collection('users').doc(event.params.barberUid)
      .update({ xp: FieldValue.increment(xpGained) });
    console.log(`Awarded ${xpGained} XP to barber ${event.params.barberUid} for ${rating}⭐ review`);
  }
);

// ── 5. Reseña eliminada → quitar XP al barbero ─────────────────
exports.onReviewDeleted = onDocumentDeleted(
  'users/{barberUid}/reviews/{reviewId}',
  async (event) => {
    const review = event.data?.data();
    if (!review) return;

    const rating = Math.round(review.rating ?? 0);
    const xpTable = { 5: 60, 4: 45, 3: 30, 2: 15, 1: 5 };
    const xpToRemove = xpTable[rating] ?? 0;
    if (xpToRemove === 0) return;

    await db.collection('users').doc(event.params.barberUid)
      .update({ xp: FieldValue.increment(-xpToRemove) });
    console.log(`Removed ${xpToRemove} XP from barber ${event.params.barberUid} for deleted ${rating}⭐ review`);
  }
);

// ── 6. Recordatorio al cliente 1 hora antes de la cita ─────────
exports.sendAppointmentReminders = onSchedule(
  { schedule: 'every 1 minutes', timeZone: 'America/Bogota' },
  async () => {
    const now = Date.now();

    // Ventana: todas las citas desde ahora hasta +75 min
    // El límite inferior es `now` para capturar citas de último minuto
    const windowStart = Timestamp.fromMillis(now);
    const windowEnd   = Timestamp.fromMillis(now + 75 * 60 * 1000);

    // Query usando índice existente: isImmediate + scheduledAt
    const snap = await db.collection('appointments')
      .where('isImmediate', '==', false)
      .where('scheduledAt', '>=', windowStart)
      .where('scheduledAt', '<=', windowEnd)
      .get();

    if (!snap.empty) {
    for (const doc of snap.docs) {
      const appt = doc.data();
      if (appt.status !== 'pending' && appt.status !== 'confirmed') continue;
      const apptTime = appt.scheduledAt.toMillis();
      const minutesLeft = Math.round((apptTime - now) / 60000);
      const updates = {};

      const { clientUid, barberUid, barberName, clientName, serviceName, scheduledAt } = appt;

      const timeStr = scheduledAt.toDate().toLocaleString('es-CO', {
        timeZone: 'America/Bogota',
        timeStyle: 'short',
      });

      // ── Recordatorio al CLIENTE (cita dentro de 75 min o menos) ─
      if (appt.reminderSent !== true) {
        updates.reminderSent = true;

        const clientDoc = await db.collection('users').doc(clientUid).get();
        const clientData = clientDoc.data() ?? {};
        const fcmToken = clientData.fcmToken;
        const notifPrefs = clientData.notifPrefs ?? {};
        const notifsEnabled = notifPrefs.allEnabled !== false;
        const reminderEnabled = notifPrefs.reminder !== false;

        if (fcmToken && notifsEnabled && reminderEnabled) {
          const clientTitle = minutesLeft <= 10
            ? '🚨 ¡Tu cita es ahora!'
            : minutesLeft <= 30
              ? `⏰ Tu cita es en ${minutesLeft} minutos`
              : '⏰ Tu cita es en 1 hora';
          await sendPush(
            fcmToken,
            clientTitle,
            `Tienes una cita de ${serviceName} con ${barberName} a las ${timeStr}`,
            { appointmentId: doc.id, type: 'appointment_reminder' }
          );
          console.log(`Client reminder sent to ${clientUid} (${minutesLeft} min left)`);
        }
      }

      // ── Recordatorio al BARBERO (solo si confirmada, dentro de 45 min) ─
      if (appt.status === 'confirmed' && appt.barberReminderSent !== true && minutesLeft <= 45) {
        updates.barberReminderSent = true;

        const barberDoc = await db.collection('users').doc(barberUid).get();
        const barberToken = barberDoc.data()?.fcmToken;

        if (barberToken) {
          const barberTitle = minutesLeft <= 10
            ? '🚨 ¡Cita ahora!'
            : `🗓️ Cita en ${minutesLeft} minutos`;
          await sendPush(
            barberToken,
            barberTitle,
            `${clientName ?? 'Un cliente'} te espera para ${serviceName} a las ${timeStr}`,
            { appointmentId: doc.id, type: 'barber_reminder' }
          );
          console.log(`Barber reminder sent to ${barberUid} (${minutesLeft} min left)`);
        }
      }

      if (Object.keys(updates).length > 0) {
        await doc.ref.update(updates);
      }
    }
    } // end if (!snap.empty)

    // ── Detectar citas perdidas (barbero no se presentó) ─────────
    // Solo status == 'confirmed', filtra isImmediate client-side
    const missedSnap = await db.collection('appointments')
      .where('status', '==', 'confirmed')
      .get();

    for (const doc of missedSnap.docs) {
      const appt = doc.data();
      if (appt.isImmediate === true) continue;     // citas inmediatas no aplica
      if (appt.barberDeparting === true) continue; // sí fue
      const endTime = appt.scheduledAt.toMillis() + (appt.serviceDuration ?? 30) * 60 * 1000;
      if (now < endTime) continue; // aún no ha terminado
      await doc.ref.update({ status: 'missed' });
      console.log(`Appointment ${doc.id} marked as missed (barber did not depart)`);

      // Penalizar al barbero con -65 XP por cita perdida
      await db.collection('users').doc(appt.barberUid).update({
        xp: FieldValue.increment(-65),
      });
      console.log(`Deducted 65 XP from barber ${appt.barberUid} for missed appointment ${doc.id}`);
    }
  }
);

// ── 6 (antes 5). Limpiar citas rechazadas con más de 8 días ─────
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

// ── 7 (antes 6). Barbero en camino → notificar al cliente ───────
exports.onBarberDeparting = onDocumentUpdated(
  'appointments/{appointmentId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    // Solo disparar cuando barberDeparting pasa de falsy a true
    if (before.barberDeparting === true || after.barberDeparting !== true) return;

    const { clientUid, barberName, serviceName, barberDepartingEtaMin } = after;
    const appointmentId = event.params.appointmentId;

    const clientDoc = await db.collection('users').doc(clientUid).get();
    const clientData = clientDoc.data() ?? {};
    const fcmToken = clientData.fcmToken;
    const notifPrefs = clientData.notifPrefs ?? {};
    const notifsEnabled = notifPrefs.allEnabled !== false;

    if (!notifsEnabled) {
      console.log(`Push skipped for client ${clientUid} (notifications disabled)`);
      return;
    }

    const etaText = barberDepartingEtaMin
      ? `Llegará en aproximadamente ${barberDepartingEtaMin} min.`
      : 'Ya está en camino.';

    await sendPush(
      fcmToken,
      '🚗 ¡Tu barbero está en camino!',
      `${barberName} sale ahora para tu cita de ${serviceName}. ${etaText}`,
      { appointmentId, type: 'barber_departing' }
    );
  }
);

// ── Proxy seguro para Directions API ────────────────────────────
exports.getRoute = onCall(
  { secrets: [googleMapsKey], cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Se requiere autenticación.');
    }
    const { originLat, originLng, destLat, destLng } = request.data;
    if (!originLat || !originLng || !destLat || !destLng) {
      throw new HttpsError('invalid-argument', 'Faltan coordenadas.');
    }
    const key = googleMapsKey.value();
    const url =
      `https://maps.googleapis.com/maps/api/directions/json` +
      `?origin=${originLat},${originLng}` +
      `&destination=${destLat},${destLng}` +
      `&mode=driving&key=${key}`;
    const resp = await fetch(url);
    const data = await resp.json();
    if (data.status !== 'OK') {
      throw new HttpsError('internal', `Directions API: ${data.status}`);
    }
    const encoded = data.routes[0]?.overview_polyline?.points ?? '';
    return { encodedPolyline: encoded };
  }
);

// ── Proxy seguro para Geocoding inverso (coordenadas → dirección) ─
exports.reverseGeocode = onCall(
  { secrets: [googleMapsKey], cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Se requiere autenticación.');
    }
    const { lat, lng } = request.data;
    if (lat == null || lng == null) {
      throw new HttpsError('invalid-argument', 'Faltan coordenadas.');
    }
    const key = googleMapsKey.value();
    const url =
      `https://maps.googleapis.com/maps/api/geocode/json` +
      `?latlng=${lat},${lng}&key=${key}`;
    const resp = await fetch(url);
    const data = await resp.json();
    if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
      throw new HttpsError('internal', `Geocoding API: ${data.status}`);
    }
    const address = data.results?.[0]?.formatted_address ?? '';
    return { address };
  }
);

// ── Proxy seguro para Geocoding directo (dirección → coordenadas) ─
exports.geocodeAddress = onCall(
  { secrets: [googleMapsKey], cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Se requiere autenticación.');
    }
    const { address } = request.data;
    if (!address) {
      throw new HttpsError('invalid-argument', 'Falta la dirección.');
    }
    const key = googleMapsKey.value();
    const encoded = encodeURIComponent(address);
    const url =
      `https://maps.googleapis.com/maps/api/geocode/json` +
      `?address=${encoded}&key=${key}`;
    const resp = await fetch(url);
    const data = await resp.json();
    if (data.status !== 'OK') {
      throw new HttpsError('internal', `Geocoding API: ${data.status}`);
    }
    const loc = data.results[0]?.geometry?.location;
    if (!loc) throw new HttpsError('not-found', 'No se encontró la dirección.');
    return { lat: loc.lat, lng: loc.lng };
  }
);
