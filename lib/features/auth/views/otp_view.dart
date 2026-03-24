import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/data/app_state.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_layout.dart';
import '../../../core/widgets/taploop_button.dart';

/// OTP verification screen — shared by login AND signup flows.
///
/// [email] — the address the code was sent to.
/// [name]  — null for login (existing user), non-null for signup (new user).
class OtpView extends StatefulWidget {
  final String email;
  final String? name;
  final String? pendingNfc;

  const OtpView({super.key, required this.email, this.name, this.pendingNfc});

  @override
  State<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<OtpView> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _resendCountdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  void _onVerify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 8) {
      setState(() => _errorMsg = 'Ingresa el código de 8 dígitos');
      return;
    }
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final user = await AuthService.verifyOtp(
        email: widget.email,
        token: code,
        name: widget.name,
      );
      if (!mounted) return;
      appState.setUser(user);
      appState.setLoadingCard(true);
      final card = await AuthService.fetchUserCard(user.id);
      if (!mounted) return;
      appState.setCard(card);
      appState.setLoadingCard(false);
      final pendingNfc = widget.pendingNfc;
      if (pendingNfc != null && pendingNfc.isNotEmpty) {
        context.go('/nfc/$pendingNfc');
      } else {
        context.go('/');
      }
    } catch (e) {
      appState.setLoadingCard(false);
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = _friendlyError(e.toString());
        });
      }
    }
  }

  Future<void> _onResend() async {
    if (_resendCountdown > 0) return;
    try {
      await AuthService.sendOtp(widget.email);
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Código reenviado. Revisa tu correo.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al reenviar el código. Intenta de nuevo.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('expired') || raw.contains('Token has expired')) {
      return 'El código expiró. Usa el botón "Reenviar código".';
    }
    if (raw.contains('invalid') ||
        raw.contains('Token not found') ||
        raw.contains('otp_error') ||
        raw.contains('OTP')) {
      return 'Código incorrecto. Verifica e inténtalo de nuevo.';
    }
    if (raw.contains('rate limit') || raw.contains('too many')) {
      return 'Demasiados intentos. Espera un momento.';
    }
    return 'Error al verificar. Intenta de nuevo.';
  }

  String _maskedEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '${name[0]}***@$domain';
    return '${name[0]}${name[1]}***@$domain';
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = widget.name == null;
    return AuthLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeader(
            title: isLogin ? 'Verifica tu correo' : 'Confirma tu cuenta',
            subtitle:
                'Ingresa el código de 8 dígitos que enviamos a\n${_maskedEmail(widget.email)}',
          ),
          const SizedBox(height: 40),

          // ── Código OTP ──────────────────────────────────────────────────
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 8,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              if (_errorMsg != null) setState(() => _errorMsg = null);
              if (v.trim().length == 8) _onVerify();
            },
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '00000000',
              hintStyle: GoogleFonts.outfit(
                fontSize: 30,
                fontWeight: FontWeight.w300,
                letterSpacing: 10,
                color: context.borderStrong,
              ),
              filled: true,
              fillColor: context.bgInput,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 20,
                horizontal: 24,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.error),
              ),
            ),
          ),

          // ── Error ────────────────────────────────────────────────────────
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _errorMsg!,
                style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Verificar ────────────────────────────────────────────────────
          TapLoopButton(
            label: 'Verificar código',
            onPressed: _loading ? null : _onVerify,
            variant: TapLoopButtonVariant.primary,
            isLoading: _loading,
          ),

          const SizedBox(height: 24),

          // ── Reenviar ─────────────────────────────────────────────────────
          Center(
            child: _resendCountdown > 0
                ? Text(
                    'Reenviar código en ${_resendCountdown}s',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  )
                : GestureDetector(
                    onTap: _onResend,
                    child: Text(
                      'Reenviar código',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 16),

          // ── Cambiar correo ───────────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: () {
                final pendingNfc = widget.pendingNfc;
                if (isLogin) {
                  if (pendingNfc != null && pendingNfc.isNotEmpty) {
                    context.go('/?pendingNfc=$pendingNfc');
                    return;
                  }
                  context.go('/');
                  return;
                }
                if (pendingNfc != null && pendingNfc.isNotEmpty) {
                  context.go('/register', extra: {'pendingNfc': pendingNfc});
                  return;
                }
                context.go('/register');
              },
              child: Text(
                '← Cambiar correo',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
