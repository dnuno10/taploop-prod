import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/supabase_service.dart';
import 'core/services/auth_service.dart';
import 'core/data/app_state.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_extensions.dart';
import 'features/home/views/home_shell.dart';
import 'features/auth/views/login_view.dart';
import 'features/auth/views/legal_pages_view.dart';
// import 'features/auth/views/register_view.dart';
// import 'features/auth/views/forgot_password_view.dart';
// import 'features/auth/views/otp_view.dart';
import 'features/card/views/public_card_view.dart';

/// Global theme mode notifier
/// Test Ivanovich
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await SupabaseService.initialize();
  runApp(const TapLoopApp());
}

// ─── Router ───────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          _AuthGate(pendingNfc: state.uri.queryParameters['pendingNfc']),
    ),
    GoRoute(
      path: '/terminos',
      builder: (context, state) => const TermsAndConditionsView(),
    ),
    GoRoute(
      path: '/privacidad',
      builder: (context, state) => const PrivacyPolicyView(),
    ),
    // Flujo anterior comentado a petición del proyecto:
    // GoRoute(
    //   path: '/register',
    //   builder: (context, state) {
    //     String? pendingNfc = state.uri.queryParameters['pendingNfc'];
    //     final extra = state.extra;
    //     if (extra is Map) {
    //       pendingNfc ??= extra['pendingNfc']?.toString();
    //     }
    //     return RegisterView(pendingNfc: pendingNfc);
    //   },
    // ),
    // GoRoute(
    //   path: '/forgot-password',
    //   builder: (context, state) => const ForgotPasswordView(),
    // ),
    // GoRoute(
    //   path: '/otp-verify',
    //   builder: (context, state) {
    //     final extra = state.extra;
    //     final data = extra is Map ? extra.cast<String, String?>() : null;
    //     final email = data?['email'];
    //     if (email == null || email.isEmpty) return const LoginView();
    //     return OtpView(
    //       email: email,
    //       name: data?['name'],
    //       pendingNfc: data?['pendingNfc'],
    //     );
    //   },
    // ),
    GoRoute(
      path: '/nfc/:serial',
      builder: (context, state) {
        final serial = state.pathParameters['serial']!;
        return PublicCardView(nfcSerial: serial);
      },
    ),
    GoRoute(
      path: '/u/:userId',
      builder: (context, state) {
        final userId = state.pathParameters['userId']!;
        final via = state.uri.queryParameters['via'];
        return PublicCardView(userId: userId, via: via);
      },
    ),
    GoRoute(
      path: '/:slug',
      builder: (context, state) {
        final slug = state.pathParameters['slug']!;
        final via = state.uri.queryParameters['via'];
        return PublicCardView(slug: slug, via: via);
      },
    ),
  ],
);

// ─── App ──────────────────────────────────────────────────────────────────────

class TapLoopApp extends StatelessWidget {
  const TapLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) => MaterialApp.router(
        title: 'TapLoop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        routerConfig: _router,
      ),
    );
  }
}

// ─── Auth Gate ────────────────────────────────────────────────────────────────

class _AuthGate extends StatefulWidget {
  final String? pendingNfc;

  const _AuthGate({this.pendingNfc});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  static bool _didBootstrap = false;
  late final Future<void> _bootstrapFuture;
  StreamSubscription<AuthState>? _authSubscription;
  bool _syncingAuth = false;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _bootstrap();
    _authSubscription = SupabaseService.authStateChanges.listen(
      _handleAuthState,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _hydrateAuthenticatedState() async {
    final user = await AuthService.restoreSession();
    if (user == null) {
      appState.clear();
      return;
    }
    appState.setUser(user);
    appState.setLoadingCard(true);
    try {
      final card = await AuthService.fetchUserCard(user.id);
      appState.setCard(card);
    } finally {
      appState.setLoadingCard(false);
    }
  }

  Future<void> _bootstrap() async {
    if (_didBootstrap) return;
    _didBootstrap = true;
    appState.setLoadingUser(true);
    try {
      await _hydrateAuthenticatedState();
    } catch (_) {
      appState.setError('No se pudo restaurar la sesión.');
    } finally {
      appState.setLoadingUser(false);
    }
  }

  Future<void> _handleAuthState(AuthState state) async {
    if (_syncingAuth) return;

    if (state.event == AuthChangeEvent.signedOut) {
      appState.clear();
      return;
    }

    final shouldSync =
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.tokenRefreshed ||
        state.event == AuthChangeEvent.userUpdated;

    if (!shouldSync) return;

    _syncingAuth = true;
    try {
      await _hydrateAuthenticatedState();
    } catch (_) {
      // Preserve existing state if there is a transient auth/network issue.
    } finally {
      _syncingAuth = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        final bootstrapping =
            snapshot.connectionState != ConnectionState.done &&
            !appState.isAuthenticated;
        if (bootstrapping) return const _BootstrapView();

        return ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            if (appState.isAuthenticated) return const HomeShell();
            return LoginView(pendingNfc: widget.pendingNfc);
          },
        );
      },
    );
  }
}

class _BootstrapView extends StatelessWidget {
  const _BootstrapView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
