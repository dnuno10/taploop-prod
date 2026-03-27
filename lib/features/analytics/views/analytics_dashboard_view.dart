import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/analytics_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../analytics/models/analytics_summary_model.dart';
import '../../analytics/widgets/visit_event_tile.dart';
import '../../analytics/widgets/link_stats_bar.dart';
import '../../analytics/widgets/weekly_visits_chart.dart';
import 'lead_intelligence_view.dart';
import 'sales_outcome_view.dart';
import 'pipeline_view.dart';

class AnalyticsDashboardView extends StatefulWidget {
  const AnalyticsDashboardView({super.key});

  @override
  State<AnalyticsDashboardView> createState() => _AnalyticsDashboardViewState();
}

class _AnalyticsDashboardViewState extends State<AnalyticsDashboardView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  AnalyticsSummaryModel? _analytics;
  bool _loading = true;
  late DateTimeRange _range;
  int _loadVersion = 0;
  String? _loadedCardId;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeCardId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    appState.addListener(_onAppStateChanged);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 6)),
      end: now,
    );
    _bindRealtime();
    _load();
  }

  void _onAppStateChanged() {
    final cardId = appState.currentCard?.id;
    _bindRealtime();
    if (cardId == null || cardId == _loadedCardId) return;
    if (!mounted) return;
    setState(() => _loading = true);
    _load();
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
    final range = _range;
    final loadVersion = ++_loadVersion;
    if (cardId == null) {
      _loadedCardId = null;
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await AnalyticsRepository.fetchSummary(
        cardId,
        from: range.start,
        to: range.end,
      );
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _loadedCardId = cardId;
        _analytics = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _loadedCardId = cardId;
        _analytics = null;
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _analytics = null;
      _loading = true;
    });
    _load();
  }

  Future<void> _exportCsv() async {
    final analytics = _analytics;
    if (analytics == null) return;

    try {
      final rows = <List<dynamic>>[
        ['TapLoop - Metrics Report'],
        ['Rango', '${_fmtDate(_range.start)} - ${_fmtDate(_range.end)}'],
        [],
        ['Indicador', 'Valor'],
        ['Visitas', analytics.totalVisits],
        ['Taps NFC', analytics.totalTaps],
        ['Clicks', analytics.totalClicks],
        ['Interacciones totales', analytics.totalInteractions],
        ['Visitas en el rango', analytics.visitsThisWeek],
        ['Visitas período anterior', analytics.visitsLastWeek],
        [
          'Crecimiento de interacciones %',
          analytics.interactionsGrowthPercent.toStringAsFixed(1),
        ],
        [],
        ['Visitas por día', ''],
        ['Fecha', 'Visitas'],
      ];

      for (var i = 0; i < analytics.visitsByDay.length; i++) {
        final date = _range.end.subtract(
          Duration(days: analytics.visitsByDay.length - 1 - i),
        );
        rows.add([_fmtDate(date), analytics.visitsByDay[i]]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final bytes = Uint8List.fromList(csv.codeUnits);
      final fileName = 'taploop_metrics_${DateTime.now().millisecondsSinceEpoch}';

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );

      if (!mounted) return;
      TapLoopToast.show(context, 'CSV exportado correctamente.', TapLoopToastType.success);
    } catch (e) {
      if (!mounted) return;
      TapLoopToast.show(context, 'Error al exportar CSV. Intenta nuevamente.', TapLoopToastType.error);
    }
  }

  Future<void> _exportPdf() async {
    final analytics = _analytics;
    if (analytics == null) return;

    try {
      final pdf = pw.Document();
      final generatedAt = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (context) => [
            pw.Text(
              'TapLoop - Reporte de Métricas',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Rango: ${_fmtDate(_range.start)} - ${_fmtDate(_range.end)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Generado: ${generatedAt.day}/${generatedAt.month}/${generatedAt.year}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor(0.11, 0.31, 0.85),
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              headers: ['Indicador', 'Valor'],
              data: [
                ['Visitas', '${analytics.totalVisits}'],
                ['Taps NFC', '${analytics.totalTaps}'],
                ['Clicks', '${analytics.totalClicks}'],
                ['Interacciones totales', '${analytics.totalInteractions}'],
                ['Visitas en el rango', '${analytics.visitsThisWeek}'],
                ['Visitas período anterior', '${analytics.visitsLastWeek}'],
                [
                  'Crecimiento de interacciones',
                  '${analytics.interactionsGrowthPercent.toStringAsFixed(1)}%',
                ],
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Visitas por día',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              headers: ['Fecha', 'Visitas'],
              data: [
                for (var i = 0; i < analytics.visitsByDay.length; i++)
                  [
                    _fmtDate(
                      _range.end.subtract(
                        Duration(days: analytics.visitsByDay.length - 1 - i),
                      ),
                    ),
                    '${analytics.visitsByDay[i]}',
                  ],
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final fileName = 'taploop_metrics_${DateTime.now().millisecondsSinceEpoch}';

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (!mounted) return;
      TapLoopToast.show(context, 'PDF exportado correctamente.', TapLoopToastType.success);
    } catch (e) {
      if (!mounted) return;
      TapLoopToast.show(context, 'Error al exportar PDF. Intenta nuevamente.', TapLoopToastType.error);
    }
  }

  static String _fmtDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    final isDesktop = Responsive.isDesktop(context);
    final isMobile = Responsive.isMobile(context);
    final hasLinkedCard = appState.currentCard != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              decoration: BoxDecoration(
                color: context.bgCard,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: isDesktop ? 320 : 240,
                      maxWidth: isDesktop ? 480 : double.infinity,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Analíticas',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Monitorea visitas, taps, leads y rendimiento comercial en un solo panel.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasLinkedCard) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _PeriodChip(
                          label:
                              '${_fmtDate(_range.start)} – ${_fmtDate(_range.end)}',
                          onTap: _pickRange,
                        ),
                        _ExportActionButton(
                          label: 'CSV',
                          icon: Icons.table_chart_outlined,
                          onTap: _loading || _analytics == null
                              ? null
                              : _exportCsv,
                        ),
                        _ExportActionButton(
                          label: 'PDF',
                          icon: Icons.picture_as_pdf_outlined,
                          onTap: _loading || _analytics == null
                              ? null
                              : _exportPdf,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: context.bgCard,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: TabBar(
                          controller: _tab,
                          isScrollable: true,
                          tabs: const [
                            Tab(text: 'Métricas'),
                            Tab(text: 'Leads'),
                            Tab(text: 'Pipeline'),
                            Tab(text: 'Ventas'),
                          ],
                          indicator: BoxDecoration(
                            color: context.bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.borderColor),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: context.textPrimary,
                          unselectedLabelColor: context.textSecondary,
                          labelStyle: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          tabAlignment: TabAlignment.start,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: context.bgPage,
                child: hasLinkedCard
                    ? TabBarView(
                        controller: _tab,
                        children: [
                          // ── Mis métricas ────────────────────────────────────────────────
                          SingleChildScrollView(
                            child: _loading
                                ? const SizedBox(
                                    height: 300,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : analytics == null
                                ? const SizedBox(
                                    height: 300,
                                    child: Center(child: Text('Sin datos')),
                                  )
                                : isDesktop
                                ? _DesktopLayout(
                                    analytics: analytics,
                                    rangeEnd: _range.end,
                                  )
                                : _MobileLayout(
                                    analytics: analytics,
                                    isMobile: isMobile,
                                    rangeEnd: _range.end,
                                  ),
                          ),
                          const _AnalyticsTabPanel(
                            child: LeadIntelligenceView(),
                          ),
                          const _AnalyticsTabPanel(child: PipelineView()),
                          const _AnalyticsTabPanel(child: SalesOutcomeView()),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                        child: CardInitialSetupState(
                          onLinked: () => setState(() {}),
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

class _AnalyticsTabPanel extends StatelessWidget {
  final Widget child;

  const _AnalyticsTabPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.borderColor),
        ),
        clipBehavior: Clip.hardEdge,
        child: child,
      ),
    );
  }
}

// ─── Layouts ─────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  final bool isMobile;
  final DateTime rangeEnd;
  const _MobileLayout({
    required this.analytics,
    required this.isMobile,
    required this.rangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final px = isMobile ? 20.0 : 40.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: px, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TotalBlock(analytics: analytics),
            const SizedBox(height: 32),
            _MetricRow(analytics: analytics),
            const SizedBox(height: 40),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 36),
            _ChartBlock(analytics: analytics, rangeEnd: rangeEnd),
            const SizedBox(height: 40),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 36),
            _LinksBlock(analytics: analytics),
            const SizedBox(height: 40),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 36),
            _ActivityBlock(analytics: analytics),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  final DateTime rangeEnd;
  const _DesktopLayout({required this.analytics, required this.rangeEnd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TotalBlock(analytics: analytics),
                    const SizedBox(height: 24),
                    _MetricRow(analytics: analytics),
                    const SizedBox(height: 28),
                    _ChartBlock(analytics: analytics, rangeEnd: rangeEnd),
                    const SizedBox(height: 28),
                    _LinksBlock(analytics: analytics),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Container(
              width: 320,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: context.borderColor)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: _ActivityBlock(analytics: analytics),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTrendValue(double value) {
  final prefix = value >= 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}%';
}

// ─── Total Block ─────────────────────────────────────────────────────────────

class _TotalBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _TotalBlock({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final total = analytics.totalInteractions;
    final trendColor = analytics.interactionsGrowing
        ? AppColors.success
        : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Interacciones totales',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$total',
            style: GoogleFonts.outfit(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      analytics.interactionsGrowing
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 11,
                      color: trendColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatTrendValue(analytics.interactionsGrowthPercent),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'vs período anterior',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Metric Row ───────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _MetricRow({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final items = [
      _MetricItem(
        label: 'Visitas',
        value: '${analytics.totalVisits}',
        icon: Icons.visibility_outlined,
        trend: _formatTrendValue(analytics.visitsGrowthPercent),
        positive: analytics.visitsGrowthPercent >= 0,
      ),
      _MetricItem(
        label: 'Taps NFC',
        value: '${analytics.totalTaps}',
        icon: Icons.nfc_outlined,
        trend: _formatTrendValue(analytics.tapsGrowthPercent),
        positive: analytics.tapsGrowthPercent >= 0,
      ),
      _MetricItem(
        label: 'Clicks',
        value: '${analytics.totalClicks}',
        icon: Icons.ads_click_outlined,
        trend: _formatTrendValue(analytics.clicksGrowthPercent),
        positive: analytics.clicksGrowthPercent >= 0,
      ),
    ];

    if (isMobile) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final gap = 10.0;
          final colWidth = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(
                width: colWidth,
                child: _MetricCompactCard(item: items[0]),
              ),
              SizedBox(
                width: colWidth,
                child: _MetricCompactCard(item: items[1]),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: _MetricCompactCard(item: items[2]),
              ),
            ],
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: items
            .asMap()
            .entries
            .map(
              (e) => Expanded(
                child: Row(
                  children: [
                    Expanded(child: _MetricCell(item: e.value)),
                    if (e.key < items.length - 1)
                      Container(
                        width: 1,
                        height: 52,
                        color: context.borderColor,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MetricItem {
  final String label, value, trend;
  final IconData icon;
  final bool positive;
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.trend,
    required this.positive,
  });
}

class _MetricCell extends StatelessWidget {
  final _MetricItem item;
  const _MetricCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(item.icon, size: 13, color: context.textMuted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                item.label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: context.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          item.value,
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.trend,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: item.positive ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }
}

class _MetricCompactCard extends StatelessWidget {
  final _MetricItem item;
  const _MetricCompactCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 13, color: context.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  item.label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.trend,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: item.positive ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chart Block ─────────────────────────────────────────────────────────────

class _ChartBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  final DateTime rangeEnd;
  const _ChartBlock({required this.analytics, required this.rangeEnd});

  @override
  Widget build(BuildContext context) {
    final trendColor = analytics.visitsGrowthPercent >= 0
        ? AppColors.success
        : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Visitas por día',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${analytics.totalVisits} en el rango',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      analytics.visitsGrowthPercent >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 13,
                      color: trendColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTrendValue(analytics.visitsGrowthPercent),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: WeeklyVisitsChart(
              visitsByDay: analytics.visitsByDay,
              referenceDate: rangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Links Block ─────────────────────────────────────────────────────────────

class _LinksBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _LinksBlock({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Links más clickeados',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${analytics.totalClicks} clicks totales',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(analytics.linkStats.length, (i) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: i == 0 ? AppColors.primary : context.textMuted,
                        ),
                      ),
                    ),
                    Expanded(child: LinkStatsBar(stat: analytics.linkStats[i])),
                  ],
                ),
                if (i < analytics.linkStats.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: context.borderColor, height: 1),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─── Activity Block ───────────────────────────────────────────────────────────

class _ActivityBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _ActivityBlock({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actividad reciente',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Últimas interacciones con tu tarjeta',
            style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
          ),
          const SizedBox(height: 20),
          ...List.generate(
              analytics.recentEvents.length > 10
                  ? 10
                  : analytics.recentEvents.length,
              (i) {
            return Column(
              children: [
                VisitEventTile(event: analytics.recentEvents[i]),
                if (i < analytics.recentEvents.length - 1)
                  Divider(color: context.borderColor, height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─── Period Chip ──────────────────────────────────────────────────────────────

class _PeriodChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PeriodChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 15,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _ExportActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
