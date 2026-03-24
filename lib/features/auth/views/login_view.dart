import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/services/auth_service.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_layout.dart';
import '../../../core/widgets/taploop_button.dart';
import '../../../core/widgets/taploop_text_field.dart';

class LoginView extends StatefulWidget {
  final String? pendingNfc;

  const LoginView({super.key, this.pendingNfc});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final user = await AuthService.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
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
    if (mounted) setState(() => _loading = false);
  }

  String _friendlyError(String raw) {
    if (raw.contains('Invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (raw.contains('Email not confirmed')) {
      return 'Tu correo no ha sido confirmado.';
    }
    return 'No se pudo iniciar sesión. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Demo privada de plataforma para',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset(
                  'assets/images/liomont-logo.png',
                  height: 22,
                  fit: BoxFit.contain,
                ),
              ],
            ),
            const SizedBox(height: 40),
            const AuthHeader(
              title: 'Bienvenido de nuevo',
              subtitle: 'Ingresa tu correo y contraseña para iniciar sesión',
            ),
            const SizedBox(height: 32),

            TapLoopTextField(
              label: 'Correo electrónico',
              hint: 'tu@email.com',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              prefixIcon: Icon(
                Icons.mail_outline,
                size: 20,
                color: context.textMuted,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                if (!v.contains('@')) return 'Correo inválido';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TapLoopTextField(
              label: 'Contraseña',
              hint: 'Tu contraseña',
              controller: _passwordCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              prefixIcon: Icon(
                Icons.lock_outline,
                size: 20,
                color: context.textMuted,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
                return null;
              },
              onSubmitted: (_) => _onSignIn(),
            ),

            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _errorMsg!,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            TapLoopButton(
              label: 'Iniciar sesión',
              onPressed: _loading ? null : _onSignIn,
              variant: TapLoopButtonVariant.secondary,
              isLoading: _loading,
            ),
            const SizedBox(height: 18),
            Center(
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => context.push('/terminos'),
                    child: Text(
                      'Terminos y condiciones',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Text(
                    '•',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: context.textMuted,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/privacidad'),
                    child: Text(
                      'Politicas de privacidad',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Flujo anterior comentado a petición del proyecto:
            // const SizedBox(height: 24),
            // const SocialDivider(),
            // const SizedBox(height: 24),
            // GoogleSignInButton(onPressed: () {}, isLoading: false),
            // const SizedBox(height: 32),
            // Row(
            //   mainAxisAlignment: MainAxisAlignment.center,
            //   children: [
            //     Text(
            //       '¿No tienes cuenta? ',
            //       style: GoogleFonts.dmSans(
            //         fontSize: 14,
            //         color: context.textSecondary,
            //       ),
            //     ),
            //     GestureDetector(
            //       onTap: () {
            //         final pendingNfc = widget.pendingNfc;
            //         if (pendingNfc != null && pendingNfc.isNotEmpty) {
            //           context.go('/register', extra: {'pendingNfc': pendingNfc});
            //           return;
            //         }
            //         context.go('/register');
            //       },
            //       child: Text(
            //         'Regístrate gratis',
            //         style: GoogleFonts.dmSans(
            //           fontSize: 14,
            //           fontWeight: FontWeight.w700,
            //           color: AppColors.primary,
            //         ),
            //       ),
            //     ),
            //   ],
            // ),
          ],
        ),
      ),
    );
  }
}
