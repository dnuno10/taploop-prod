import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'card_qr_web_scanner_stub.dart'
    if (dart.library.html) 'card_qr_web_scanner_web.dart';
import '../data/app_state.dart';
import '../data/repositories/card_repository.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme_extensions.dart';

class CardInitialSetupState extends StatefulWidget {
  final VoidCallback? onLinked;

  const CardInitialSetupState({super.key, this.onLinked});

  @override
  State<CardInitialSetupState> createState() => _CardInitialSetupStateState();
}

class _CardInitialSetupStateState extends State<CardInitialSetupState> {
  static const String _phoneFallbackMessage =
      'Si tu computadora no tiene camara, accede desde tu telefono para usar su camara y escanear el QR.';

  MobileScannerController? _scannerController;

  bool _scannerVisible = false;
  bool _scannerPaused = false;
  bool _submitting = false;
  bool _hasProcessedScan = false;
  String? _error;
  String? _cameraError;

  bool get _usesEmbeddedScanner => !kIsWeb;

  @override
  void dispose() {
    _disposeScannerController();
    super.dispose();
  }

  Future<void> _startScanner() async {
    if (!_usesEmbeddedScanner) {
      setState(() {
        _scannerVisible = true;
        _scannerPaused = false;
        _error = null;
        _cameraError = null;
        _hasProcessedScan = false;
      });
      return;
    }

    if (_scannerController == null) {
      try {
        _scannerController = MobileScannerController(
          formats: const [BarcodeFormat.qrCode],
          facing: CameraFacing.back,
          detectionSpeed: DetectionSpeed.noDuplicates,
          returnImage: false,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _scannerVisible = true;
          _scannerPaused = true;
          _cameraError =
              'No se pudo iniciar la camara en este dispositivo o navegador. $_phoneFallbackMessage';
          _error = null;
          _hasProcessedScan = false;
        });
        return;
      }
    }

    setState(() {
      _scannerVisible = true;
      _scannerPaused = false;
      _error = null;
      _cameraError = null;
      _hasProcessedScan = false;
    });
  }

  void _closeScanner() {
    _disposeScannerController();
    setState(() {
      _scannerVisible = false;
      _scannerPaused = false;
      _submitting = false;
      _hasProcessedScan = false;
      _error = null;
      _cameraError = null;
    });
  }

  Future<void> _retryScanner() async {
    _disposeScannerController();
    setState(() {
      _scannerVisible = true;
      _scannerPaused = false;
      _cameraError = null;
      _error = null;
      _hasProcessedScan = false;
      _submitting = false;
    });
    await _startScanner();
  }

  void _disposeScannerController() {
    _scannerController?.dispose();
    _scannerController = null;
  }

  void _pauseScannerWithError(String message) {
    _disposeScannerController();
    setState(() {
      _scannerVisible = true;
      _scannerPaused = true;
      _submitting = false;
      _hasProcessedScan = true;
      _error = message;
    });
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (!_scannerVisible || _hasProcessedScan || _submitting) return;

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    await _processScannedValue(rawValue);
  }

  Future<void> _processScannedValue(String rawValue) async {
    if (_submitting) return;

    setState(() {
      _hasProcessedScan = true;
      _submitting = true;
      _error = null;
    });

    final result = await _linkCardFromInput(rawValue);
    if (!mounted) return;

    if (!result.success) {
      _pauseScannerWithError(result.message);
      return;
    }

    widget.onLinked?.call();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    setState(() {
      _scannerVisible = false;
      _scannerPaused = false;
      _submitting = false;
      _hasProcessedScan = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 20,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.bgSubtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Configuracion inicial',
                        style: GoogleFonts.dmSans(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Escanea el QR de tu tarjeta para conectar tu perfil digital.',
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _usesEmbeddedScanner
                          ? 'La vinculacion se realiza unicamente con la camara del dispositivo. Al validar el QR se enlaza la tarjeta en nfc_cards con tu usuario y, si corresponde, se crea tu digital_card para habilitar clicks, taps, visitas, leads y metricas.'
                          : 'En navegador se abrira la camara del dispositivo para escanear el QR en vivo y vincular la tarjeta.',
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'En caso de que el dispositivo no tenga camara, accede desde un dispositivo movil.',
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _CardSetupActionButton(
                      label: _scannerVisible
                          ? (_usesEmbeddedScanner
                                ? 'Escaneando QR...'
                                : 'Leyendo QR...')
                          : 'Escanear QR de tarjeta',
                      icon: Icons.qr_code_scanner_rounded,
                      filled: true,
                      onTap: _scannerVisible || _submitting
                          ? null
                          : _startScanner,
                    ),
                  ],
                ),
              ),
              Container(
                width: 320,
                height: 230,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Image.asset(
                          'assets/images/taploop-logo.png',
                          height: 24,
                        ),
                        Icon(Icons.wifi_rounded, color: context.textSecondary),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      'Activa tu perfil',
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'QR validado • NFC vinculada • Perfil digital',
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_scannerVisible) ...[
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.bgPage,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _usesEmbeddedScanner
                              ? 'Escanea el QR de la tarjeta'
                              : 'Lee el QR con la camara',
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _submitting ? null : _closeScanner,
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _usesEmbeddedScanner
                        ? 'Coloca el QR dentro del recuadro. La lectura de la camara validara la tarjeta y la vinculara automaticamente a tu cuenta.'
                        : 'Tu navegador pedira permiso para abrir la camara del dispositivo y leer el QR en tiempo real.',
                    style: GoogleFonts.dmSans(
                      color: context.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _scannerPaused
                      ? _ScannerValidationErrorState(
                          message: _error ?? 'No se pudo validar el QR.',
                          onRetry: _retryScanner,
                          onClose: _closeScanner,
                        )
                      : _usesEmbeddedScanner
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            height: 320,
                            width: double.infinity,
                            child: _scannerController == null
                                ? (_cameraError != null
                                      ? _ScannerErrorState(
                                          message: _cameraError!,
                                          onRetry: _retryScanner,
                                          onClose: _closeScanner,
                                        )
                                      : Container(
                                          color: context.bgSubtle,
                                          alignment: Alignment.center,
                                          child:
                                              const CircularProgressIndicator(),
                                        ))
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      MobileScanner(
                                        controller: _scannerController!,
                                        onDetect: _handleBarcode,
                                        errorBuilder: (context, error, child) {
                                          final message = switch (error
                                              .errorCode) {
                                            MobileScannerErrorCode
                                                .permissionDenied =>
                                              'La camara no tiene permiso. Permite el acceso a la camara para escanear el QR.',
                                            MobileScannerErrorCode
                                                .unsupported =>
                                              'Este dispositivo o navegador no soporta escaneo con camara. $_phoneFallbackMessage',
                                            _ =>
                                              error.errorDetails?.message ??
                                                  error.errorCode.message,
                                          };
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (!mounted ||
                                                    _cameraError == message) {
                                                  return;
                                                }
                                                setState(
                                                  () => _cameraError = message,
                                                );
                                              });
                                          return _ScannerErrorState(
                                            message: message,
                                            onRetry: _retryScanner,
                                            onClose: _closeScanner,
                                          );
                                        },
                                      ),
                                      IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: AppColors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          margin: const EdgeInsets.all(28),
                                        ),
                                      ),
                                      if (_submitting)
                                        Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                          alignment: Alignment.center,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(),
                                              const SizedBox(height: 14),
                                              Text(
                                                'Validando QR y vinculando tarjeta...',
                                                style: GoogleFonts.dmSans(
                                                  color: AppColors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        )
                      : Container(
                          height: 220,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: context.bgSubtle,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.borderColor),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CardQrWebScanner(
                                onDetected: _processScannedValue,
                                onError: (message) {
                                  if (!mounted) return;
                                  setState(() => _cameraError = message);
                                },
                              ),
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  margin: const EdgeInsets.all(28),
                                ),
                              ),
                              if (_submitting)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Validando QR y vinculando tarjeta...',
                                        style: GoogleFonts.dmSans(
                                          color: AppColors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                  if (_error != null && !_scannerPaused) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: GoogleFonts.dmSans(
                        color: AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_cameraError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _cameraError!,
                      style: GoogleFonts.dmSans(
                        color: AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScannerErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ScannerErrorState({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.bgSubtle,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            size: 34,
            color: AppColors.error,
          ),
          const SizedBox(height: 14),
          Text(
            'No se pudo iniciar la camara',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _ScannerActionRow(onRetry: onRetry, onClose: onClose),
        ],
      ),
    );
  }
}

class _ScannerValidationErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ScannerValidationErrorState({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.bgSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2_rounded, size: 34, color: AppColors.error),
          const SizedBox(height: 14),
          Text(
            'No se pudo validar el QR',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _ScannerActionRow(onRetry: onRetry, onClose: onClose),
        ],
      ),
    );
  }
}

class _ScannerActionRow extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ScannerActionRow({required this.onRetry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      fixedSize: const WidgetStatePropertyAll(null),
      maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 44)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonal(
          onPressed: onRetry,
          style: buttonStyle,
          child: const Text('Reintentar'),
        ),
        OutlinedButton(
          onPressed: onClose,
          style: buttonStyle,
          child: const Text('Cerrar lector'),
        ),
      ],
    );
  }
}

class _CardSetupActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  const _CardSetupActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : context.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: filled ? AppColors.primary : context.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? AppColors.white : context.textPrimary,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  color: filled ? AppColors.white : context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardLinkResult {
  final bool success;
  final String message;

  const _CardLinkResult({required this.success, required this.message});
}

Future<_CardLinkResult> _linkCardFromInput(String rawValue) async {
  final user = appState.currentUser;
  if (user == null) {
    return const _CardLinkResult(
      success: false,
      message: 'Necesitas iniciar sesion para vincular una tarjeta.',
    );
  }

  final serial = _extractNfcSerial(rawValue);
  if (serial == null) {
    return const _CardLinkResult(
      success: false,
      message: 'El QR no contiene un identificador valido de tarjeta.',
    );
  }

  try {
    final status = await CardRepository.checkNfcSerial(serial);
    if (status == 'not_found') {
      return const _CardLinkResult(
        success: false,
        message: 'No encontramos una tarjeta valida en ese QR.',
      );
    }

    if (status == 'assigned') {
      final linkedCard = await CardRepository.fetchByNfcSerial(serial);
      if (linkedCard != null && linkedCard.userId == user.id) {
        final myCard = await AuthService.fetchUserCard(user.id) ?? linkedCard;
        appState.setCard(myCard);
        return const _CardLinkResult(
          success: true,
          message: 'Esta tarjeta ya estaba vinculada a tu cuenta.',
        );
      }

      return const _CardLinkResult(
        success: false,
        message: 'Esta tarjeta ya esta vinculada a otra cuenta.',
      );
    }

    final activated = await CardRepository.activateNfcCard(serial);
    if (!activated) {
      return const _CardLinkResult(
        success: false,
        message: 'No se pudo vincular la tarjeta. Intenta de nuevo.',
      );
    }

    final card =
        await AuthService.fetchUserCard(user.id) ??
        await CardRepository.fetchByNfcSerial(serial);
    appState.setCard(card);
    return const _CardLinkResult(
      success: true,
      message: 'Tarjeta vinculada correctamente.',
    );
  } catch (_) {
    return const _CardLinkResult(
      success: false,
      message: 'Ocurrio un error al vincular la tarjeta.',
    );
  }
}

String? _extractNfcSerial(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    final idx = uri.pathSegments.lastIndexOf('nfc');
    if (idx != -1 && idx + 1 < uri.pathSegments.length) {
      final serial = uri.pathSegments[idx + 1].trim();
      if (serial.isNotEmpty) return serial;
    }
  }

  final segments = trimmed.split('/');
  final candidate = segments.isNotEmpty ? segments.last.trim() : trimmed;
  if (candidate.isEmpty) return null;

  final normalized = candidate.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return normalized.isEmpty ? null : normalized;
}
