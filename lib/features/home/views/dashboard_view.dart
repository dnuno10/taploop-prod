import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/analytics_repository.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../analytics/models/analytics_summary_model.dart';
import '../../analytics/models/lead_model.dart';
import '../../analytics/models/link_stat_model.dart';
import '../../analytics/models/visit_event_model.dart';
import '../../card/models/digital_card_model.dart';

Color _panelBorderColor(BuildContext context) => context.borderSoft;
Color _panelSurfaceColor(BuildContext context) =>
    context.bgSubtle.withValues(alpha: 0.5);

class DashboardView extends StatefulWidget {
  final void Function(int index) onNavigate;

  const DashboardView({super.key, required this.onNavigate});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  AnalyticsSummaryModel? _analytics;
  List<LeadModel> _leads = [];
  bool _loading = true;
  String? _loadedCardId;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeCardId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _load();
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

    if (cardId != _loadedCardId) {
      setState(() => _loading = true);
      _load();
      return;
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
        _load();
      },
    );
  }

  Future<void> _load() async {
    final cardId = appState.currentCard?.id;
    if (cardId == null) {
      if (!mounted) return;
      setState(() {
        _loadedCardId = null;
        _analytics = null;
        _leads = [];
        _loading = false;
      });
      return;
    }

    try {
      final results = await Future.wait([
        AnalyticsRepository.fetchSummary(cardId),
        LeadRepository.fetchDashboardLeadsForCard(cardId),
      ]);

      if (!mounted) return;
      setState(() {
        _loadedCardId = cardId;
        _analytics = results[0] as AnalyticsSummaryModel;
        _leads = results[1] as List<LeadModel>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadedCardId = cardId;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isResolvingCard =
        appState.isAuthenticated &&
        appState.loadingCard &&
        appState.currentCard == null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _loading || isResolvingCard
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 1180;
                  final isTablet = constraints.maxWidth >= 820;
                  final padding = isDesktop
                      ? const EdgeInsets.fromLTRB(28, 24, 28, 28)
                      : isTablet
                      ? const EdgeInsets.fromLTRB(22, 20, 22, 24)
                      : const EdgeInsets.fromLTRB(16, 16, 16, 24);

                  return SingleChildScrollView(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DashboardHeader(
                          onOpenPublicCard: _openPublicCard,
                          onNavigate: widget.onNavigate,
                        ),
                        const SizedBox(height: 20),
                        if (appState.currentCard == null)
                          CardInitialSetupState(onLinked: () => setState(() {}))
                        else if (isDesktop)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: Column(
                                  children: [
                                    _buildOverviewStack(compact: false),
                                    const SizedBox(height: 20),
                                    _LeadsTable(
                                      leads: _sortedLeads,
                                      onNavigate: widget.onNavigate,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 3,
                                child: _RightRail(
                                  analytics: _analytics,
                                  leads: _sortedLeads,
                                ),
                              ),
                            ],
                          )
                        else if (isTablet)
                          Column(
                            children: [
                              _buildOverviewStack(compact: true, narrow: false),
                              const SizedBox(height: 18),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: _LeadsTable(
                                      leads: _sortedLeads,
                                      onNavigate: widget.onNavigate,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    flex: 5,
                                    child: _RightRail(
                                      analytics: _analytics,
                                      leads: _sortedLeads,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildOverviewStack(compact: true, narrow: true),
                              const SizedBox(height: 18),
                              _ActivityPanel(
                                events: _analytics?.recentEvents ?? const [],
                                leads: _sortedLeads,
                              ),
                              const SizedBox(height: 18),
                              _LeadsTable(
                                leads: _sortedLeads,
                                onNavigate: widget.onNavigate,
                              ),
                              const SizedBox(height: 18),
                              _TopLinksPanel(
                                links: _analytics?.linkStats ?? const [],
                              ),
                              const SizedBox(height: 18),
                              _ConversionPanel(analytics: _analytics),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildOverviewStack({required bool compact, bool narrow = false}) {
    final analytics = _analytics;
    final leads = _sortedLeads;
    final growth = analytics?.weeklyGrowthPercent ?? 0;
    final card = appState.currentCard;
    final totalLeads = leads.length;
    final hotLeads = leads
        .where((lead) => lead.status == LeadStatus.hot)
        .length;
    final statCards = [
      _StatCard(
        label: 'Tarjeta activa',
        value: card?.isActive == true ? 'Activa' : 'Pendiente',
        subtitle: card?.publicSlug.isNotEmpty == true
            ? '@${card!.publicSlug}'
            : 'Sin slug publicado',
        tone: _panelSurfaceColor(context),
        icon: Icons.badge_outlined,
        compact: compact,
      ),
      _StatCard(
        label: 'Visitas totales',
        value: '${analytics?.totalVisits ?? 0}',
        delta: '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(0)}%',
        deltaPositive: growth >= 0,
        tone: _panelSurfaceColor(context),
        icon: Icons.visibility_outlined,
        compact: compact,
      ),
      _StatCard(
        label: 'Interacciones',
        value: '${analytics?.totalClicks ?? 0}',
        subtitle: 'Clics en enlaces y CTA',
        tone: _panelSurfaceColor(context),
        icon: Icons.ads_click_outlined,
        compact: compact,
      ),
      _StatCard(
        label: 'Leads activos',
        value: '$totalLeads',
        subtitle: '$hotLeads listos para seguimiento',
        tone: _panelSurfaceColor(context),
        icon: Icons.groups_2_outlined,
        compact: compact,
      ),
    ];

    return Column(
      children: [
        _OverviewStatsGrid(cards: statCards, compact: compact),
        const SizedBox(height: 20),
        if (compact)
          Column(
            children: [
              if (narrow) ...[
                _QuickActions(
                  onNavigate: widget.onNavigate,
                  onOpenPublicCard: _openPublicCard,
                  compact: true,
                ),
                const SizedBox(height: 18),
              ],
              _CardPreviewPanel(
                card: appState.currentCard!,
                onOpenPublicCard: _openPublicCard,
                compact: narrow,
              ),
              const SizedBox(height: 18),
              if (!narrow)
                _QuickActions(
                  onNavigate: widget.onNavigate,
                  onOpenPublicCard: _openPublicCard,
                  compact: true,
                ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: _CardPreviewPanel(
                  card: appState.currentCard!,
                  onOpenPublicCard: _openPublicCard,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(flex: 7, child: _PerformancePanel(analytics: analytics)),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _QuickActions(
                  onNavigate: widget.onNavigate,
                  onOpenPublicCard: _openPublicCard,
                ),
              ),
            ],
          ),
        if (compact) ...[
          const SizedBox(height: 18),
          _PerformancePanel(analytics: analytics, compact: narrow),
        ],
      ],
    );
  }

  List<LeadModel> get _sortedLeads {
    final leads = [..._leads];
    leads.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return b.lastSeen.compareTo(a.lastSeen);
    });
    return leads.take(6).toList();
  }

  Future<void> _openPublicCard() async {
    final url = appState.currentCard?.publicUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri);
    }
  }
}

class _DashboardHeader extends StatelessWidget {
  final VoidCallback onOpenPublicCard;
  final ValueChanged<int> onNavigate;

  const _DashboardHeader({
    required this.onOpenPublicCard,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final user = appState.currentUser;
    final isWide = MediaQuery.of(context).size.width >= 920;
    final isCompact = MediaQuery.of(context).size.width < 680;
    final actions = [
      (
        label: 'Editar tarjeta',
        icon: Icons.edit_outlined,
        filled: false,
        onTap: () => onNavigate(1),
      ),
      (
        label: 'Compartir',
        icon: Icons.ios_share_outlined,
        filled: false,
        onTap: () => onNavigate(2),
      ),
      (
        label: 'Ver perfil',
        icon: Icons.arrow_outward_rounded,
        filled: true,
        onTap: onOpenPublicCard,
      ),
    ];

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel principal',
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Monitorea visitas, leads y rendimiento de tu tarjeta TapLoop en un solo flujo.',
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _panelSurfaceColor(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _panelBorderColor(context)),
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: context.bgSubtle,
                  backgroundImage: user?.photoUrl?.isNotEmpty == true
                      ? NetworkImage(user!.photoUrl!)
                      : null,
                  child: user?.photoUrl?.isNotEmpty == true
                      ? null
                      : Text(
                          user?.initials ?? 'TL',
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: cardWidth,
                      child: _HeaderButton(
                        label: action.label,
                        icon: action.icon,
                        filled: action.filled,
                        onTap: action.onTap,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isWide ? 320 : 240,
            maxWidth: isWide ? 460 : MediaQuery.of(context).size.width,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Panel principal',
                style: GoogleFonts.outfit(
                  color: context.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Monitorea visitas, leads y rendimiento de tu tarjeta TapLoop en un solo flujo.',
                style: GoogleFonts.dmSans(
                  color: context.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        for (final action in actions)
          _HeaderButton(
            label: action.label,
            icon: action.icon,
            filled: action.filled,
            onTap: action.onTap,
          ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _panelSurfaceColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _panelBorderColor(context)),
          ),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: context.bgSubtle,
            backgroundImage: user?.photoUrl?.isNotEmpty == true
                ? NetworkImage(user!.photoUrl!)
                : null,
            child: user?.photoUrl?.isNotEmpty == true
                ? null
                : Text(
                    user?.initials ?? 'TL',
                    style: GoogleFonts.outfit(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _HeaderButton({
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: _panelSurfaceColor(context),
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
                size: 17,
                color: filled ? AppColors.primary : context.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  color: filled ? AppColors.primary : context.textPrimary,
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final String? delta;
  final bool deltaPositive;
  final Color tone;
  final IconData icon;
  final bool compact;

  const _StatCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.delta,
    this.deltaPositive = true,
    required this.tone,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _panelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.textSecondary),
              const Spacer(),
              if (delta != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgSubtle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delta!,
                    style: GoogleFonts.dmSans(
                      color: deltaPositive
                          ? AppColors.success
                          : AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            label,
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: compact ? 24 : 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewStatsGrid extends StatelessWidget {
  final List<Widget> cards;
  final bool compact;

  const _OverviewStatsGrid({required this.cards, required this.compact});

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _PerformancePanel extends StatelessWidget {
  final AnalyticsSummaryModel? analytics;
  final bool compact;

  const _PerformancePanel({required this.analytics, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final visits = analytics?.visitsByDay ?? const [0, 0, 0, 0, 0, 0, 0];
    final clicks = _deriveSeries(visits, analytics?.totalClicks ?? 0);
    final taps = _deriveSeries(visits, analytics?.totalTaps ?? 0);
    final maxValue = [
      ...visits,
      ...clicks,
      ...taps,
    ].fold<int>(0, (current, value) => math.max(current, value));
    final chartMax = math.max(4, maxValue + 1).toDouble();
    final leftInterval = math.max(1, (chartMax / 4).ceil()).toDouble();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de actividad',
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comparativa semanal entre visitas, clics y toques NFC.',
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Últimos 7 días',
                style: GoogleFonts.dmSans(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: const [
              _ChartLegend(color: AppColors.primary, label: 'Visitas'),
              _ChartLegend(color: Color(0xFF3F3F46), label: 'Clics'),
              _ChartLegend(color: Color(0xFF2E8B57), label: 'Toques NFC'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: compact ? 220 : 270,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: chartMax,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: leftInterval,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: context.borderColor, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: leftInterval,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: GoogleFonts.dmSans(
                            color: context.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[index],
                            style: GoogleFonts.dmSans(
                              color: context.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 3,
                    color: AppColors.primary,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                    spots: [
                      for (var i = 0; i < visits.length; i++)
                        FlSpot(i.toDouble(), visits[i].toDouble()),
                    ],
                  ),
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 2,
                    color: const Color(0xFF3F3F46),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                    spots: [
                      for (var i = 0; i < clicks.length; i++)
                        FlSpot(i.toDouble(), clicks[i].toDouble()),
                    ],
                  ),
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 2,
                    color: const Color(0xFF2E8B57),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                    spots: [
                      for (var i = 0; i < taps.length; i++)
                        FlSpot(i.toDouble(), taps[i].toDouble()),
                    ],
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

class _QuickActions extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenPublicCard;
  final bool compact;

  const _QuickActions({
    required this.onNavigate,
    required this.onOpenPublicCard,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        icon: Icons.edit_note_outlined,
        label: 'Actualizar perfil',
        description: 'Ajusta tu tarjeta y tu presencia digital.',
        onTap: () => onNavigate(1),
      ),
      (
        icon: Icons.send_outlined,
        label: 'Compartir tarjeta',
        description: 'Envía tu tarjeta por QR o enlace.',
        onTap: () => onNavigate(2),
      ),
      (
        icon: Icons.campaign_outlined,
        label: 'Abrir campañas',
        description: 'Activa campañas y seguimiento comercial.',
        onTap: () => onNavigate(5),
      ),
      (
        icon: Icons.language_rounded,
        label: 'Ver perfil público',
        description: 'Revisa el perfil que ve tu lead.',
        onTap: onOpenPublicCard,
      ),
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Acciones rápidas',
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Acciones clave para operar TapLoop sin cambiar de contexto.',
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          if (compact)
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final action in actions)
                      SizedBox(
                        width: itemWidth,
                        child: _ActionRow(
                          icon: action.icon,
                          label: action.label,
                          description: action.description,
                          onTap: action.onTap,
                          compact: true,
                        ),
                      ),
                  ],
                );
              },
            )
          else
            ...actions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActionRow(
                  icon: action.icon,
                  label: action.label,
                  description: action.description,
                  onTap: action.onTap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool compact;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            color: _panelSurfaceColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _panelBorderColor(context)),
          ),
          child: Row(
            children: [
              Icon(icon, color: context.textSecondary, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.dmSans(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: compact ? 11 : 12,
                        height: 1.35,
                      ),
                      maxLines: compact ? 2 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                color: context.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RightRail extends StatelessWidget {
  final AnalyticsSummaryModel? analytics;
  final List<LeadModel> leads;

  const _RightRail({required this.analytics, required this.leads});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ConversionPanel(analytics: analytics),
        const SizedBox(height: 18),
        _TopLinksPanel(links: analytics?.linkStats ?? const []),
        const SizedBox(height: 18),
        _ActivityPanel(
          events: analytics?.recentEvents ?? const [],
          leads: leads,
        ),
      ],
    );
  }
}

class _CardPreviewPanel extends StatelessWidget {
  final DigitalCardModel card;
  final VoidCallback onOpenPublicCard;
  final bool compact;

  const _CardPreviewPanel({
    required this.card,
    required this.onOpenPublicCard,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tarjeta',
                style: GoogleFonts.outfit(
                  color: context.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: onOpenPublicCard,
                child: const Text('Abrir'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 16 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: _panelSurfaceColor(context),
              border: Border.all(color: _panelBorderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (card.companyLogoUrl?.isNotEmpty == true)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 110,
                          maxHeight: 28,
                        ),
                        child: Image.network(
                          card.companyLogoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Text(
                            card.company.isNotEmpty ? card.company : 'TapLoop',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: context.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        card.company.isNotEmpty ? card.company : 'TapLoop',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Icon(
                      card.isActive ? Icons.check_circle : Icons.pause_circle,
                      color: context.textSecondary,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  card.name.isNotEmpty ? card.name : 'Perfil TapLoop',
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (card.jobTitle.isNotEmpty) card.jobTitle,
                    if (card.company.isNotEmpty) card.company,
                  ].join(' • '),
                  style: GoogleFonts.dmSans(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  '@${card.publicSlug}',
                  style: GoogleFonts.dmSans(
                    color: context.textPrimary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversionPanel extends StatelessWidget {
  final AnalyticsSummaryModel? analytics;

  const _ConversionPanel({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final totalInteractions = math.max(analytics?.totalInteractions ?? 0, 1);
    final metrics = [
      (
        label: 'Visitas',
        value: analytics?.totalVisits ?? 0,
        color: AppColors.primary,
      ),
      (
        label: 'Toques NFC',
        value: analytics?.totalTaps ?? 0,
        color: const Color(0xFFA98BFF),
      ),
      (
        label: 'Clics',
        value: analytics?.totalClicks ?? 0,
        color: const Color(0xFF57B894),
      ),
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversión',
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Participación de cada tipo de evento dentro del rango.',
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          ...metrics.map(
            (metric) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ProgressMetric(
                label: metric.label,
                value: metric.value,
                progress: metric.value / totalInteractions,
                color: metric.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  final String label;
  final int value;
  final double progress;
  final Color color;

  const _ProgressMetric({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$value',
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(progress.clamp(0, 1) * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 10,
            backgroundColor: context.bgSubtle,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.dmSans(
            color: context.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TopLinksPanel extends StatelessWidget {
  final List<LinkStatModel> links;

  const _TopLinksPanel({required this.links});

  @override
  Widget build(BuildContext context) {
    final topLinks = [...links]..sort((a, b) => b.clicks.compareTo(a.clicks));

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enlaces principales',
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Los enlaces con mayor intención de contacto.',
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          if (topLinks.isEmpty)
            Text(
              'Aún no hay clics suficientes para mostrar ranking.',
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 12,
              ),
            )
          else
            ...topLinks
                .take(4)
                .map(
                  (link) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          _platformIcon(link.platform),
                          size: 17,
                          color: context.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                link.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(
                                  color: context.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(link.percentage * 100).toStringAsFixed(0)}% de los clics',
                                style: GoogleFonts.dmSans(
                                  color: context.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${link.clicks}',
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
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

class _ActivityPanel extends StatelessWidget {
  final List<VisitEventModel> events;
  final List<LeadModel> leads;

  const _ActivityPanel({required this.events, required this.leads});

  @override
  Widget build(BuildContext context) {
    final items = events.take(4).toList();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actividad reciente',
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Últimos movimientos detectados en tu ecosistema TapLoop.',
            style: GoogleFonts.dmSans(
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Text(
              'Todavía no hay eventos recientes.',
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 12,
              ),
            )
          else
            ...items.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _platformIcon(event.source ?? ''),
                      size: 17,
                      color: context.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.label?.isNotEmpty == true
                                ? event.label!
                                : _eventTitle(event),
                            style: GoogleFonts.dmSans(
                              color: context.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${event.locationDisplay} • ${event.formattedDate} ${event.formattedTime}',
                            style: GoogleFonts.dmSans(
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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

class _LeadsTable extends StatelessWidget {
  final List<LeadModel> leads;
  final ValueChanged<int> onNavigate;

  const _LeadsTable({required this.leads, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leads recientes',
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Leads priorizados por intención y última actividad.',
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _HeaderButton(
                label: 'Abrir analíticas',
                icon: Icons.arrow_forward_rounded,
                filled: false,
                onTap: () => onNavigate(3),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (leads.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Todavía no hay leads capturados.',
                style: GoogleFonts.dmSans(
                  color: context.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          else if (isDesktop)
            Column(
              children: [
                const _LeadsHeaderRow(),
                const SizedBox(height: 10),
                ...leads.map(
                  (lead) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LeadRow(lead: lead),
                  ),
                ),
              ],
            )
          else
            Column(
              children: leads
                  .map(
                    (lead) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LeadCard(lead: lead),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _LeadsHeaderRow extends StatelessWidget {
  const _LeadsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.dmSans(
      color: context.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('LEAD', style: style)),
          Expanded(flex: 4, child: Text('ETAPA', style: style)),
          Expanded(flex: 3, child: Text('ÚLTIMA VISITA', style: style)),
        ],
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  final LeadModel lead;

  const _LeadRow({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _panelBorderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: context.bgSubtle,
                  child: Text(
                    _initials(lead.displayName),
                    style: GoogleFonts.outfit(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lead.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lead.company?.isNotEmpty == true
                            ? lead.company!
                            : (lead.location?.isNotEmpty == true
                                  ? lead.location!
                                  : 'Sin empresa registrada'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _pipelineLabel(lead.pipelineStage),
              style: GoogleFonts.dmSans(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatShortDate(lead.lastSeen),
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final LeadModel lead;

  const _LeadCard({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _panelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: context.bgSubtle,
                child: Text(
                  _initials(lead.displayName),
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.displayName,
                      style: GoogleFonts.dmSans(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pipelineLabel(lead.pipelineStage),
                      style: GoogleFonts.dmSans(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LeadMetric(
                label: 'Última visita',
                value: _formatShortDate(lead.lastSeen),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeadMetric extends StatelessWidget {
  final String label;
  final String value;

  const _LeadMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _panelBorderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: context.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _panelSurfaceColor(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _panelBorderColor(context)),
      ),
      child: child,
    );
  }
}

enum _LinkInputMode { qr, code }

class _CardLinkResult {
  final bool success;
  final String message;

  const _CardLinkResult({required this.success, required this.message});
}

class _LinkCardDialog extends StatefulWidget {
  final _LinkInputMode initialMode;
  final Future<_CardLinkResult> Function(String rawValue) onSubmit;

  const _LinkCardDialog({required this.initialMode, required this.onSubmit});

  @override
  State<_LinkCardDialog> createState() => _LinkCardDialogState();
}

class _LinkCardDialogState extends State<_LinkCardDialog> {
  late _LinkInputMode _mode;
  late final TextEditingController _controller;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.onSubmit(_controller.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isQr = _mode == _LinkInputMode.qr;

    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vincular tarjeta TapLoop',
                style: GoogleFonts.outfit(
                  color: context.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pega la URL del QR o el serial NFC para conectar la tarjeta con este workspace.',
                style: GoogleFonts.dmSans(
                  color: context.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ModeChip(
                      label: 'QR / URL',
                      active: isQr,
                      onTap: () => setState(() => _mode = _LinkInputMode.qr),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeChip(
                      label: 'Código NFC',
                      active: !isQr,
                      onTap: () => setState(() => _mode = _LinkInputMode.code),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: isQr
                      ? 'https://.../nfc/ABC123 o ABC123'
                      : 'Ej. ABC123456',
                ),
              ),
              if (_error != null) ...[
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_submitting ? 'Vinculando...' : 'Vincular'),
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

class _ModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active ? context.bgSubtle : context.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? AppColors.primary : context.borderColor,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusMeta {
  final String label;
  final Color foreground;
  final Color background;

  const _StatusMeta({
    required this.label,
    required this.foreground,
    required this.background,
  });
}

_StatusMeta _statusMeta(LeadStatus status) {
  switch (status) {
    case LeadStatus.hot:
      return const _StatusMeta(
        label: 'Hot',
        foreground: Color(0xFFBA4E10),
        background: Color(0xFFFFE6D8),
      );
    case LeadStatus.warm:
      return const _StatusMeta(
        label: 'Warm',
        foreground: Color(0xFF6E59B2),
        background: Color(0xFFECE3FF),
      );
    case LeadStatus.cold:
      return const _StatusMeta(
        label: 'Cold',
        foreground: Color(0xFF31705A),
        background: Color(0xFFE1F5ED),
      );
  }
}

IconData _platformIcon(String platform) {
  switch (platform.toLowerCase()) {
    case 'linkedin':
      return Icons.business_center_outlined;
    case 'website':
      return Icons.language_rounded;
    case 'whatsapp':
      return Icons.chat_bubble_outline_rounded;
    case 'qr':
      return Icons.qr_code_rounded;
    case 'nfc':
      return Icons.nfc_rounded;
    case 'link':
      return Icons.link_rounded;
    case 'social':
      return Icons.alternate_email_rounded;
    case 'form':
      return Icons.description_outlined;
    default:
      return Icons.touch_app_outlined;
  }
}

String _eventTitle(VisitEventModel event) {
  switch ((event.source ?? '').toLowerCase()) {
    case 'nfc':
      return 'Tap NFC registrado';
    case 'qr':
      return 'Escaneo QR registrado';
    case 'form':
      return 'Formulario completado';
    case 'social':
      return 'Interacción social';
    case 'link':
      return 'Click en enlace';
    default:
      return 'Visita al perfil';
  }
}

String _pipelineLabel(String stage) {
  switch (stage) {
    case 'qualified':
      return 'Calificado';
    case 'proposal':
      return 'Propuesta';
    case 'won':
      return 'Cerrado';
    case 'contacted':
      return 'Contactado';
    default:
      return 'Nuevo lead';
  }
}

String _formatShortDate(DateTime date) {
  const months = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  return '${date.day} ${months[date.month - 1]}';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty);
  final list = parts.take(2).toList();
  if (list.isEmpty) return 'TL';
  if (list.length == 1) return list.first.substring(0, 1).toUpperCase();
  return '${list[0][0]}${list[1][0]}'.toUpperCase();
}

List<int> _deriveSeries(List<int> baseSeries, int total) {
  if (baseSeries.isEmpty || total <= 0) {
    return List<int>.filled(baseSeries.length, 0);
  }

  final baseTotal = baseSeries.fold<int>(0, (sum, value) => sum + value);
  if (baseTotal <= 0) {
    return List<int>.filled(baseSeries.length, 0);
  }

  final raw = baseSeries.map((value) => (value / baseTotal) * total).toList();
  final floored = raw.map((value) => value.floor()).toList();
  var remainder = total - floored.fold<int>(0, (sum, value) => sum + value);

  final order = List<int>.generate(raw.length, (index) => index)
    ..sort((a, b) => (raw[b] - floored[b]).compareTo(raw[a] - floored[a]));

  for (final index in order) {
    if (remainder <= 0) break;
    floored[index] += 1;
    remainder -= 1;
  }

  return floored;
}
