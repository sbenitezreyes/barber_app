import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Modelo ───────────────────────────────────────────────────────
class BarberService {
  final String? id;
  String name;
  double price;
  int durationMinutes;
  String description;

  BarberService({
    this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'durationMinutes': durationMinutes,
    'description': description,
  };

  factory BarberService.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BarberService(
      id: doc.id,
      name: d['name'] ?? '',
      price: (d['price'] as num).toDouble(),
      durationMinutes: d['durationMinutes'] ?? 30,
      description: d['description'] ?? '',
    );
  }
}

// ── Pantalla principal ───────────────────────────────────────────
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  CollectionReference<Map<String, dynamic>> get _col {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('services');
  }

  void _openForm({BarberService? service}) async {
    final result = await Navigator.of(context).push<BarberService>(
      MaterialPageRoute(builder: (_) => _ServiceFormScreen(service: service)),
    );
    if (result == null) return;

    if (service?.id != null) {
      // Actualizar
      await _col.doc(service!.id).update(result.toMap());
    } else {
      // Crear nuevo
      await _col.add(result.toMap());
    }
  }

  void _deleteService(BarberService service) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Eliminar servicio'),
        content: Text('¿Estás seguro de eliminar "${service.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _col.doc(service.id).delete();
            },
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis servicios'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: _col.orderBy('name').snapshots(),
        builder: (context, snapshot) {
          // Mostrar caché al instante si está disponible, luego actualizar con datos en tiempo real
          final docs = snapshot.data?.docs ?? [];
          final services = docs.map((d) => BarberService.fromDoc(d)).toList();

          // Solo mostrar CircularProgressIndicator si NO tenemos datos y está esperando
          if (services.isEmpty && snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && services.isEmpty) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (services.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.content_cut, size: 56, color: Colors.grey[700]),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no tienes servicios',
                    style: TextStyle(color: Colors.grey[500], fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar servicio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ServiceCard(
              service: services[i],
              onEdit: () => _openForm(service: services[i]),
              onDelete: () => _deleteService(services[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: theme.colorScheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ── Tarjeta de servicio ──────────────────────────────────────────
class _ServiceCard extends StatelessWidget {
  final BarberService service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceCard({
    required this.service,
    required this.onEdit,
    required this.onDelete,
  });

  String _formatPrice(double price) {
    final formatted = price
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return '\$$formatted';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: Colors.white54,
                ),
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                tooltip: 'Editar',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.redAccent,
                ),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                tooltip: 'Eliminar',
              ),
            ],
          ),
          if (service.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              service.description,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _Badge(
                icon: Icons.attach_money,
                label: _formatPrice(service.price),
                color: Colors.greenAccent,
              ),
              const SizedBox(width: 8),
              _Badge(
                icon: Icons.timer_outlined,
                label: '${service.durationMinutes} min',
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formulario ───────────────────────────────────────────────────
class _ServiceFormScreen extends StatefulWidget {
  final BarberService? service;

  const _ServiceFormScreen({this.service});

  @override
  State<_ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<_ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  int _duration = 30;

  static const _durations = [2, 15, 20, 30, 45, 60, 75, 90, 120];

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _priceCtrl = TextEditingController(
      text: s != null ? s.price.toStringAsFixed(0) : '',
    );
    _descCtrl = TextEditingController(text: s?.description ?? '');
    _duration = s?.durationMinutes ?? 30;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final service = BarberService(
      name: _nameCtrl.text.trim(),
      price: double.parse(_priceCtrl.text.trim()),
      durationMinutes: _duration,
      description: _descCtrl.text.trim(),
    );
    Navigator.of(context).pop(service);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.service != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar servicio' : 'Nuevo servicio'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Nombre
            _FormLabel('Nombre del servicio'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              decoration: _inputDecoration('Ej. Corte clásico'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
            ),
            const SizedBox(height: 20),

            // Precio
            _FormLabel('Precio (COP)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _priceCtrl,
              decoration: _inputDecoration('Ej. 25000'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa el precio';
                if (double.tryParse(v) == null) return 'Precio inválido';
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Duración
            _FormLabel('Tiempo estimado'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF18181C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: DropdownButton<int>(
                value: _duration,
                isExpanded: true,
                dropdownColor: const Color(0xFF18181C),
                underline: const SizedBox(),
                icon: const Icon(Icons.expand_more, color: Colors.white54),
                items: _durations
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          d < 60
                              ? '$d minutos'
                              : d == 60
                              ? '1 hora'
                              : '${d ~/ 60}h ${d % 60 > 0 ? '${d % 60}min' : ''}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _duration = v!),
              ),
            ),
            const SizedBox(height: 20),

            // Descripción
            _FormLabel('Descripción (opcional)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descCtrl,
              decoration: _inputDecoration(
                'Describe brevemente el servicio...',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 32),

            // Botón guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isEdit ? 'Guardar cambios' : 'Agregar servicio',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[600]),
    filled: true,
    fillColor: const Color(0xFF18181C),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: Colors.white70,
      ),
    );
  }
}
