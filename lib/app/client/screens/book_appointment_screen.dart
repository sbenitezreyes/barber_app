import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/auth/auth_screen.dart';
import 'client_home_screen.dart';

// ── Modelo de servicio exportado para uso en el sheet ───────────
class BookService {
  final String id;
  final String name;
  final double price;
  final int durationMinutes;
  final String description;

  const BookService({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    required this.description,
  });
}

// ── Pantalla principal ───────────────────────────────────────────
class BookAppointmentScreen extends StatefulWidget {
  final String barberUid;
  final String barberName;
  final List<BookService> services;

  const BookAppointmentScreen({
    super.key,
    required this.barberUid,
    required this.barberName,
    required this.services,
  });

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  int _step = 0; // 0 = servicio, 1 = horario, 2 = ubicación, 3 = confirmación
  BookService? _selectedService;
  bool _isImmediate = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  // Ubicación: 'gps' usa el GPS del teléfono, 'saved' usa una dirección guardada
  String _locationMode = 'gps';
  String? _savedAddressId;
  String? _savedAddressName;
  String? _savedAddressText;
  double? _savedAddressLat;
  double? _savedAddressLng;
  bool _saving = false;
  bool _justAuthenticated = false; // Indica si el usuario acaba de autenticarse

  Future<(double, double)?> _geocodeAddress(String address) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('geocodeAddress');
      final result = await callable.call({'address': address});
      final lat = (result.data['lat'] as num).toDouble();
      final lng = (result.data['lng'] as num).toDouble();
      return (lat, lng);
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────
  String _formatPrice(double p) {
    final f = p
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return '\$$f';
  }

  String _formatDateTime() {
    if (_isImmediate) return 'Ahora mismo';
    if (_selectedDate == null || _selectedTime == null) return '-';
    final d = _selectedDate!;
    final t = _selectedTime!;
    const months = [
      '',
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month]} ${d.year} · $h:$m';
  }

  bool get _canContinueStep1 => _selectedService != null;
  bool get _canContinueStep2 =>
      _isImmediate || (_selectedDate != null && _selectedTime != null);

  // ── Guardar cita ─────────────────────────────────────────────
  Future<void> _confirmAppointment() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      // Navegar al login y esperar el resultado
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const AuthScreen(returnAfterAuth: true),
        ),
      );

      // Si el usuario completó el login, marcar que se acaba de autenticar
      if (result == true && mounted) {
        setState(() => _justAuthenticated = true);
        await _confirmAppointment();
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final user = currentUser;
      DateTime scheduledAt;
      if (_isImmediate) {
        scheduledAt = DateTime.now();
      } else {
        scheduledAt = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
      }

      // Obtener ubicación del cliente para compartir con el barbero
      double? clientLat;
      double? clientLng;
      String? clientAddress;
      String? clientAddressName;

      if (_locationMode == 'saved') {
        clientAddress = _savedAddressText;
        clientAddressName = _savedAddressName;
        if (_savedAddressLat != null && _savedAddressLng != null) {
          // Coordenadas guardadas directamente desde el pin del mapa
          clientLat = _savedAddressLat;
          clientLng = _savedAddressLng;
        } else if (_savedAddressText != null) {
          // Fallback: geocodificar (para direcciones antiguas sin lat/lng)
          final coords = await _geocodeAddress(_savedAddressText!);
          if (coords != null) {
            clientLat = coords.$1;
            clientLng = coords.$2;
          }
        }
      } else {
        // Usar GPS actual (comportamiento por defecto)
        try {
          LocationPermission perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.whileInUse ||
              perm == LocationPermission.always) {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 5),
              ),
            );
            clientLat = pos.latitude;
            clientLng = pos.longitude;
          }
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('appointments').add({
        'barberUid': widget.barberUid,
        'barberName': widget.barberName,
        'clientUid': user.uid,
        'clientName': user.displayName ?? 'Cliente',
        'serviceName': _selectedService!.name,
        'servicePrice': _selectedService!.price,
        'serviceDuration': _selectedService!.durationMinutes,
        'isImmediate': _isImmediate,
        'scheduledAt': Timestamp.fromDate(scheduledAt),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        if (clientLat != null) 'clientLat': clientLat,
        if (clientLng != null) 'clientLng': clientLng,
        if (clientAddress != null) 'clientAddress': clientAddress,
        if (clientAddressName != null) 'clientAddressName': clientAddressName,
      });

      if (!mounted) return;

      // Si el usuario acaba de autenticarse, recargar toda la app
      if (_justAuthenticated) {
        // Capturar el messenger antes de navegar
        final messenger = ScaffoldMessenger.of(context);
        final primaryColor = Theme.of(context).colorScheme.primary;

        // Navegar al home
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ClientHomeScreen()),
          (route) => false,
        );

        // Mostrar mensaje de éxito
        messenger.showSnackBar(
          SnackBar(
            content: const Text('¡Cita solicitada con éxito!'),
            backgroundColor: primaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        // Flujo normal: solo cerrar la pantalla
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('¡Cita solicitada con éxito!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al guardar la cita. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitle()),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            if (_step == 0) {
              Navigator.of(context).pop();
            } else {
              setState(() => _step--);
            }
          },
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _buildStep(theme),
      ),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  String _stepTitle() {
    switch (_step) {
      case 0:
        return 'Elige un servicio';
      case 1:
        return '¿Cuándo?';
      case 2:
        return '¿Dónde?';
      default:
        return 'Confirmar cita';
    }
  }

  // ── Pasos ────────────────────────────────────────────────────
  Widget _buildStep(ThemeData theme) {
    switch (_step) {
      case 0:
        return _StepServices(
          key: const ValueKey(0),
          services: widget.services,
          selected: _selectedService,
          onSelect: (s) => setState(() => _selectedService = s),
          formatPrice: _formatPrice,
        );
      case 1:
        return _StepTime(
          key: const ValueKey(1),
          isImmediate: _isImmediate,
          selectedDate: _selectedDate,
          selectedTime: _selectedTime,
          onImmediate: () => setState(() {
            _isImmediate = true;
            _selectedDate = null;
            _selectedTime = null;
          }),
          onDatePick: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 90)),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: Theme.of(ctx).colorScheme.copyWith(
                    primary: theme.colorScheme.primary,
                    surface: const Color(0xFF18181C),
                  ),
                  dialogTheme: const DialogThemeData(
                    backgroundColor: Color(0xFF1A1A2E),
                  ),
                ),
                child: child!,
              ),
            );
            if (date != null) {
              setState(() {
                _isImmediate = false;
                _selectedDate = date;
              });
            }
          },
          onTimePick: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: Theme.of(ctx).colorScheme.copyWith(
                    primary: theme.colorScheme.primary,
                    surface: const Color(0xFF18181C),
                  ),
                  dialogTheme: const DialogThemeData(
                    backgroundColor: Color(0xFF1A1A2E),
                  ),
                ),
                child: child!,
              ),
            );
            if (time != null) {
              setState(() {
                _isImmediate = false;
                _selectedTime = time;
              });
            }
          },
        );
      case 2:
        return _StepLocation(
          key: const ValueKey(2),
          locationMode: _locationMode,
          selectedAddressId: _savedAddressId,
          onGpsSelected: () => setState(() {
            _locationMode = 'gps';
            _savedAddressId = null;
            _savedAddressName = null;
            _savedAddressText = null;
          }),
          onAddressSelected: (id, name, address, lat, lng) => setState(() {
            _locationMode = 'saved';
            _savedAddressId = id;
            _savedAddressName = name;
            _savedAddressText = address;
            _savedAddressLat = lat;
            _savedAddressLng = lng;
          }),
        );
      default:
        return _StepConfirm(
          key: const ValueKey(3),
          barberName: widget.barberName,
          service: _selectedService!,
          dateTimeLabel: _formatDateTime(),
          locationLabel: _locationMode == 'saved' && _savedAddressName != null
              ? '$_savedAddressName · $_savedAddressText'
              : 'Ubicación GPS',
          formatPrice: _formatPrice,
        );
    }
  }

  Widget _buildBottomBar(ThemeData theme) {
    final canContinue = switch (_step) {
      0 => _canContinueStep1,
      1 => _canContinueStep2,
      _ => true, // paso 2 (ubicación) y paso 3 (confirmar) siempre habilitados
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (canContinue && !_saving)
                ? () {
                    if (_step < 3) {
                      setState(() => _step++);
                    } else {
                      _confirmAppointment();
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white12,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _step < 3 ? 'Continuar' : 'Confirmar cita',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Paso 1: Seleccionar servicio ─────────────────────────────────
class _StepServices extends StatelessWidget {
  final List<BookService> services;
  final BookService? selected;
  final ValueChanged<BookService> onSelect;
  final String Function(double) formatPrice;

  const _StepServices({
    super.key,
    required this.services,
    required this.selected,
    required this.onSelect,
    required this.formatPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = services[i];
        final isSelected = selected?.id == s.id;
        return GestureDetector(
          onTap: () => onSelect(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : const Color(0xFF18181C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? theme.colorScheme.primary : Colors.white12,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.content_cut,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.white54,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      if (s.description.isNotEmpty)
                        Text(
                          s.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPrice(s.price),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      '${s.durationMinutes} min',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Paso 2: Seleccionar horario ──────────────────────────────────
class _StepTime extends StatelessWidget {
  final bool isImmediate;
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final VoidCallback onImmediate;
  final VoidCallback onDatePick;
  final VoidCallback onTimePick;

  const _StepTime({
    super.key,
    required this.isImmediate,
    required this.selectedDate,
    required this.selectedTime,
    required this.onImmediate,
    required this.onDatePick,
    required this.onTimePick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Cuándo quieres la cita?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // ── Ahora mismo ──
          _OptionCard(
            icon: Icons.bolt,
            title: 'Ahora mismo',
            subtitle: 'El barbero atenderá en cuanto esté disponible',
            selected: isImmediate,
            color: theme.colorScheme.primary,
            onTap: onImmediate,
          ),

          const SizedBox(height: 16),
          const Center(
            child: Text(
              '— o programa una cita —',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),

          // ── Programar: fecha ──
          _OptionCard(
            icon: Icons.calendar_month_outlined,
            title: selectedDate == null
                ? 'Seleccionar fecha'
                : _formatDate(selectedDate!),
            subtitle: 'Elige el día que prefieras',
            selected: !isImmediate && selectedDate != null,
            color: theme.colorScheme.primary,
            onTap: onDatePick,
          ),

          const SizedBox(height: 10),

          // ── Programar: hora ──
          _OptionCard(
            icon: Icons.schedule,
            title: selectedTime == null
                ? 'Seleccionar hora'
                : _formatTime(selectedTime!),
            subtitle: 'Elige la hora que prefieras',
            selected: !isImmediate && selectedTime != null,
            color: theme.colorScheme.primary,
            onTap: onTimePick,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      '',
      'enero',
      'feb',
      'mar',
      'abr',
      'mayo',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${d.day} de ${months[d.month]} de ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Paso 3: Seleccionar ubicación ────────────────────────────────
class _StepLocation extends StatelessWidget {
  final String locationMode; // 'gps' o 'saved'
  final String? selectedAddressId;
  final VoidCallback onGpsSelected;
  final void Function(String id, String name, String address, double? lat, double? lng)
  onAddressSelected;

  const _StepLocation({
    super.key,
    required this.locationMode,
    required this.selectedAddressId,
    required this.onGpsSelected,
    required this.onAddressSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isGuest =
        uid == null ||
        uid.isEmpty ||
        (FirebaseAuth.instance.currentUser?.isAnonymous ?? false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Dónde quieres la cita?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'El barbero se dirigirá a la dirección que elijas',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),

          // Opción GPS
          _OptionCard(
            icon: Icons.my_location_rounded,
            title: 'Mi ubicación actual',
            subtitle: 'El barbero usará tu GPS al momento de confirmar',
            selected: locationMode == 'gps',
            color: theme.colorScheme.primary,
            onTap: onGpsSelected,
          ),

          if (!isGuest) ...[
            const SizedBox(height: 16),
            const Center(
              child: Text(
                '— o elige una dirección guardada —',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('addresses')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_off_outlined,
                          color: Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No tienes direcciones guardadas. Puedes añadirlas desde tu perfil.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'] as String? ?? '';
                    final address = data['address'] as String? ?? '';
                    final lat = (data['lat'] as num?)?.toDouble();
                    final lng = (data['lng'] as num?)?.toDouble();
                    final isSelected =
                        locationMode == 'saved' &&
                        doc.id == selectedAddressId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OptionCard(
                        icon: Icons.location_on_outlined,
                        title: name,
                        subtitle: address.isEmpty
                            ? 'Ubicación guardada con pin'
                            : address,
                        selected: isSelected,
                        color: theme.colorScheme.primary,
                        onTap: () => onAddressSelected(doc.id, name, address, lat, lng),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : const Color(0xFF18181C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? color : Colors.white54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? color : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Paso 4: Confirmar ────────────────────────────────────────────
class _StepConfirm extends StatelessWidget {
  final String barberName;
  final BookService service;
  final String dateTimeLabel;
  final String locationLabel;
  final String Function(double) formatPrice;

  const _StepConfirm({
    super.key,
    required this.barberName,
    required this.service,
    required this.dateTimeLabel,
    required this.locationLabel,
    required this.formatPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de tu cita',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          _SummaryRow(
            icon: Icons.person_outline,
            label: 'Barbero',
            value: barberName,
          ),
          _SummaryRow(
            icon: Icons.content_cut,
            label: 'Servicio',
            value: service.name,
          ),
          _SummaryRow(
            icon: Icons.attach_money,
            label: 'Precio',
            value: formatPrice(service.price),
            valueColor: theme.colorScheme.primary,
          ),
          _SummaryRow(
            icon: Icons.schedule,
            label: 'Duración',
            value: '${service.durationMinutes} min',
          ),
          _SummaryRow(
            icon: Icons.calendar_today_outlined,
            label: 'Fecha / Hora',
            value: dateTimeLabel,
          ),
          _SummaryRow(
            icon: Icons.location_on_outlined,
            label: 'Ubicación',
            value: locationLabel,
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Al confirmar, el barbero recibirá tu solicitud de cita.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white54),
          const SizedBox(width: 14),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
