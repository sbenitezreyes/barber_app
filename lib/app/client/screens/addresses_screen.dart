import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../shared/theme/app_theme.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _addressesCol =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('addresses');

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete(String id) async {
    try {
      await _addressesCol.doc(id).delete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al eliminar la dirección'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddAddressSheet(addressesCol: _addressesCol),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Mis direcciones', style: AppTextStyles.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _addressesCol
              .orderBy('createdAt', descending: false)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              );
            }

            final docs = snap.data?.docs ?? [];

            if (docs.isEmpty) {
              return _EmptyState(onAdd: _showAddSheet);
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final doc = docs[i];
                final data = doc.data();
                return _AddressTile(
                  docId: doc.id,
                  name: data['name'] as String? ?? '',
                  address: data['address'] as String? ?? '',
                  onDelete: () => _delete(doc.id),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: Text('Agregar', style: AppTextStyles.button),
      ),
    );
  }
}

// ── Tile de dirección ──────────────────────────────────────────

class _AddressTile extends StatelessWidget {
  final String docId;
  final String name;
  final String address;
  final VoidCallback onDelete;

  const _AddressTile({
    required this.docId,
    required this.name,
    required this.address,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(docId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.error,
          size: 22,
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eliminar dirección'),
            content: Text('¿Eliminar "$name"?', style: AppTextStyles.body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: AppDecorations.surface(),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.goldSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: AppColors.gold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.subtitle),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: AppTextStyles.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
                size: 20,
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar dirección'),
                    content: Text(
                      '¿Eliminar "$name"?',
                      style: AppTextStyles.body,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Estado vacío ───────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.goldSubtle,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppColors.gold,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text('Sin direcciones guardadas', style: AppTextStyles.subtitle),
            const SizedBox(height: 8),
            Text(
              'Guarda tus lugares frecuentes para agilizar tus reservas',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar dirección'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet: agregar dirección con mapa ──────────────────

class _AddAddressSheet extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> addressesCol;

  const _AddAddressSheet({required this.addressesCol});

  @override
  State<_AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<_AddAddressSheet> {
  static const _bogota = LatLng(4.7110, -74.0721);

  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _mapController = Completer<GoogleMapController>();

  bool _saving = false;
  bool _loadingLocation = true;
  bool _reverseGeocoding = false;
  LatLng _pinPosition = _bogota;
  String _resolvedAddress = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (!mounted) return;
        final latLng = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _pinPosition = latLng;
          _loadingLocation = false;
        });
        final ctrl = await _mapController.future;
        ctrl.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
        _reverseGeocode(latLng);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLocation = false);
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (mounted) setState(() => _reverseGeocoding = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('reverseGeocode');
      final result = await callable.call({'lat': pos.latitude, 'lng': pos.longitude});
      final address = result.data['address'] as String? ?? '';
      if (mounted) setState(() => _resolvedAddress = address);
    } catch (_) {}
    if (mounted) setState(() => _reverseGeocoding = false);
  }

  void _onPinDragEnd(LatLng pos) {
    setState(() => _pinPosition = pos);
    _reverseGeocode(pos);
  }

  void _onMapTap(LatLng pos) {
    setState(() => _pinPosition = pos);
    _reverseGeocode(pos);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.addressesCol.add({
        'name': _nameCtrl.text.trim(),
        'address': _resolvedAddress,
        'lat': _pinPosition.latitude,
        'lng': _pinPosition.longitude,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Nueva dirección', style: AppTextStyles.title),
            const SizedBox(height: 16),

            // Nombre
            Text('NOMBRE', style: AppTextStyles.label),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              style: AppTextStyles.body,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'ej. Casa, Trabajo...',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'El nombre es obligatorio'
                  : null,
            ),
            const SizedBox(height: 16),

            // Mapa con pin
            Text('UBICACIÓN EXACTA', style: AppTextStyles.label),
            const SizedBox(height: 8),
            Text(
              'Toca el mapa o arrastra el pin para ajustar',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 300,
                child: _loadingLocation
                    ? Container(
                        color: AppColors.surface,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.gold,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _pinPosition,
                          zoom: 16,
                        ),
                        onMapCreated: (ctrl) {
                          if (!_mapController.isCompleted) {
                            _mapController.complete(ctrl);
                          }
                        },
                        onTap: _onMapTap,
                        markers: {
                          Marker(
                            markerId: const MarkerId('pin'),
                            position: _pinPosition,
                            draggable: true,
                            onDragEnd: _onPinDragEnd,
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueOrange,
                            ),
                          ),
                        },
                        gestureRecognizers:
                            <Factory<OneSequenceGestureRecognizer>>{
                              Factory<EagerGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        myLocationButtonEnabled: false,
                        myLocationEnabled: true,
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Dirección resuelta
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.gold,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _reverseGeocoding
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.gold,
                            ),
                          )
                        : Text(
                            _resolvedAddress.isEmpty
                                ? 'Mueve el pin para ver la dirección'
                                : _resolvedAddress,
                            style: AppTextStyles.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.background,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Guardar dirección'),
            ),
          ],
        ),
      ),
    );
  }
}
