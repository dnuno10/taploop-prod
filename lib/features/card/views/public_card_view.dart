import 'dart:async';
import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/data/repositories/analytics_repository.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/vcard_web_helper.dart';
import '../../../core/utils/visitor_info.dart';
import '../../../core/widgets/remote_brand_logo.dart';
import '../../../core/widgets/platform_icon.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/digital_card_model.dart';
import '../models/contact_item_model.dart';
import '../models/social_link_model.dart';
import '../models/smart_form_model.dart';
import '../utils/calendar_links.dart';

// ─── NFC serial state ─────────────────────────────────────────────────────────
enum _NfcState { loading, showCard, unassigned, notFound }

class PublicCardView extends StatefulWidget {
  final String? slug;
  final String? userId;
  final String? nfcSerial;
  final String? campaignId;

  /// 'qr' when opened from a QR scan, null/'' for regular link share
  final String? via;
  const PublicCardView({
    super.key,
    this.slug,
    this.userId,
    this.nfcSerial,
    this.campaignId,
    this.via,
  }) : assert(slug != null || userId != null || nfcSerial != null);

  @override
  State<PublicCardView> createState() => _PublicCardViewState();
}

class _PublicCardViewState extends State<PublicCardView> {
  DigitalCardModel? _card;
  bool _loading = true;
  bool _notFound = false;
  String? _errorDetail;
  bool _hydratingOrganizationLogo = false;
  // NFC-specific
  _NfcState _nfcState = _NfcState.loading;
  bool _activating = false;
  String? _activationError;

  bool get _isNfcFlow => widget.nfcSerial != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isSvgUrl(String url) {
    final normalized = url.toLowerCase().split('?').first;
    return normalized.endsWith('.svg');
  }

  Future<void> _warmCompanyLogo(String url) async {
    try {
      if (_isSvgUrl(url)) {
        final loader = SvgNetworkLoader(url);
        await svg.cache.putIfAbsent(
          loader.cacheKey(null),
          () => loader.loadBytes(null),
        );
      } else {
        await precacheImage(NetworkImage(url), context);
      }
    } catch (_) {}
  }

  Future<void> _hydrateOrganizationLogo(DigitalCardModel? card) async {
    if (card == null || card.orgId == null || card.orgId!.isEmpty) return;
    if (card.companyLogoUrl?.trim().isNotEmpty == true) return;
    if (mounted) {
      setState(() => _hydratingOrganizationLogo = true);
    }
    try {
      final orgLogoUrl = await CardRepository.fetchOrganizationLogoUrl(
        card.orgId,
      );
      if (orgLogoUrl != null && orgLogoUrl.isNotEmpty) {
        await _warmCompanyLogo(orgLogoUrl);
      }
      if (!mounted || _card?.id != card.id) return;
      if (orgLogoUrl == null || orgLogoUrl.isEmpty) {
        setState(() => _hydratingOrganizationLogo = false);
        return;
      }
      if (_card?.companyLogoUrl == orgLogoUrl) {
        setState(() => _hydratingOrganizationLogo = false);
        return;
      }
      setState(() {
        _card = _card?.copyWith(companyLogoUrl: orgLogoUrl);
        _hydratingOrganizationLogo = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _hydratingOrganizationLogo = false);
      }
    }
  }

  Future<void> _load() async {
    try {
      if (_isNfcFlow) {
        await _loadNfc();
      } else {
        DigitalCardModel? card;
        if (widget.userId != null) {
          card = await CardRepository.fetchByUserId(
            widget.userId!,
            includeOrganizationLogo: false,
          );
        } else {
          card = await CardRepository.fetchBySlug(
            widget.slug!,
            includeOrganizationLogo: false,
          );
        }
        if (mounted) {
          setState(() {
            _card = card;
            _notFound = card == null;
            _loading = false;
          });
        }
        if (card != null && card.isActive) {
          final source = (widget.via == 'qr') ? 'qr' : 'link';
          unawaited(
            AnalyticsRepository.recordVisit(
              card.id,
              source,
              campaignId: widget.campaignId,
            ),
          );
        }
        unawaited(_hydrateOrganizationLogo(card));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _notFound = true;
          _errorDetail = e.toString();
        });
      }
    }
  }

  Future<void> _loadNfc() async {
    final status = await CardRepository.checkNfcSerial(widget.nfcSerial!);
    if (!mounted) return;
    if (status == 'not_found') {
      setState(() {
        _nfcState = _NfcState.notFound;
        _loading = false;
      });
      return;
    }
    if (status == 'unassigned') {
      setState(() {
        _nfcState = _NfcState.unassigned;
        _loading = false;
      });
      return;
    }
    // assigned — load the card
    final card = await CardRepository.fetchByNfcSerial(
      widget.nfcSerial!,
      includeOrganizationLogo: false,
    );
    if (mounted) {
      setState(() {
        _card = card;
        _nfcState = _NfcState.showCard;
        _loading = false;
      });
    }
    if (card != null && card.isActive) {
      unawaited(
        AnalyticsRepository.recordVisit(
          card.id,
          'nfc',
          campaignId: widget.campaignId,
        ),
      );
    }
    unawaited(_hydrateOrganizationLogo(card));
  }

  Future<void> _activate() async {
    if (!appState.isAuthenticated) {
      final serial = Uri.encodeComponent(widget.nfcSerial!);
      context.go('/?pendingNfc=$serial');
      return;
    }
    setState(() {
      _activating = true;
      _activationError = null;
    });
    try {
      final ok = await CardRepository.activateNfcCard(widget.nfcSerial!);
      if (!mounted) return;
      if (ok) {
        // Activación exitosa — ir al dashboard
        context.go('/');
      } else {
        setState(() {
          _activationError = 'Esta tarjeta ya fue activada por otra cuenta.';
          _activating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activationError = e.toString();
          _activating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // ── NFC flows ──
    if (_isNfcFlow) {
      if (_nfcState == _NfcState.notFound) {
        return _NotFoundPage(slug: widget.nfcSerial!, errorDetail: null);
      }
      if (_nfcState == _NfcState.unassigned) {
        return _NfcActivationPage(
          serial: widget.nfcSerial!,
          isLoggedIn: appState.isAuthenticated,
          activating: _activating,
          error: _activationError,
          onActivate: _activate,
          onLogin: () => context.push('/?pendingNfc=${widget.nfcSerial}'),
        );
      }
    }

    // ── Normal slug/userId flow ──
    if (_notFound || _card == null) {
      return _NotFoundPage(
        slug: widget.slug ?? widget.nfcSerial ?? widget.userId ?? '',
        errorDetail: _errorDetail,
      );
    }
    if (!_card!.isActive) {
      return _CardDeactivatedPage(
        message: _card!.deactivationReason?.trim().isNotEmpty == true
            ? _card!.deactivationReason!
            : 'Tarjeta digital desactivada por seguridad',
      );
    }
    return _CardPage(
      card: _card!,
      campaignId: widget.campaignId,
      reserveCompanyLogoSpace: _hydratingOrganizationLogo,
    );
  }
}

// ─── Theme helpers (mirrors DigitalProfilePreview logic exactly) ──────────────

Color _cardAccent(DigitalCardModel card) => card.primaryColor;

Color _cardBgBase(DigitalCardModel card) => card.bgColor ?? Colors.white;

Color _cardTextColor(DigitalCardModel card) =>
    card.textColorIsDark ? const Color(0xFF0D0D0D) : Colors.white;

/// Mirrors _ScreenContent._buildBgDecoration from digital_profile_preview.dart
BoxDecoration _buildPageDecoration(DigitalCardModel card) {
  final bgBase = card.bgColor ?? _cardBgBase(card);
  switch (card.bgStyle) {
    case CardBgStyle.gradient:
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgBase, card.bgColorEnd ?? _darkenColor(bgBase)],
        ),
      );
    case CardBgStyle.mesh:
      return BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.2, -0.6),
          radius: 1.6,
          colors: [
            card.bgColorEnd ?? Colors.white.withValues(alpha: 0.45),
            bgBase,
          ],
        ),
      );
    default:
      return BoxDecoration(color: bgBase);
  }
}

class _CardDeactivatedPage extends StatelessWidget {
  final String message;

  const _CardDeactivatedPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 42,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Esta tarjeta no se encuentra disponible temporalmente.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _darkenColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
}

class _StripePainter extends CustomPainter {
  final Color bgColor;
  const _StripePainter(this.bgColor);

  @override
  void paint(Canvas canvas, Size size) {
    final isDark =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = size.width * 0.025;
    final gap = size.width * 0.1;
    for (double i = -size.height; i < size.width + size.height; i += gap) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.bgColor != bgColor;
}

// ─── Card Page ────────────────────────────────────────────────────────────────

Widget _buildCardHeader(
  DigitalCardModel card, {
  bool reserveCompanyLogoSpace = false,
}) {
  switch (card.layoutStyle) {
    case CardLayoutStyle.banner:
      return _BannerHeader(
        card: card,
        reserveCompanyLogoSpace: reserveCompanyLogoSpace,
      );
    default:
      return _HeroHeader(
        card: card,
        reserveCompanyLogoSpace: reserveCompanyLogoSpace,
      );
  }
}

class _CardPage extends StatelessWidget {
  final DigitalCardModel card;
  final String? campaignId;
  final bool reserveCompanyLogoSpace;

  const _CardPage({
    required this.card,
    this.campaignId,
    this.reserveCompanyLogoSpace = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleContacts = card.contactItems.where((c) => c.isVisible).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final visibleSocials = card.socialLinks.where((s) => s.isVisible).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final accent = _cardAccent(card);
    final textCol = _cardTextColor(card);
    final bgBase = card.bgColor ?? _cardBgBase(card);

    final scrollView = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildCardHeader(
            card,
            reserveCompanyLogoSpace: reserveCompanyLogoSpace,
          ),
        ),
        SliverToBoxAdapter(
          child: _SaveContactSection(
            card: card,
            contacts: visibleContacts,
            socials: visibleSocials,
            accent: accent,
          ),
        ),
        if (visibleContacts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Contacto', textColor: textCol),
          ),
          SliverToBoxAdapter(
            child: _ContactSection(
              // ─── Hero Header ──────────────────────────────────────────────────────────────
              items: visibleContacts,
              accent: accent,
              textColor: textCol,
              cardId: card.id,
              campaignId: campaignId,
            ),
          ),
        ],
        if (visibleSocials.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Redes sociales', textColor: textCol),
          ),
          SliverToBoxAdapter(
            child: _SocialSection(
              links: visibleSocials,
              accent: accent,
              textColor: textCol,
              cardId: card.id,
              campaignId: campaignId,
            ),
          ),
        ],
        if (card.calendarEnabled) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Agenda una reunión',
              textColor: textCol,
            ),
          ),
          SliverToBoxAdapter(
            child: _CalendarButton(
              url: card.calendarUrl!,
              accent: accent,
              textColor: textCol,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: _FormsSection(
            card: card,
            accent: accent,
            textColor: textCol,
            campaignId: campaignId,
          ),
        ),
        SliverToBoxAdapter(
          child: _Footer(card: card, accent: accent),
        ),
      ],
    );

    if (card.bgStyle == CardBgStyle.stripes) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: bgBase),
            CustomPaint(painter: _StripePainter(bgBase)),
            scrollView,
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: _buildPageDecoration(card),
        child: scrollView,
      ),
    );
  }
}

// ─── Hero Header ──────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final DigitalCardModel card;
  final bool reserveCompanyLogoSpace;

  const _HeroHeader({required this.card, this.reserveCompanyLogoSpace = false});

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccent(card);
    final textCol = _cardTextColor(card);
    final subCol = textCol.withValues(alpha: 0.65);
    final isCentered = card.layoutStyle != CardLayoutStyle.leftAligned;

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: isCentered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  // Logo de empresa (primero)
                  if ((card.companyLogoUrl?.isNotEmpty ?? false) ||
                      reserveCompanyLogoSpace)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _PublicCompanyLogo(
                        imageUrl: card.companyLogoUrl,
                        maxWidth: 160,
                        height: 56,
                      ),
                    ),
                  // Avatar del usuario
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.2),
                      border: Border.all(color: accent, width: 2.5),
                    ),
                    child: ClipOval(
                      child: card.profilePhotoUrl != null
                          ? Image.network(
                              card.profilePhotoUrl!,
                              fit: BoxFit.cover,
                              width: 104,
                              height: 104,
                            )
                          : Center(
                              child: Text(
                                _initials(card.name),
                                style: GoogleFonts.outfit(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Nombre
                  Text(
                    card.name,
                    textAlign: isCentered ? TextAlign.center : TextAlign.left,
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: textCol,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Puesto
                  Text(
                    card.jobTitle,
                    textAlign: isCentered ? TextAlign.center : TextAlign.left,
                    style: GoogleFonts.dmSans(fontSize: 15, color: subCol),
                  ),
                  // Compañía
                  if (card.company.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      card.company,
                      textAlign: isCentered ? TextAlign.center : TextAlign.left,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: subCol,
                      ),
                    ),
                  ],
                  if (card.bio != null && card.bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        card.bio!,
                        textAlign: isCentered
                            ? TextAlign.center
                            : TextAlign.left,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: subCol,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicCompanyLogo extends StatelessWidget {
  final String? imageUrl;
  final double maxWidth;
  final double height;

  const _PublicCompanyLogo({
    required this.imageUrl,
    required this.maxWidth,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        width: maxWidth,
        height: height,
        child: imageUrl == null || imageUrl!.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
              )
            : RemoteBrandLogo(
                imageUrl: imageUrl!,
                width: maxWidth,
                height: height,
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}

// ─── Banner Header ────────────────────────────────────────────────────────────

class _BannerHeader extends StatelessWidget {
  final DigitalCardModel card;
  final bool reserveCompanyLogoSpace;

  const _BannerHeader({
    required this.card,
    this.reserveCompanyLogoSpace = false,
  });

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccent(card);
    final textCol = _cardTextColor(card);
    final subCol = textCol.withValues(alpha: 0.65);

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo de empresa (primero en su propio column)
                  if ((card.companyLogoUrl?.isNotEmpty ?? false) ||
                      reserveCompanyLogoSpace)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _PublicCompanyLogo(
                        imageUrl: card.companyLogoUrl,
                        maxWidth: 140,
                        height: 56,
                      ),
                    ),
                  // Row con avatar (izquierda) y datos (derecha)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar del usuario (izquierda)
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.2),
                          border: Border.all(color: accent, width: 2.5),
                        ),
                        child: ClipOval(
                          child: card.profilePhotoUrl != null
                              ? Image.network(
                                  card.profilePhotoUrl!,
                                  fit: BoxFit.cover,
                                  width: 80,
                                  height: 80,
                                )
                              : Center(
                                  child: Text(
                                    _initials(card.name),
                                    style: GoogleFonts.outfit(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Datos (derecha)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Nombre
                            Text(
                              card.name,
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: textCol,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // Puesto
                            Text(
                              card.jobTitle,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: subCol,
                              ),
                            ),
                            // Compañía
                            if (card.company.isNotEmpty) ...[
                              Text(
                                card.company,
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: subCol,
                                ),
                              ),
                            ],
                            // Biografía
                            if (card.bio != null && card.bio!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                card.bio!,
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: subCol,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color textColor;
  const _SectionHeader({required this.title, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor.withValues(alpha: 0.5),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ─── Save Contact ────────────────────────────────────────────────────────────

class _SaveContactSection extends StatefulWidget {
  final DigitalCardModel card;
  final List<ContactItemModel> contacts;
  final List<SocialLinkModel> socials;
  final Color accent;

  const _SaveContactSection({
    required this.card,
    required this.contacts,
    required this.socials,
    required this.accent,
  });

  @override
  State<_SaveContactSection> createState() => _SaveContactSectionState();
}

class _SaveContactSectionState extends State<_SaveContactSection> {
  bool _saving = false;

  Future<void> _saveVCard() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final fileName = _buildVCardFileName(widget.card.name);
      final bytes = Uint8List.fromList(
        utf8.encode(
          await _buildVCard(
            card: widget.card,
            contacts: widget.contacts,
            socials: widget.socials,
          ),
        ),
      );

      final result = await _persistVCard(fileName, bytes);
      if (!mounted || !result.success) return;

      unawaited(
        AnalyticsRepository.recordInteraction(
          cardId: widget.card.id,
          source: 'contact',
        ),
      );

      TapLoopToast.show(
        context,
        _downloadSuccessMessage(result),
        TapLoopToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No fue posible generar la vCard: $error',
        TapLoopToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<_VCardPersistResult> _persistVCard(
    String fileName,
    Uint8List bytes,
  ) async {
    const extension = 'vcf';
    const mimeType = 'text/vcard';

    if (kIsWeb) {
      final webAction = await presentVCardOnWeb(
        fileName: '$fileName.$extension',
        bytes: bytes,
        mimeType: mimeType,
      );
      if (webAction != null) {
        return _VCardPersistResult(success: true, webAction: webAction);
      }

      final path = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        fileExtension: extension,
        mimeType: MimeType.custom,
        customMimeType: mimeType,
      );
      return _VCardPersistResult(
        success: path.isNotEmpty,
        webAction: 'downloaded',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        {
          final path = await FileSaver.instance.saveAs(
            name: fileName,
            bytes: bytes,
            fileExtension: extension,
            mimeType: MimeType.custom,
            customMimeType: mimeType,
          );
          return _VCardPersistResult(success: path?.isNotEmpty == true);
        }
      default:
        {
          final path = await FileSaver.instance.saveFile(
            name: fileName,
            bytes: bytes,
            fileExtension: extension,
            mimeType: MimeType.custom,
            customMimeType: mimeType,
          );
          return _VCardPersistResult(success: path.isNotEmpty);
        }
    }
  }

  String _downloadSuccessMessage(_VCardPersistResult result) {
    if (kIsWeb) {
      if (result.webAction == 'opened') {
        return 'La vCard se abrió en la app disponible del dispositivo.';
      }
      return 'La vCard se descargó en tu dispositivo.';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'La vCard está lista para guardarse en Archivos.';
      case TargetPlatform.android:
        return 'La vCard está lista para guardarse en tu dispositivo.';
      default:
        return 'La vCard se generó correctamente.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(widget.accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111827);
    final badgeColor = foreground.withValues(alpha: 0.14);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: widget.accent,
            borderRadius: BorderRadius.circular(14),
            elevation: 0,
            child: InkWell(
              onTap: _saving ? null : _saveVCard,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: badgeColor,
                      ),
                      child: Icon(
                        _saving
                            ? Icons.hourglass_top_rounded
                            : Icons.download_rounded,
                        size: 20,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _saving ? 'Generando contacto...' : 'Guardar contacto',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VCardPersistResult {
  final bool success;
  final String? webAction;

  const _VCardPersistResult({required this.success, this.webAction});
}

String _buildVCardFileName(String name) {
  final sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  final compact = sanitized
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (compact.isEmpty) return 'contacto_taploop';
  return 'contacto_$compact';
}

Future<String> _buildVCard({
  required DigitalCardModel card,
  required List<ContactItemModel> contacts,
  required List<SocialLinkModel> socials,
}) async {
  final lines = <String>[
    'BEGIN:VCARD',
    'VERSION:3.0',
    'FN:${_escapeVCardValue(card.name)}',
  ];

  final splitName = _splitFullName(card.name);
  lines.add(
    'N:${_escapeVCardValue(splitName.lastName)};${_escapeVCardValue(splitName.firstName)};;;',
  );

  if (card.company.trim().isNotEmpty) {
    lines.add('ORG:${_escapeVCardValue(card.company)}');
  }
  if (card.jobTitle.trim().isNotEmpty) {
    lines.add('TITLE:${_escapeVCardValue(card.jobTitle)}');
  }

  final photoUrl = card.profilePhotoUrl?.trim();
  if (photoUrl != null && photoUrl.isNotEmpty) {
    lines.addAll(await _buildVCardPhotoLines(photoUrl));
  }

  final seenPhoneNumbers = <String>{};
  final seenEmails = <String>{};
  final seenUrls = <String>{};
  var urlIndex = 1;

  for (final item in contacts) {
    final value = item.value.trim();
    if (value.isEmpty) continue;

    switch (item.type) {
      case ContactType.phone:
        final phone = _normalizePhoneForVCard(value);
        if (phone.isEmpty || !seenPhoneNumbers.add(phone)) continue;
        lines.add('TEL;TYPE=CELL,VOICE:$phone');
        break;
      case ContactType.whatsapp:
        final phone = _normalizePhoneForVCard(value);
        if (phone.isNotEmpty && seenPhoneNumbers.add(phone)) {
          lines.add('TEL;TYPE=CELL,VOICE:$phone');
        }
        final whatsappUrl = _normalizeWhatsappUrl(value);
        if (whatsappUrl.isNotEmpty && seenUrls.add(whatsappUrl)) {
          _appendVCardUrl(
            lines: lines,
            index: urlIndex++,
            url: whatsappUrl,
            label: 'WhatsApp',
            type: 'OTHER',
          );
        }
        break;
      case ContactType.email:
        final email = value.toLowerCase();
        if (!seenEmails.add(email)) continue;
        lines.add('EMAIL;TYPE=INTERNET:$email');
        break;
      case ContactType.address:
        lines.add('ADR;TYPE=WORK:;;${_escapeVCardValue(value)};;;;');
        break;
      case ContactType.website:
        final url = _normalizeUrl(value);
        if (url.isEmpty || !seenUrls.add(url)) continue;
        final label = _labelForUrl(url, fallbackLabel: item.displayLabel);
        _appendVCardUrl(
          lines: lines,
          index: urlIndex++,
          url: url,
          label: label,
          type: _vCardUrlTypeForLabel(label),
        );
        break;
    }
  }

  for (final social in socials) {
    final url = _normalizeUrl(social.url);
    if (url.isEmpty || !seenUrls.add(url)) continue;
    final label = _labelForUrl(url, fallbackLabel: social.label);
    _appendVCardUrl(
      lines: lines,
      index: urlIndex++,
      url: url,
      label: label,
      type: _vCardUrlTypeForLabel(label),
    );
  }

  if (card.publicUrl.trim().isNotEmpty && seenUrls.add(card.publicUrl.trim())) {
    _appendVCardUrl(
      lines: lines,
      index: urlIndex++,
      url: card.publicUrl.trim(),
      label: 'Tarjeta digital',
      type: 'OTHER',
    );
  }

  final noteParts = <String>[];
  if (card.bio?.trim().isNotEmpty == true) {
    noteParts.add(card.bio!.trim());
  }
  for (final social in socials) {
    final url = _normalizeUrl(social.url);
    if (url.isEmpty) continue;
    noteParts.add('${social.label}: $url');
  }

  if (noteParts.isNotEmpty) {
    lines.add('NOTE:${_escapeVCardValue(noteParts.join(' | '))}');
  }

  final revisionDate = (card.updatedAt ?? DateTime.now())
      .toUtc()
      .toIso8601String();
  lines.add('REV:$revisionDate');
  lines.add('END:VCARD');

  return '${lines.join('\r\n')}\r\n';
}

Future<List<String>> _buildVCardPhotoLines(String imageUrl) async {
  try {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) return const [];

    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final imageBytes = response.bodyBytes;
    if (imageBytes.isEmpty) return const [];

    final mediaType = _resolveImageMediaType(
      contentTypeHeader: response.headers['content-type'],
      imageUrl: imageUrl,
    );
    final typeSegment = mediaType.vCardType.isNotEmpty
        ? ';TYPE=${mediaType.vCardType}'
        : '';
    final encoded = base64Encode(imageBytes);

    return _foldVCardLine('PHOTO;ENCODING=b$typeSegment:$encoded');
  } catch (_) {
    return const [];
  }
}

List<String> _foldVCardLine(String line, {int maxLineLength = 75}) {
  if (line.length <= maxLineLength) return [line];

  final folded = <String>[];
  var start = 0;
  var isFirstLine = true;

  while (start < line.length) {
    final availableLength = isFirstLine ? maxLineLength : maxLineLength - 1;
    final end = (start + availableLength).clamp(0, line.length);
    final chunk = line.substring(start, end);
    folded.add(isFirstLine ? chunk : ' $chunk');
    start = end;
    isFirstLine = false;
  }

  return folded;
}

({String vCardType}) _resolveImageMediaType({
  required String? contentTypeHeader,
  required String imageUrl,
}) {
  final normalizedHeader = contentTypeHeader
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  final normalizedUrl = imageUrl.toLowerCase().split('?').first;

  if (normalizedHeader != null && normalizedHeader.isNotEmpty) {
    final typeFromHeader = _vCardImageTypeFromMime(normalizedHeader);
    if (typeFromHeader != null) {
      return (vCardType: typeFromHeader);
    }
  }

  if (normalizedUrl.endsWith('.jpg') || normalizedUrl.endsWith('.jpeg')) {
    return (vCardType: 'JPEG');
  }
  if (normalizedUrl.endsWith('.png')) {
    return (vCardType: 'PNG');
  }
  if (normalizedUrl.endsWith('.gif')) {
    return (vCardType: 'GIF');
  }
  if (normalizedUrl.endsWith('.webp')) {
    return (vCardType: 'WEBP');
  }

  return (vCardType: '');
}

String? _vCardImageTypeFromMime(String mimeType) {
  switch (mimeType) {
    case 'image/jpeg':
    case 'image/jpg':
      return 'JPEG';
    case 'image/png':
      return 'PNG';
    case 'image/gif':
      return 'GIF';
    case 'image/webp':
      return 'WEBP';
    default:
      return null;
  }
}

void _appendVCardUrl({
  required List<String> lines,
  required int index,
  required String url,
  required String label,
  String? type,
}) {
  final normalizedType = type?.trim().isNotEmpty == true
      ? ';TYPE=${_escapeVCardType(type!)}'
      : '';
  final escapedUrl = _escapeVCardValue(url);
  lines.add('item$index.URL$normalizedType:$escapedUrl');
  lines.add('item$index.X-ABLabel:${_escapeVCardValue(label)}');
}

String _escapeVCardValue(String value) {
  return value
      .trim()
      .replaceAll(r'\', r'\\')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,');
}

String _escapeVCardType(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

String _normalizePhoneForVCard(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  final hasPlus = raw.startsWith('+');
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return '';
  return hasPlus ? '+$digits' : digits;
}

String _normalizeWhatsappUrl(String value) {
  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return '';
  return 'https://wa.me/$digits';
}

String _normalizeUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }
  return 'https://$raw';
}

String _labelForUrl(String url, {String? fallbackLabel}) {
  final inferred = _platformLabelFromUrl(url);
  if (inferred != null) return inferred;
  final fallback = fallbackLabel?.trim();
  if (fallback != null && fallback.isNotEmpty) return fallback;
  return 'Sitio web';
}

String? _platformLabelFromUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.contains('linkedin.com')) return 'LinkedIn';
  if (host.contains('instagram.com')) return 'Instagram';
  if (host.contains('facebook.com') || host == 'fb.com') return 'Facebook';
  if (host.contains('tiktok.com')) return 'TikTok';
  if (host == 'x.com' || host.contains('twitter.com')) return 'X';
  if (host.contains('youtube.com') || host.contains('youtu.be')) {
    return 'YouTube';
  }
  if (host.contains('github.com')) return 'GitHub';
  if (host.contains('calendly.com')) return 'Calendly';
  if (host.contains('wa.me') || host.contains('whatsapp.com')) {
    return 'WhatsApp';
  }
  return null;
}

String _vCardUrlTypeForLabel(String label) {
  switch (label.toLowerCase()) {
    case 'linkedin':
    case 'instagram':
    case 'facebook':
    case 'tiktok':
    case 'x':
    case 'youtube':
    case 'github':
    case 'calendly':
    case 'whatsapp':
      return label;
    default:
      return 'WORK';
  }
}

({String firstName, String lastName}) _splitFullName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    return (firstName: '', lastName: '');
  }

  final parts = normalized.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return (firstName: parts.first, lastName: '');
  }

  return (firstName: parts.first, lastName: parts.sublist(1).join(' '));
}

// ─── Contact Section ──────────────────────────────────────────────────────────

class _ContactSection extends StatelessWidget {
  final List<ContactItemModel> items;
  final Color accent;
  final Color textColor;
  final String cardId;
  final String? campaignId;
  const _ContactSection({
    required this.items,
    required this.accent,
    required this.textColor,
    required this.cardId,
    this.campaignId,
  });

  Future<void> _launchFromTap(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    try {
      await launchUrl(uri, mode: mode, webOnlyWindowName: '_self');
    } catch (error) {
      debugPrint('[PublicCard] contact launch error for $uri: $error');
    }
  }

  Future<void> _handleTap(ContactItemModel item) async {
    final Uri uri;
    switch (item.type) {
      case ContactType.phone:
        uri = Uri(scheme: 'tel', path: item.value);
        break;
      case ContactType.whatsapp:
        final cleaned = item.value.replaceAll(RegExp(r'\D'), '');
        uri = Uri.parse('https://wa.me/$cleaned');
        break;
      case ContactType.email:
        uri = Uri(scheme: 'mailto', path: item.value);
        break;
      case ContactType.address:
        uri = Uri.parse(
          'https://maps.google.com/?q=${Uri.encodeComponent(item.value)}',
        );
        break;
      case ContactType.website:
        uri = Uri.parse(
          item.value.startsWith('http') ? item.value : 'https://${item.value}',
        );
        break;
    }
    final launchFuture = _launchFromTap(uri);
    unawaited(
      AnalyticsRepository.recordInteraction(
        cardId: cardId,
        source: 'contact',
        campaignId: campaignId,
        contactItemId: item.id,
      ),
    );
    await launchFuture;
  }

  @override
  Widget build(BuildContext context) {
    final tileBg = textColor.withValues(alpha: 0.04);
    final tileBorder = textColor.withValues(alpha: 0.10);
    final subText = textColor.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _handleTap(item),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tileBorder),
                      ),
                      child: Row(
                        children: [
                          PlatformIcon.contact(contactType: item.type),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.displayLabel,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: subText,
                                  ),
                                ),
                                Text(
                                  item.value,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 13,
                            color: textColor.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Social Section ───────────────────────────────────────────────────────────

class _SocialSection extends StatelessWidget {
  final List<SocialLinkModel> links;
  final Color accent;
  final Color textColor;
  final String cardId;
  final String? campaignId;
  const _SocialSection({
    required this.links,
    required this.accent,
    required this.textColor,
    required this.cardId,
    this.campaignId,
  });

  Future<void> _launchFromTap(Uri uri) async {
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
    } catch (error) {
      debugPrint('[PublicCard] social launch error for $uri: $error');
    }
  }

  Future<void> _openUrl(SocialLinkModel link) async {
    final uri = Uri.parse(
      link.url.startsWith('http') ? link.url : 'https://${link.url}',
    );
    final launchFuture = _launchFromTap(uri);
    unawaited(
      AnalyticsRepository.recordInteraction(
        cardId: cardId,
        source: 'social',
        campaignId: campaignId,
        socialLinkId: link.id,
      ),
    );
    await launchFuture;
  }

  String _shortHandle(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final handle = segments.last;
        return handle.startsWith('@') ? handle : '@$handle';
      }
    } catch (_) {}
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final tileBg = textColor.withValues(alpha: 0.04);
    final tileBorder = textColor.withValues(alpha: 0.10);
    final subText = textColor.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          children: [
            for (final link in links)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _openUrl(link),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tileBorder),
                      ),
                      child: Row(
                        children: [
                          PlatformIcon.social(platform: link.platform),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  link.label,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  _shortHandle(link.url),
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: subText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 13,
                            color: textColor.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final DigitalCardModel card;
  final Color accent;
  const _Footer({required this.card, required this.accent});

  @override
  Widget build(BuildContext context) {
    final textCol = _cardTextColor(card);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 48),
      child: Center(
        child: Column(
          children: [
            Divider(color: textCol.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('https://liomont.taploop.com.mx');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Creado con ',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: textCol.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    'TapLoop',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Calendar Button ─────────────────────────────────────────────────────────

class _CalendarButton extends StatelessWidget {
  final String url;
  final Color accent;
  final Color textColor;
  const _CalendarButton({
    required this.url,
    required this.accent,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final links = parseCalendarLinks(url);

    Future<void> openProvider(CalendarProviderType provider) async {
      final rawUrl = links[provider];
      if (rawUrl == null || rawUrl.trim().isEmpty) return;
      final uri = Uri.parse(normalizeCalendarUrl(rawUrl));
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    Future<void> handleTap() async {
      if (links.isEmpty) return;
      if (links.length == 1) {
        await openProvider(links.keys.first);
        return;
      }

      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecciona proveedor',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...links.keys.map(
                    (provider) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(provider.label),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await openProvider(provider);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: accent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: handleTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Agendar reunión',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Forms Section ────────────────────────────────────────────────────────────

class _FormsSection extends StatefulWidget {
  final DigitalCardModel card;
  final Color accent;
  final Color textColor;
  final String? campaignId;
  const _FormsSection({
    required this.card,
    required this.accent,
    required this.textColor,
    this.campaignId,
  });

  @override
  State<_FormsSection> createState() => _FormsSectionState();
}

class _FormsSectionState extends State<_FormsSection> {
  List<SmartFormModel> _forms = const [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadForms();
  }

  Future<void> _loadForms() async {
    try {
      final forms = await CardRepository.fetchSmartForms(widget.card.id);
      final activeForms = forms.where((f) => f.isActive).toList();
      if (!mounted) return;
      setState(() {
        _forms = activeForms.isNotEmpty ? activeForms : forms;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_loadFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Text(
          'No se pudieron cargar los formularios dinámicos.',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: widget.textColor.withValues(alpha: 0.65),
          ),
        ),
      );
    }
    if (_forms.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: 'Formularios', textColor: widget.textColor),
            for (final form in _forms)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FormCard(
                  form: form,
                  card: widget.card,
                  accent: widget.accent,
                  textColor: widget.textColor,
                  campaignId: widget.campaignId,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatefulWidget {
  final SmartFormModel form;
  final DigitalCardModel card;
  final Color accent;
  final Color textColor;
  final String? campaignId;
  const _FormCard({
    required this.form,
    required this.card,
    required this.accent,
    required this.textColor,
    this.campaignId,
  });

  @override
  State<_FormCard> createState() => _FormCardState();
}

class _FormCardState extends State<_FormCard> {
  bool _expanded = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _alreadySubmittedOnDevice = false;
  bool _checkingDeviceState = true;
  final Map<String, TextEditingController> _ctrl = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.form.fields) {
      _ctrl[f.id] = TextEditingController();
    }
    _loadDeviceSubmissionState();
  }

  Future<void> _loadDeviceSubmissionState() async {
    final exists = await hasLocalLeadSubmission(
      cardId: widget.card.id,
      formId: widget.form.id,
    );
    if (!mounted) return;
    setState(() {
      _alreadySubmittedOnDevice = exists;
      _checkingDeviceState = false;
      if (exists) {
        _submitted = true;
      }
    });
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  SmartFormFieldModel? _referenceNameField(List<SmartFormFieldModel> fields) {
    for (final field in fields) {
      if (field.fieldType == SmartFormFieldType.text) {
        return field;
      }
    }

    for (final field in fields) {
      if (field.label.toLowerCase().contains('nombre')) {
        return field;
      }
    }

    return fields.isNotEmpty ? fields.first : null;
  }

  Future<void> _submit() async {
    if (_alreadySubmittedOnDevice) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'Este dispositivo ya envió este formulario.',
          TapLoopToastType.warning,
        );
      }
      return;
    }

    final fields = widget.form.fields;
    // Validate required
    for (final f in fields) {
      if (f.isRequired && (_ctrl[f.id]?.text.trim().isEmpty ?? true)) {
        TapLoopToast.show(
          context,
          'Por favor completa: ${f.label}',
          TapLoopToastType.error,
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final formData = {
        for (final f in fields) f.label: _ctrl[f.id]!.text.trim(),
      };
      final deviceId = await getStableVisitorId();
      if (deviceId != null && deviceId.isNotEmpty) {
        formData['_client_device_id'] = deviceId;
      }
      final nameField = _referenceNameField(fields);
      final name = nameField == null
          ? ''
          : (_ctrl[nameField.id]?.text.trim() ?? '');
      final email = fields
          .where(
            (f) =>
                f.fieldType == SmartFormFieldType.email ||
                f.label.toLowerCase().contains('correo'),
          )
          .map((f) => _ctrl[f.id]?.text.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull;
      final phone = fields
          .where(
            (f) =>
                f.fieldType == SmartFormFieldType.phone ||
                f.label.toLowerCase().contains('tel') ||
                f.label.toLowerCase().contains('cel'),
          )
          .map((f) => _ctrl[f.id]?.text.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull;
      final company = fields
          .where((f) => f.label.toLowerCase().contains('empresa'))
          .map((f) => _ctrl[f.id]?.text.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull;

      await LeadRepository.submitFormLead(
        cardId: widget.card.id,
        formType: widget.form.id,
        name: name.isEmpty ? 'Anónimo' : name,
        campaignId: widget.campaignId,
        email: email,
        phone: phone,
        company: company,
        formData: formData,
      );
      await AnalyticsRepository.recordInteraction(
        cardId: widget.card.id,
        source: 'form',
        campaignId: widget.campaignId,
        smartFormId: widget.form.id,
      );
      await markLocalLeadSubmission(
        cardId: widget.card.id,
        formId: widget.form.id,
      );
      if (mounted) {
        setState(() {
          _submitted = true;
          _alreadySubmittedOnDevice = true;
          _submitting = false;
        });
      }
    } catch (e) {
      debugPrint('[PublicCardView] submit form error: $e');
      if (mounted) {
        setState(() => _submitting = false);
        TapLoopToast.show(
          context,
          'Error al enviar. Intenta de nuevo.',
          TapLoopToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final textColor = widget.textColor;
    final tileBg = textColor.withValues(alpha: 0.04);
    final tileBorder = textColor.withValues(alpha: 0.12);

    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tileBorder),
      ),
      child: Column(
        children: [
          // Header row — tap to expand/collapse
          InkWell(
            onTap: _checkingDeviceState || _alreadySubmittedOnDevice
                ? null
                : () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.form.name,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _alreadySubmittedOnDevice
                          ? Icons.check_circle_outline_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_alreadySubmittedOnDevice)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Este dispositivo ya llenó este formulario.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ),
          // Expanded form body
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded && !_alreadySubmittedOnDevice
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _submitted
                        ? _SuccessMessage(accent: accent)
                        : _FormBody(
                            fields: widget.form.fields,
                            ctrl: _ctrl,
                            accent: accent,
                            textColor: textColor,
                            submitting: _submitting,
                            onSubmit: _submit,
                          ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SuccessMessage extends StatelessWidget {
  final Color accent;
  const _SuccessMessage({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 40, color: accent),
          const SizedBox(height: 10),
          Text(
            '¡Formulario enviado!',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nos pondremos en contacto contigo pronto.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: accent.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FormBody extends StatelessWidget {
  static const int _maxFieldLength = 200;
  final List<SmartFormFieldModel> fields;
  final Map<String, TextEditingController> ctrl;
  final Color accent;
  final Color textColor;
  final bool submitting;
  final VoidCallback onSubmit;
  const _FormBody({
    required this.fields,
    required this.ctrl,
    required this.accent,
    required this.textColor,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final borderCol = textColor.withValues(alpha: 0.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in fields) ...[
          _buildField(f, borderCol, textColor),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        Material(
          color: accent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: submitting ? null : onSubmit,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Enviar',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    SmartFormFieldModel field,
    Color borderCol,
    Color textColor,
  ) {
    final label = field.label;
    final required = field.isRequired;
    final controller = ctrl[field.id]!;

    InputDecoration decoration = InputDecoration(
      labelText: required ? '$label *' : label,
      hintText: field.placeholder,
      counterText: '',
      labelStyle: GoogleFonts.dmSans(
        fontSize: 13,
        color: textColor.withValues(alpha: 0.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderCol),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderCol),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: textColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      filled: true,
      fillColor: textColor.withValues(alpha: 0.04),
    );

    if (field.fieldType == SmartFormFieldType.textarea) {
      return TextField(
        controller: controller,
        maxLines: 3,
        keyboardType: TextInputType.multiline,
        inputFormatters: _inputFormattersForField(field.fieldType),
        maxLength: _maxFieldLength,
        style: GoogleFonts.dmSans(fontSize: 14, color: textColor),
        decoration: decoration,
      );
    }
    return TextField(
      controller: controller,
      maxLines: 1,
      keyboardType: _keyboardTypeForField(field.fieldType),
      inputFormatters: _inputFormattersForField(field.fieldType),
      maxLength: _maxFieldLength,
      style: GoogleFonts.dmSans(fontSize: 14, color: textColor),
      decoration: decoration,
    );
  }

  TextInputType _keyboardTypeForField(SmartFormFieldType fieldType) {
    switch (fieldType) {
      case SmartFormFieldType.phone:
        return TextInputType.phone;
      case SmartFormFieldType.email:
        return TextInputType.emailAddress;
      case SmartFormFieldType.number:
        return TextInputType.number;
      case SmartFormFieldType.textarea:
        return TextInputType.multiline;
      case SmartFormFieldType.text:
        return TextInputType.text;
    }
  }

  List<TextInputFormatter> _inputFormattersForField(
    SmartFormFieldType fieldType,
  ) {
    switch (fieldType) {
      case SmartFormFieldType.number:
        return [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.phone:
        return [
          FilteringTextInputFormatter.allow(RegExp(r"[0-9+\-\s().]")),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.email:
        return [
          FilteringTextInputFormatter.deny(RegExp(r"\s")),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.textarea:
        return [
          FilteringTextInputFormatter.allow(
            RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s.,;:!¡?¿()#@&/_\-\n]'),
          ),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
      case SmartFormFieldType.text:
        return [
          FilteringTextInputFormatter.allow(
            RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s.,;:!¡?¿()#@&/_\-]'),
          ),
          LengthLimitingTextInputFormatter(_maxFieldLength),
        ];
    }
  }
}

// ─── NFC Activation Page ──────────────────────────────────────────────────────

class _NfcActivationPage extends StatelessWidget {
  final String serial;
  final bool isLoggedIn;
  final bool activating;
  final String? error;
  final VoidCallback onActivate;
  final VoidCallback onLogin;

  const _NfcActivationPage({
    required this.serial,
    required this.isLoggedIn,
    required this.activating,
    required this.error,
    required this.onActivate,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final loggedIn = appState.isAuthenticated;
        final logoUrl = appState.currentCard?.companyLogoUrl;
        return Scaffold(
          backgroundColor: AppColors.surface,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 40,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (logoUrl != null && logoUrl.isNotEmpty) ...[
                        Image.network(
                          logoUrl,
                          height: 46,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 40),
                      ],
                      // NFC icon
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.nfc,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        loggedIn
                            ? 'Activa tu tarjeta digital'
                            : 'Esta tarjeta está lista para activarse',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        loggedIn
                            ? 'Esta tarjeta NFC todavía no está vinculada a ninguna cuenta. ¿Deseas vincularla a tu cuenta?'
                            : 'Crea una cuenta o inicia sesión para vincular esta tarjeta NFC a tu perfil.',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: AppColors.grey,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      if (loggedIn) ...[
                        // ── Logged in: show "Link" button ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: activating ? null : onActivate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: activating
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'Vincular con mi cuenta',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => context.go('/'),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.inter(
                              color: AppColors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ] else ...[
                        // ── Not logged in: show register/login CTAs ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => context.go('/?pendingNfc=$serial'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Ir a inicio',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: onLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Ya tengo cuenta',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Serial chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.credit_card,
                              size: 14,
                              color: AppColors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              serial,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Not Found ────────────────────────────────────────────────────────────────

class _NotFoundPage extends StatelessWidget {
  final String slug;
  final String? errorDetail;
  const _NotFoundPage({required this.slug, this.errorDetail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_off_outlined,
                  size: 36,
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tarjeta no encontrada',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La tarjeta /$slug no existe o fue desactivada.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.grey),
              ),
              if (errorDetail != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorDetail!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://liomont.taploop.com.mx');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  'Ir al inicio →',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
