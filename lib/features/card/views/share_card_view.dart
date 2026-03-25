// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/analytics_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../analytics/models/analytics_summary_model.dart';
import '../models/contact_item_model.dart';
import '../widgets/qr_code_widget.dart';

class ShareCardView extends StatefulWidget {
  const ShareCardView({super.key});

  @override
  State<ShareCardView> createState() => _ShareCardViewState();
}

class _ShareCardViewState extends State<ShareCardView> {
  bool _linkCopied = false;
  Color _qrColor = AppColors.black;
  AnalyticsSummaryModel? _analytics;
  String? _loadedCardId;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeCardId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _loadAnalytics();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    super.dispose();
  }

  void _onAppStateChanged() {
    final cardId = appState.currentCard?.id;
    _bindRealtime();
    if (!mounted) return;
    if (cardId != null && cardId != _loadedCardId) {
      _loadAnalytics();
    }
    setState(() {});
  }

  void _bindRealtime() {
    final cardId = appState.currentCard?.id;
    if (cardId == _realtimeCardId) return;
    _metricsRealtime?.close();
    _realtimeCardId = cardId;
    if (cardId == null || cardId.isEmpty) return;
    _metricsRealtime = MetricsRealtimeSubscription.forCard(
      cardId: cardId,
      onRefresh: () {
        if (!mounted) return;
        _loadAnalytics();
      },
    );
  }

  Future<void> _loadAnalytics() async {
    final cardId = appState.currentCard?.id;
    if (cardId == null) {
      _loadedCardId = null;
      if (mounted) {
        setState(() {
          _analytics = null;
        });
      }
      return;
    }
    try {
      final a = await AnalyticsRepository.fetchSummary(cardId);
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _analytics = a;
        });
      }
    } catch (_) {}
  }

  static const _qrPalette = <Color>[
    AppColors.black,
    AppColors.primary,
    Color(0xFF6C4FE8),
    Color(0xFF1A73E8),
  ];

  void _copyLink() {
    final url = appState.currentCard?.publicUrl ?? '';
    Clipboard.setData(ClipboardData(text: url));
    setState(() => _linkCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);
    final effectiveQrColor = _qrColor == AppColors.black && context.isDark
        ? Colors.white
        : _qrColor;
    final hasLinkedCard = appState.currentCard != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: context.bgCard,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compartir',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Distribuye tu tarjeta digital, QR y contacto desde un centro único.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: hasLinkedCard
                ? (isDesktop
                      ? _DesktopLayout(
                          linkCopied: _linkCopied,
                          onCopy: _copyLink,
                          qrColor: effectiveQrColor,
                          qrPalette: _qrPalette,
                          onQrColorChanged: (c) => setState(() => _qrColor = c),
                          analytics: _analytics,
                        )
                      : _MobileLayout(
                          linkCopied: _linkCopied,
                          onCopy: _copyLink,
                          isMobile: isMobile,
                          qrColor: effectiveQrColor,
                          qrPalette: _qrPalette,
                          onQrColorChanged: (c) => setState(() => _qrColor = c),
                          analytics: _analytics,
                        ))
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 64 : 20,
                      28,
                      isDesktop ? 64 : 20,
                      36,
                    ),
                    child: CardInitialSetupState(
                      onLinked: () => setState(() {}),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile / Tablet ──────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final bool linkCopied;
  final VoidCallback onCopy;
  final bool isMobile;
  final Color qrColor;
  final List<Color> qrPalette;
  final ValueChanged<Color> onQrColorChanged;
  final AnalyticsSummaryModel? analytics;

  const _MobileLayout({
    required this.linkCopied,
    required this.onCopy,
    required this.isMobile,
    required this.qrColor,
    required this.qrPalette,
    required this.onQrColorChanged,
    required this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final hPad = isMobile ? 24.0 : 48.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              _SectionPanel(
                child: _CardHeroSection(hPad: 0, analytics: analytics),
              ),
              const SizedBox(height: 24),
              _SectionPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeading(
                      title: 'Distribución',
                      subtitle:
                          'Copia el enlace o envíalo por tus canales principales.',
                    ),
                    const SizedBox(height: 18),
                    _LinkBar(copied: linkCopied, onCopy: onCopy),
                    const SizedBox(height: 20),
                    const _QuickShareSection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionPanel(
                child: _QrSection(
                  qrColor: qrColor,
                  qrPalette: qrPalette,
                  onQrColorChanged: onQrColorChanged,
                ),
              ),
              const SizedBox(height: 24),
              const _SectionPanel(child: _WalletSection()),
              const SizedBox(height: 52),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Desktop ──────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final bool linkCopied;
  final VoidCallback onCopy;
  final Color qrColor;
  final List<Color> qrPalette;
  final ValueChanged<Color> onQrColorChanged;
  final AnalyticsSummaryModel? analytics;

  const _DesktopLayout({
    required this.linkCopied,
    required this.onCopy,
    required this.qrColor,
    required this.qrPalette,
    required this.onQrColorChanged,
    required this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(64, 44, 64, 56),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left — overview and contact actions
              SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionPanel(
                      child: _CardHeroSection(hPad: 0, analytics: analytics),
                    ),
                    const SizedBox(height: 24),
                    _SectionPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionHeading(
                            title: 'Compartir contacto',
                            subtitle:
                                'Administra el enlace principal y distribúyelo desde aquí.',
                          ),
                          const SizedBox(height: 18),
                          _LinkBar(copied: linkCopied, onCopy: onCopy),
                          const SizedBox(height: 20),
                          const _QuickShareSection(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 44),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionPanel(
                      child: _QrSection(
                        qrColor: qrColor,
                        qrPalette: qrPalette,
                        onQrColorChanged: onQrColorChanged,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionPanel(child: _WalletSection()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Card Hero ────────────────────────────────────────────────────────────────

class _CardHeroSection extends StatelessWidget {
  final double hPad;
  final AnalyticsSummaryModel? analytics;
  const _CardHeroSection({required this.hPad, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final isDesktop = Responsive.isDesktop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDesktop ? 'Centro de distribución' : 'Compartir contacto',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Presenta tu tarjeta de forma más ejecutiva y comparte desde un solo lugar.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: context.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          const Center(child: _MinimalCardPreview(width: 280)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  icon: Icons.touch_app_outlined,
                  label: 'Taps NFC',
                  value: '${a?.totalTaps ?? 0}',
                  color: const Color(0xFF6C4FE8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatChip(
                  icon: Icons.qr_code_2_outlined,
                  label: 'QR Scans',
                  value: '${a?.totalQrScans ?? 0}',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatChip(
                  icon: Icons.visibility_outlined,
                  label: 'Esta semana',
                  value: '+${a?.visitsThisWeek ?? 0}',
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                final url = appState.currentCard?.publicUrl;
                if (url != null) launchUrl(Uri.parse(url));
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    (appState.currentCard?.publicUrl ?? '').replaceFirst(
                      'https://',
                      '',
                    ),
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_outward_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Minimal Card Preview ────────────────────────────────────────────────────

class _MinimalCardPreview extends StatelessWidget {
  final double width;
  const _MinimalCardPreview({this.width = 280});

  double get height => width * (54 / 85.6); // CR80 ratio

  @override
  Widget build(BuildContext context) {
    final card = appState.currentCard;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(width * 0.04),
        border: Border.all(color: context.borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.07,
          vertical: height * 0.12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: logo + NFC
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (card?.companyLogoUrl != null &&
                    card!.companyLogoUrl!.isNotEmpty)
                  Image.network(
                    card.companyLogoUrl!,
                    height: height * 0.30,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                else
                  Text(
                    card?.company.isNotEmpty == true
                        ? card!.company
                        : 'TapLoop',
                    style: GoogleFonts.outfit(
                      fontSize: height * 0.15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                Icon(Icons.wifi, size: height * 0.20, color: context.textMuted),
              ],
            ),
            const Spacer(),
            // Name
            Text(
              card?.name ?? '',
              style: GoogleFonts.outfit(
                fontSize: height * 0.16,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: height * 0.04),
            // Job title
            Text(
              card?.jobTitle ?? '',
              style: GoogleFonts.dmSans(
                fontSize: height * 0.11,
                color: context.textSecondary,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: context.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── QR Section ───────────────────────────────────────────────────────────────

class _QrSection extends StatefulWidget {
  final Color qrColor;
  final List<Color> qrPalette;
  final ValueChanged<Color> onQrColorChanged;

  const _QrSection({
    required this.qrColor,
    required this.qrPalette,
    required this.onQrColorChanged,
  });

  @override
  State<_QrSection> createState() => _QrSectionState();
}

class _QrSectionState extends State<_QrSection> {
  bool _downloading = false;

  Future<void> _downloadQrPng() async {
    if (_downloading) return;
    final url = appState.currentCard?.publicUrl;
    if (url == null) return;
    setState(() => _downloading = true);
    try {
      final painter = QrPainter(
        data: '$url?via=qr',
        version: QrVersions.auto,
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: widget.qrColor,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: widget.qrColor,
        ),
      );
      final imageData = await painter.toImageData(600);
      if (imageData == null) return;
      final bytes = imageData.buffer.asUint8List();
      final blob = html.Blob([bytes], 'image/png');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: blobUrl)
        ..download = 'qr_tarjeta.png'
        ..click();
      html.Url.revokeObjectUrl(blobUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al generar QR: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Código QR ejecutivo',
          subtitle:
              'Personaliza el QR y úsalo en presentaciones, impresos o eventos.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.qrPalette.map((c) {
            final active = widget.qrColor == c;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onQrColorChanged(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: active ? context.textPrimary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              QrCodeWidget(
                data: appState.currentCard != null
                    ? '${appState.currentCard!.publicUrl}?via=qr'
                    : '',
                size: 200,
                foregroundColor: widget.qrColor,
                showLogo: true,
                embeddedLogoUrl: appState.currentCard?.companyLogoUrl,
              ),
              const SizedBox(height: 12),
              Text(
                'liomont.taploop.com.mx/${appState.currentCard?.publicSlug ?? ''}',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _QrActionButton(
                icon: _downloading
                    ? Icons.hourglass_empty
                    : Icons.download_outlined,
                label: _downloading ? 'Generando...' : 'Descargar PNG',
                onTap: _downloadQrPng,
                variant: _QrButtonVariant.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QrActionButton(
                icon: Icons.ios_share_outlined,
                label: 'Compartir QR',
                onTap: () {
                  final url = appState.currentCard?.publicUrl;
                  if (url != null) {
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                variant: _QrButtonVariant.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _QrButtonVariant { outline, filled }

class _QrActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _QrButtonVariant variant;

  const _QrActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final isFilled = variant == _QrButtonVariant.filled;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: isFilled ? context.textPrimary : context.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFilled ? context.textPrimary : context.borderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isFilled
                    ? (context.isDark ? Colors.black : Colors.white)
                    : context.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isFilled
                      ? (context.isDark ? Colors.black : Colors.white)
                      : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Link Bar ─────────────────────────────────────────────────────────────────

class _LinkBar extends StatelessWidget {
  final bool copied;
  final VoidCallback onCopy;
  const _LinkBar({required this.copied, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enlace público',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              copied ? Icons.check_circle_outline : Icons.link_rounded,
              size: 16,
              color: copied ? AppColors.success : context.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appState.currentCard?.publicUrl ?? '',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: context.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onCopy,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: copied
                      ? AppColors.success.withValues(alpha: 0.3)
                      : context.borderColor,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    copied ? 'Enlace copiado' : 'Copiar enlace',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: copied ? AppColors.success : AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    size: 16,
                    color: copied ? AppColors.success : AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Quick Share Section ──────────────────────────────────────────────────────

class _QuickShareSection extends StatelessWidget {
  const _QuickShareSection();

  void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final cardUrl = appState.currentCard?.publicUrl ?? '';
    final name = appState.currentCard?.name ?? 'mi contacto';
    final encoded = Uri.encodeComponent(cardUrl);
    final msgText = Uri.encodeComponent(
      'Te comparto la tarjeta digital de $name: $cardUrl',
    );

    final actions = <(IconData, String, VoidCallback)>[
      (
        Icons.chat_outlined,
        'WhatsApp',
        () => _open('https://wa.me/?text=$msgText'),
      ),
      (
        Icons.email_outlined,
        'Email',
        () => _open(
          'mailto:?subject=${Uri.encodeComponent('Tarjeta digital de $name')}&body=$msgText',
        ),
      ),
      (
        Icons.send_outlined,
        'Telegram',
        () => _open(
          'https://t.me/share/url?url=$encoded&text=${Uri.encodeComponent('Tarjeta de $name')}',
        ),
      ),
      (
        Icons.work_outline,
        'LinkedIn',
        () => _open(
          'https://www.linkedin.com/sharing/share-offsite/?url=$encoded',
        ),
      ),
      (
        Icons.alternate_email,
        'X / Twitter',
        () => _open('https://twitter.com/intent/tweet?text=$msgText'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Canales de envío',
          subtitle: 'Usa accesos rápidos para mandar tu contacto en segundos.',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 420;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 2 : 1,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 58,
              ),
              itemBuilder: (_, i) {
                final action = actions[i];
                return _QuickShareButton(
                  icon: action.$1,
                  label: action.$2,
                  onTap: action.$3,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _QuickShareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickShareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.bgSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: context.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: 14,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Wallet Section ───────────────────────────────────────────────────────────

class _WalletSection extends StatefulWidget {
  const _WalletSection();

  @override
  State<_WalletSection> createState() => _WalletSectionState();
}

class _WalletSectionState extends State<_WalletSection> {
  bool _downloading = false;

  Future<void> _downloadVCard() async {
    final card = appState.currentCard;
    if (card == null) return;
    setState(() => _downloading = true);
    try {
      final lines = <String>['BEGIN:VCARD', 'VERSION:3.0'];
      lines.add('FN:${card.name}');
      if (card.jobTitle.isNotEmpty) lines.add('TITLE:${card.jobTitle}');
      if (card.company.isNotEmpty) lines.add('ORG:${card.company}');
      final visibleContacts =
          card.contactItems.where((c) => c.isVisible).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (final c in visibleContacts) {
        switch (c.type) {
          case ContactType.phone:
          case ContactType.whatsapp:
            lines.add('TEL:${c.value}');
          case ContactType.email:
            lines.add('EMAIL:${c.value}');
          case ContactType.website:
            lines.add('URL:${c.value}');
          case ContactType.address:
            lines.add('ADR:;;${c.value};;;;');
        }
      }
      lines.add('URL:${card.publicUrl}');
      lines.add('NOTE:Tarjeta digital: ${card.publicUrl}');
      lines.add('END:VCARD');
      final vcf = lines.join('\r\n');
      final blob = html.Blob([vcf], 'text/vcard');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: blobUrl)
        ..download = '${card.name.replaceAll(' ', '_')}.vcf'
        ..click();
      html.Url.revokeObjectUrl(blobUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar contacto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Guardar contacto',
          subtitle:
              'Descarga tu tarjeta en formato compatible para iPhone o Android.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _WalletButton(
                label: _downloading ? 'Guardando...' : 'Apple Wallet',
                sublabel: 'Para iPhone',
                icon: Icons.apple,
                isPrimary: true,
                onTap: _downloading ? null : _downloadVCard,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WalletButton(
                label: _downloading ? 'Guardando...' : 'Google Wallet',
                sublabel: 'Para Android',
                icon: Icons.account_balance_wallet_outlined,
                isPrimary: false,
                onTap: _downloading ? null : _downloadVCard,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: context.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Abre el archivo descargado en tu teléfono para guardar el contacto',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionPanel extends StatelessWidget {
  final Widget child;

  const _SectionPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: child,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: context.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _WalletButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _WalletButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isPrimary ? context.textPrimary : context.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPrimary ? context.textPrimary : context.borderColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isPrimary
                    ? (context.isDark ? Colors.black : Colors.white)
                    : context.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isPrimary
                          ? (context.isDark ? Colors.black : Colors.white)
                          : context.textPrimary,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: isPrimary
                          ? (context.isDark
                                ? Colors.black.withValues(alpha: 0.75)
                                : Colors.white70)
                          : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
