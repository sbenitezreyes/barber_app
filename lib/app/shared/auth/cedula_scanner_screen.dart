import 'dart:typed_data';

// Ocultar ImageFormat de camera para que no colisione con flutter_zxing
import 'package:camera/camera.dart' hide ImageFormat;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../theme/app_theme.dart';
import 'cedula_decoder.dart';

// ── Función top-level para compute() — corre en isolate separado ─────────────
Code _decodePdf417(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final w = args['w'] as int;
  final h = args['h'] as int;
  return zx.readBarcode(
    bytes,
    DecodeParams(
      imageFormat: ImageFormat.lum, // plano Y de YUV420
      format: Format.pdf417,
      width: w,
      height: h,
      cropLeft: 0,
      cropTop: 0,
      cropWidth: w,
      cropHeight: h,
      tryHarder: true,
      tryRotate: true,
    ),
  );
}

/// Pantalla de escaneo de cédula colombiana.
///
/// Retorna un [CedulaData] via [Navigator.pop] si el escaneo es exitoso,
/// o `null` si el usuario cancela.
class CedulaScannerScreen extends StatefulWidget {
  const CedulaScannerScreen({super.key});

  @override
  State<CedulaScannerScreen> createState() => _CedulaScannerScreenState();
}

class _CedulaScannerScreenState extends State<CedulaScannerScreen>
    with WidgetsBindingObserver {
  bool _showIntro = true;

  // ── Cámara ────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _cameraReady = false;
  bool _torchOn = false;

  // ── Scan ──────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _detected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (!_showIntro) _initCamera();
    }
  }

  Future<void> _disposeCamera() async {
    await _camCtrl?.stopImageStream().catchError((_) {});
    await _camCtrl?.dispose();
    _camCtrl = null;
    if (mounted) setState(() => _cameraReady = false);
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final ctrl = CameraController(
      back,
      ResolutionPreset.veryHigh, // más píxeles → PDF417 decodifica mejor
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await ctrl.initialize();
      // Autofoco continuo para que el código de barras quede nítido
      await ctrl.setFocusMode(FocusMode.auto);
    } catch (e) {
      debugPrint('Camera init error: $e');
      return;
    }

    if (!mounted) {
      ctrl.dispose();
      return;
    }

    _camCtrl = ctrl;
    setState(() => _cameraReady = true);

    // Iniciar stream de frames
    try {
      await ctrl.startImageStream(_onFrame);
      debugPrint('Camera: image stream started OK');
    } catch (e) {
      debugPrint('Camera: stream start error: $e');
    }
  }

  // ── Procesamiento de frames ───────────────────────────────────

  Future<void> _onFrame(CameraImage image) async {
    if (_isProcessing || _detected || !mounted) return;
    _isProcessing = true;
    debugPrint('ZXing: frame ${image.width}x${image.height}');

    // Copiar plano Y ANTES de cualquier await — el buffer puede liberarse
    final int w = image.width;
    final int h = image.height;
    final plane = image.planes[0];
    final int rowStride = plane.bytesPerRow;
    final Uint8List yBytes;
    if (rowStride == w) {
      // Sin padding: copia directa
      yBytes = Uint8List.fromList(plane.bytes);
    } else {
      // Con padding de fila: copiar solo los w píxeles válidos por fila
      yBytes = Uint8List(w * h);
      for (int row = 0; row < h; row++) {
        yBytes.setRange(row * w, (row + 1) * w, plane.bytes, row * rowStride);
      }
    }

    try {
      // Decodificar en isolate separado (evita colgarse en processCameraImage)
      final result = await compute(_decodePdf417, {
        'bytes': yBytes,
        'w': w,
        'h': h,
      });

      debugPrint(
        'ZXing: isValid=${result.isValid} format=${result.format} bytes=${result.rawBytes?.length} text=${result.text?.length}',
      );

      if (result.isValid && mounted) {
        _detected = true;
        await _camCtrl?.stopImageStream().catchError((_) {});
        _handleResult(result);
      }
    } catch (e, st) {
      debugPrint('ZXing error: $e\n$st');
    }

    _isProcessing = false;
  }

  void _handleResult(Code code) {
    Uint8List? bytes = code.rawBytes;

    // Fallback: convertir text a bytes latin-1 si rawBytes no está disponible
    if ((bytes == null || bytes.isEmpty) &&
        code.text != null &&
        code.text!.isNotEmpty) {
      bytes = Uint8List.fromList(
        code.text!.codeUnits.map((c) => c & 0xFF).toList(),
      );
    }

    if (bytes == null || bytes.isEmpty) {
      if (mounted) setState(() => _detected = false);
      return;
    }

    final data = CedulaDecoder.decodeBytes(bytes);
    if (data != null) {
      Navigator.of(context).pop(data);
      return;
    }

    // DEBUG: muestra los bytes si el decode falla
    _showRawDialog(bytes);
  }

  void _showRawDialog(Uint8List bytes) {
    final preview = String.fromCharCodes(
      bytes.map((b) => (b >= 32 && b < 127) ? b : 46),
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Debug: PDF417 detectado'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bytes: ${bytes.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _detected = false;
              await _camCtrl?.startImageStream(_onFrame).catchError((_) {});
            },
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  // ── Controles ─────────────────────────────────────────────────

  Future<void> _startScanning() async {
    setState(() {
      _showIntro = false;
      _detected = false;
      _cameraReady = false;
    });
    await _initCamera();
  }

  void _backToIntro() {
    _disposeCamera();
    setState(() {
      _showIntro = true;
      _detected = false;
    });
  }

  Future<void> _toggleTorch() async {
    if (_camCtrl == null) return;
    _torchOn = !_torchOn;
    await _camCtrl!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showIntro) return _buildIntro(context);
    return _buildScanner(context);
  }

  Widget _buildIntro(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textSecondary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.goldSubtle,
                  border: Border.all(color: AppColors.borderAccent, width: 1.5),
                ),
                child: const Icon(
                  Icons.badge_rounded,
                  color: AppColors.gold,
                  size: 28,
                ),
              ),
              const SizedBox(height: 24),
              Text('Verifica tu identidad', style: AppTextStyles.headline),
              const SizedBox(height: 10),
              Text(
                'Para garantizar la seguridad de nuestros clientes, '
                'todos los barberos deben verificar su identidad escaneando '
                'su cédula de ciudadanía colombiana.',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              _Step(number: '1', text: 'Ten tu cédula física a mano.'),
              _Step(
                number: '2',
                text:
                    'Apunta la cámara al reverso de la cédula, '
                    'donde está el código de barras negro (PDF417).',
              ),
              _Step(
                number: '3',
                text:
                    'El escaneo es automático. Mantén la cédula '
                    'firme y bien iluminada hasta que detectemos el código.',
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.gold,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'El código PDF417 está en la parte inferior trasera '
                        'de la cédula — franja de barras negras horizontales.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _startScanning,
                  icon: const Icon(Icons.document_scanner_rounded, size: 20),
                  label: Text('Escanear cédula', style: AppTextStyles.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Preview de cámara
            if (_cameraReady && _camCtrl != null)
              Positioned.fill(child: CameraPreview(_camCtrl!))
            else
              const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),

            // Overlay rectangular guía (3:1 — proporción PDF417)
            if (_cameraReady) const _BarcodeOverlay(),

            // Barra superior: volver + linterna
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: _backToIntro,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    if (_cameraReady)
                      IconButton(
                        onPressed: _toggleTorch,
                        icon: Icon(
                          _torchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Instrucciones inferiores
            if (_cameraReady)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 52),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Apunta al reverso de tu cédula',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.subtitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Código de barras PDF417 — parte inferior trasera',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Overlay rectangular 3:1 ───────────────────────────────────────

class _BarcodeOverlay extends StatelessWidget {
  const _BarcodeOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RectOverlayPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _RectOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double hPad = 24.0;
    final double cutW = size.width - hPad * 2;
    final double cutH = cutW / 3.0; // proporción 3:1 del PDF417
    final double cutL = hPad;
    final double cutT = (size.height - cutH) / 2;
    final cutRect = Rect.fromLTWH(cutL, cutT, cutW, cutH);

    final dark = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(cutRect, const Radius.circular(6)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dark);

    const cLen = 22.0;
    const r = 6.0;
    final corner = Paint()
      ..color = const Color(0xFFC9A84C)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    void drawCorner(Offset o, bool fx, bool fy) {
      final dx = fx ? -1.0 : 1.0;
      final dy = fy ? -1.0 : 1.0;
      canvas.drawLine(
        Offset(o.dx + dx * r, o.dy),
        Offset(o.dx + dx * (r + cLen), o.dy),
        corner,
      );
      canvas.drawLine(
        Offset(o.dx, o.dy + dy * r),
        Offset(o.dx, o.dy + dy * (r + cLen)),
        corner,
      );
    }

    drawCorner(Offset(cutL, cutT), false, false);
    drawCorner(Offset(cutL + cutW, cutT), true, false);
    drawCorner(Offset(cutL, cutT + cutH), false, true);
    drawCorner(Offset(cutL + cutW, cutT + cutH), true, true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Widget de paso numerado ───────────────────────────────────────

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.goldSubtle,
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Center(
              child: Text(
                number,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
