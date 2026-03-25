import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/data/app_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../main.dart' show themeModeNotifier;
import '../../auth/models/user_model.dart';
import '../../card/models/digital_card_model.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _pushNotifications = true;
  bool _emailSummary = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final user = appState.currentUser;
        final card = appState.currentCard;
        if (user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildContent(context, user, card);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    UserModel user,
    DigitalCardModel? card,
  ) {
    final displayName = (card?.name.isNotEmpty == true)
        ? card!.name
        : user.name;
    final displayRole = [
      if (card?.jobTitle.isNotEmpty == true) card!.jobTitle,
      if (card?.company.isNotEmpty == true) card!.company,
      if ((card?.jobTitle.isNotEmpty != true) &&
          (user.jobTitle?.isNotEmpty == true))
        user.jobTitle!,
      if ((card?.company.isNotEmpty != true) && user.email.isNotEmpty)
        user.email,
    ].join(' · ');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: context.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Configuración',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.borderColor),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          if (card == null) ...[
            CardInitialSetupState(onLinked: () => setState(() {})),
            const SizedBox(height: 24),
          ],
          // ─ Profile card ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: context.bgSubtle,
                  child: Text(
                    _initials(displayName),
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      if (displayRole.isNotEmpty)
                        Text(
                          displayRole,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.textMuted),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ─ Apariencia ─────────────────────────────────────
          _SettingsSection(
            title: 'Apariencia',
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeModeNotifier,
                builder: (_, mode, __) => _SettingsTile(
                  icon: mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  label: 'Modo oscuro',
                  trailing: Switch.adaptive(
                    value: mode == ThemeMode.dark,
                    onChanged: (v) => themeModeNotifier.value = v
                        ? ThemeMode.dark
                        : ThemeMode.light,
                    activeTrackColor: AppColors.primary,
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.color_lens_outlined,
                label: 'Color de acento',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: context.textMuted),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ─ Notificaciones ─────────────────────────────────
          _SettingsSection(
            title: 'Notificaciones',
            children: [
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Notificaciones push',
                trailing: Switch.adaptive(
                  value: _pushNotifications,
                  onChanged: (v) => setState(() => _pushNotifications = v),
                  activeTrackColor: AppColors.primary,
                ),
              ),
              _SettingsTile(
                icon: Icons.email_outlined,
                label: 'Resumen semanal por email',
                trailing: Switch.adaptive(
                  value: _emailSummary,
                  onChanged: (v) => setState(() => _emailSummary = v),
                  activeTrackColor: AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ─ Seguridad ──────────────────────────────────────
          _SettingsSection(
            title: 'Seguridad',
            children: [
              _SettingsTile(
                icon: Icons.lock_outlined,
                label: 'Cambiar contraseña',
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.verified_user_outlined,
                label: 'Autenticación en dos pasos',
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ─ Soporte ────────────────────────────────────────
          _SettingsSection(
            title: 'Soporte',
            children: [
              _SettingsTile(
                icon: Icons.help_outline,
                label: 'Centro de ayuda',
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.chat_bubble_outline,
                label: 'Contactar soporte',
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─ Cerrar sesión ──────────────────────────────────
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                await AuthService.signOut();
                appState.clear();
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout, size: 18, color: AppColors.error),
                    const SizedBox(width: 8),
                    Text(
                      'Cerrar sesión',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ─ Version footer ─────────────────────────────────
          Center(
            child: Column(
              children: [
                Text(
                  'TapLoop',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'v1.0.0 · 2024 TapLoop Inc.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _initials(String name) {
    final p = name.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : name[0].toUpperCase();
  }
}

// ─── Settings Section ─────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children: children.asMap().entries.map((e) {
              final isLast = e.key == children.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    Divider(color: context.borderColor, height: 1, indent: 50),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Settings Tile ────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: context.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
