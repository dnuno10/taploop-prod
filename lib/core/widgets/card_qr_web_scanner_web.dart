// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class CardQrWebScanner extends StatefulWidget {
  final ValueChanged<String> onDetected;
  final ValueChanged<String> onError;

  const CardQrWebScanner({
    super.key,
    required this.onDetected,
    required this.onError,
  });

  @override
  State<CardQrWebScanner> createState() => _CardQrWebScannerState();
}

class _CardQrWebScannerState extends State<CardQrWebScanner> {
  static const String _phoneFallbackMessage =
      'Si tu computadora no tiene camara, accede desde tu telefono para usar su camara y escanear el QR.';

  late final String _viewType;
  late final html.VideoElement _videoElement;
  html.MediaStream? _mediaStream;
  Object? _barcodeDetector;
  Timer? _scanTimer;
  bool _disposed = false;
  bool _scanInFlight = false;
  bool _reportedError = false;

  @override
  void initState() {
    super.initState();
    _viewType =
        'taploop-qr-web-scanner-${DateTime.now().microsecondsSinceEpoch}';
    _videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.border = '0';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      return _videoElement;
    });

    unawaited(_initScanner());
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _stopCamera();
    super.dispose();
  }

  Future<void> _initScanner() async {
    try {
      final barcodeDetectorCtor = js_util.getProperty<Object?>(
        html.window,
        'BarcodeDetector',
      );
      if (barcodeDetectorCtor == null) {
        _emitError(
          'Este navegador no soporta escaneo QR en vivo con la camara. $_phoneFallbackMessage',
        );
        return;
      }

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        _emitError(
          'No fue posible acceder a la camara del navegador. $_phoneFallbackMessage',
        );
        return;
      }

      _barcodeDetector = js_util.callConstructor(
        barcodeDetectorCtor,
        <Object?>[],
      );

      final stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': {'ideal': 'environment'},
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': false,
      });

      if (_disposed) {
        _stopTracks(stream);
        return;
      }

      _mediaStream = stream;
      _videoElement.srcObject = stream;
      await _videoElement.play();

      _scanTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => unawaited(_scanCurrentFrame()),
      );
    } catch (_) {
      _emitError(
        'No se pudo abrir la camara. Verifica el permiso del navegador o accede desde tu telefono si este equipo no tiene camara.',
      );
    }
  }

  Future<void> _scanCurrentFrame() async {
    if (_disposed || _scanInFlight || _barcodeDetector == null) return;
    if (_videoElement.readyState < 2) return;

    _scanInFlight = true;
    try {
      final result = await js_util.promiseToFuture<Object?>(
        js_util.callMethod<Object?>(_barcodeDetector as Object, 'detect', [
              _videoElement,
            ])
            as Object,
      );
      final decoded = js_util.dartify(result);
      if (decoded is! List || decoded.isEmpty) return;

      for (final item in decoded) {
        if (item is Map && item['rawValue'] is String) {
          final rawValue = (item['rawValue'] as String).trim();
          if (rawValue.isEmpty) continue;
          _scanTimer?.cancel();
          _stopCamera();
          widget.onDetected(rawValue);
          return;
        }
      }
    } catch (_) {
      _emitError('No se pudo leer el QR desde la camara.');
    } finally {
      _scanInFlight = false;
    }
  }

  void _emitError(String message) {
    if (_disposed || _reportedError) return;
    _reportedError = true;
    _scanTimer?.cancel();
    _stopCamera();
    widget.onError(message);
  }

  void _stopCamera() {
    final stream = _mediaStream;
    _mediaStream = null;
    if (stream != null) {
      _stopTracks(stream);
    }
    _videoElement.srcObject = null;
    _videoElement.pause();
  }

  void _stopTracks(html.MediaStream stream) {
    for (final track in stream.getTracks()) {
      track.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
