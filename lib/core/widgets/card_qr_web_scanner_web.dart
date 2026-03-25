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
  static const List<String> _jsQrUrls = [
    'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js',
    'https://unpkg.com/jsqr@1.4.0/dist/jsQR.js',
  ];
  static Future<bool>? _jsQrLoadFuture;

  late final String _viewType;
  late final html.VideoElement _videoElement;
  late final html.CanvasElement _canvasElement;
  late final html.CanvasRenderingContext2D _canvasContext;
  html.MediaStream? _mediaStream;
  Object? _barcodeDetector;
  Timer? _scanTimer;
  bool _disposed = false;
  bool _scanInFlight = false;
  bool _reportedError = false;
  bool _useJsQrFallback = false;

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
    _canvasElement = html.CanvasElement();
    _canvasContext = _canvasElement.context2D;

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
        final jsQrLoaded = await _ensureJsQrLoaded();
        if (!jsQrLoaded) {
          _emitError(
            'Este navegador no soporta escaneo QR en vivo con la camara. $_phoneFallbackMessage',
          );
          return;
        }
        _useJsQrFallback = true;
      } else {
        _barcodeDetector = js_util.callConstructor(
          barcodeDetectorCtor,
          <Object?>[],
        );
      }

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        _emitError(
          'No fue posible acceder a la camara del navegador. $_phoneFallbackMessage',
        );
        return;
      }

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
    if (_disposed || _scanInFlight) return;
    if (_videoElement.readyState < 2) return;

    _scanInFlight = true;
    try {
      if (_useJsQrFallback) {
        _scanWithJsQr();
      } else {
        try {
          await _scanWithBarcodeDetector();
        } catch (_) {
          final jsQrLoaded = await _ensureJsQrLoaded();
          if (!jsQrLoaded) rethrow;
          _useJsQrFallback = true;
          _scanWithJsQr();
        }
      }
    } catch (_) {
      _emitError('No se pudo leer el QR desde la camara.');
    } finally {
      _scanInFlight = false;
    }
  }

  Future<void> _scanWithBarcodeDetector() async {
    if (_barcodeDetector == null) {
      throw StateError('BarcodeDetector no disponible');
    }

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
        _handleDetected(rawValue);
        return;
      }
    }
  }

  void _scanWithJsQr() {
    final jsQr = js_util.getProperty<Object?>(html.window, 'jsQR');
    if (jsQr == null) {
      throw StateError('jsQR no disponible');
    }

    final width = _videoElement.videoWidth;
    final height = _videoElement.videoHeight;
    if (width <= 0 || height <= 0) return;

    _canvasElement
      ..width = width
      ..height = height;
    _canvasContext.drawImageScaled(
      _videoElement,
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );

    final imageData = _canvasContext.getImageData(0, 0, width, height);
    final result = js_util.callMethod<Object?>(html.window, 'jsQR', [
      imageData.data,
      width,
      height,
      js_util.jsify({'inversionAttempts': 'dontInvert'}),
    ]);
    if (result == null) return;

    final rawValue = js_util.getProperty<Object?>(result, 'data');
    if (rawValue is! String) return;

    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return;
    _handleDetected(trimmed);
  }

  void _handleDetected(String rawValue) {
    _scanTimer?.cancel();
    _stopCamera();
    widget.onDetected(rawValue);
  }

  Future<bool> _ensureJsQrLoaded() {
    final existing = js_util.getProperty<Object?>(html.window, 'jsQR');
    if (existing != null) return Future.value(true);
    final pending = _jsQrLoadFuture;
    if (pending != null) return pending;

    final completer = Completer<bool>();
    _jsQrLoadFuture = completer.future;

    Future<void> tryLoad(int index) async {
      if (_disposed) {
        if (!completer.isCompleted) completer.complete(false);
        return;
      }
      if (js_util.getProperty<Object?>(html.window, 'jsQR') != null) {
        if (!completer.isCompleted) completer.complete(true);
        return;
      }
      if (index >= _jsQrUrls.length) {
        if (!completer.isCompleted) completer.complete(false);
        return;
      }

      final script = html.ScriptElement()
        ..src = _jsQrUrls[index]
        ..async = true;

      late StreamSubscription<html.Event> loadSub;
      late StreamSubscription<html.Event> errorSub;

      loadSub = script.onLoad.listen((_) {
        loadSub.cancel();
        errorSub.cancel();
        final loaded =
            js_util.getProperty<Object?>(html.window, 'jsQR') != null;
        if (!completer.isCompleted) {
          completer.complete(loaded);
        }
      });

      errorSub = script.onError.listen((_) {
        loadSub.cancel();
        errorSub.cancel();
        unawaited(tryLoad(index + 1));
      });

      (html.document.head ?? html.document.body)?.append(script);
    }

    unawaited(tryLoad(0));
    return completer.future;
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
