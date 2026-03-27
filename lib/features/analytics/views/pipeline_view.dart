import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/lead_model.dart';

// ─── Main view ────────────────────────────────────────────────────────────────

enum _PipelineStage { proposals, closed }

class PipelineView extends StatefulWidget {
  const PipelineView({super.key});

  @override
  State<PipelineView> createState() => _PipelineViewState();
}

class _PipelineViewState extends State<PipelineView> {
  List<LeadModel> _leads = [];
  bool _loading = true;
  String? _loadedCardId;
  _PipelineStage _selectedStage = _PipelineStage.proposals;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeCardId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _loadLeads();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final cardId = appState.currentCard?.id;
    _bindRealtime();
    if (cardId == _loadedCardId) return;
    if (!mounted) return;
    setState(() => _loading = true);
    _loadLeads();
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
        _loadLeads();
      },
    );
  }

  Future<void> _loadLeads() async {
    final cardId = appState.currentCard?.id;
    if (cardId == null) {
      if (mounted) {
        setState(() {
          _loadedCardId = null;
          _leads = [];
          _loading = false;
        });
      }
      return;
    }
    try {
      final data = await LeadRepository.fetchLeadsForCard(cardId);
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _leads = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _loading = false;
        });
      }
    }
  }

  Future<void> _markConverted(LeadModel lead) async {
    try {
      await LeadRepository.markConverted(lead.id, true);
      await _loadLeads();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Lead marcado como venta correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'Error al guardar: $e',
          TapLoopToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final proposals = _leads.where((l) => !l.isConverted).toList();
    final closed = _leads.where((l) => l.isConverted).toList();
    final activeLeads = _selectedStage == _PipelineStage.proposals
        ? proposals
        : closed;
    final filteredLeads = _search.trim().isEmpty
        ? activeLeads
        : activeLeads.where((lead) {
            final q = _search.trim().toLowerCase();
            final name = lead.displayName.toLowerCase();
            final company = (lead.company ?? '').toLowerCase();
            return name.contains(q) || company.contains(q);
          }).toList();
    final activeLabel = _selectedStage == _PipelineStage.proposals
        ? 'Propuestas enviadas'
        : 'Cerrados';
    final emptyMessage = _selectedStage == _PipelineStage.proposals
        ? 'No hay propuestas pendientes por cerrar'
        : 'Sin ventas cerradas aún';
    final useProposalWhiteSurface =
        !context.isDark && _selectedStage == _PipelineStage.proposals;

    return CustomScrollView(
      slivers: [
        // ── Header + Stats ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _PipelineHeader(
            total: _leads.length,
            proposals: proposals.length,
            closed: closed.length,
            selected: _selectedStage,
            onSelected: (stage) => setState(() => _selectedStage = stage),
          ),
        ),

        // ── Active Stage ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _SectionLabel(
            label: activeLabel,
            count: filteredLeads.length,
            solidSurface: useProposalWhiteSurface,
          ),
        ),
        if (_selectedStage == _PipelineStage.proposals)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                maxLength: 200,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar propuesta por nombre o empresa...',
                  hintStyle: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textMuted,
                  ),
                  counterText: '',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: context.textMuted,
                  ),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: context.textMuted,
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                        ),
                  filled: true,
                  fillColor: useProposalWhiteSurface
                      ? Colors.white
                      : (context.isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.white.withValues(alpha: 0.68)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (filteredLeads.isEmpty)
          SliverToBoxAdapter(
            child: _EmptyHint(
              message: emptyMessage,
              solidSurface: useProposalWhiteSurface,
            ),
          )
        else if (_selectedStage == _PipelineStage.proposals)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 460,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 166,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _LeadCard(
                  lead: filteredLeads[i],
                  solidSurface: useProposalWhiteSurface,
                  onMarkClosed: () => _markConverted(filteredLeads[i]),
                ),
                childCount: filteredLeads.length,
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _LeadCard(
                  lead: filteredLeads[i],
                  solidSurface: false,
                  onMarkClosed: null,
                ),
              ),
              childCount: filteredLeads.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _PipelineHeader extends StatelessWidget {
  final int total;
  final int proposals;
  final int closed;
  final _PipelineStage selected;
  final ValueChanged<_PipelineStage> onSelected;

  const _PipelineHeader({
    required this.total,
    required this.proposals,
    required this.closed,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final conversionRate = total == 0 ? 0.0 : closed / total;

    return Container(
      color: context.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pipeline',
            style: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sigue cada oportunidad de forma simple',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatTile(
                value: '$total',
                label: 'Total',
                icon: Icons.people_outline_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: '$proposals',
                label: 'Propuestas',
                icon: Icons.description_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: '$closed',
                label: 'Cerrados',
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF16A34A),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Conversión',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${(conversionRate * 100).round()}%',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: conversionRate.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: context.bgSubtle,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _StageFilterChip(
                label: 'Por cerrar',
                count: proposals,
                active: selected == _PipelineStage.proposals,
                onTap: () => onSelected(_PipelineStage.proposals),
              ),
              _StageFilterChip(
                label: 'Cerrados',
                count: closed,
                active: selected == _PipelineStage.closed,
                onTap: () => onSelected(_PipelineStage.closed),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: context.borderColor, height: 1),
        ],
      ),
    );
  }
}

class _StageFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _StageFilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.14)
                : (context.isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.white.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primary : context.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.primary : context.textSecondary,
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

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: context.textPrimary,
                height: 0.95,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  final bool solidSurface;

  const _SectionLabel({
    required this.label,
    required this.count,
    required this.solidSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textMuted,
                letterSpacing: 0.35,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: solidSurface
                  ? Colors.white
                  : (context.isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.white.withValues(alpha: 0.62)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final String message;
  final bool solidSurface;

  const _EmptyHint({required this.message, required this.solidSurface});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: solidSurface
              ? Colors.white
              : (context.isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.62)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            message,
            style: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
          ),
        ),
      ),
    );
  }
}

// ─── Lead Card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatelessWidget {
  final LeadModel lead;
  final bool solidSurface;
  final VoidCallback? onMarkClosed;

  const _LeadCard({
    required this.lead,
    required this.solidSurface,
    required this.onMarkClosed,
  });

  String _latestActionLabel(LeadModel lead) {
    if (lead.actions.isEmpty) return 'Sin actividad registrada';
    final latest = [...lead.actions]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final action = latest.first;
    switch (action.action) {
      case LeadAction.visitedProfile:
        return 'Visitó el perfil digital';
      case LeadAction.clickedLinkedIn:
        return 'Hizo click en LinkedIn';
      case LeadAction.clickedWebsite:
        return 'Hizo click en Sitio web';
      case LeadAction.clickedWhatsApp:
        return 'Hizo click en WhatsApp';
      case LeadAction.downloadedContact:
        return 'Descargó el contacto';
      case LeadAction.filledForm:
        return 'Hizo el llenado del formulario';
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysSince = DateTime.now().difference(lead.lastSeen).inDays;
    final hasForm = lead.formData != null && lead.formData!.isNotEmpty;
    final timeLabel = daysSince == 0
        ? 'Hoy'
        : daysSince == 1
        ? 'Ayer'
        : 'Hace $daysSince días';

    return Container(
      decoration: BoxDecoration(
        color: solidSurface
            ? Colors.white
            : (context.isDark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.white.withValues(alpha: 0.58)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.displayName,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (lead.company != null && lead.company!.isNotEmpty)
                          lead.company!,
                        timeLabel,
                      ].join(' • '),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _latestActionLabel(lead),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (lead.isConverted)
                _MetaChip(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Cerrado',
                  color: AppColors.success,
                ),
            ],
          ),
          if (hasForm || onMarkClosed != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (hasForm) Expanded(child: _FormDataButton(lead: lead)),
                if (hasForm && onMarkClosed != null) const SizedBox(width: 8),
                if (onMarkClosed != null)
                  Expanded(child: _MarkClosedButton(onTap: onMarkClosed!)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Mark Closed Button ───────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? context.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkClosedButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MarkClosedButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFF15803D).withValues(alpha: 0.1)
                : const Color(0xFF15803D).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.attach_money_rounded,
                size: 14,
                color: const Color(0xFF15803D),
              ),
              const SizedBox(width: 5),
              Text(
                'Mover a cerrados',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF15803D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Form Data Button + Dialog ────────────────────────────────────────────────

class _FormDataButton extends StatelessWidget {
  final LeadModel lead;
  const _FormDataButton({required this.lead});

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible abrir la acción.')),
      );
    }
  }

  Future<void> _saveLeadSummary(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln('Lead: ${lead.displayName}');
    buffer.writeln('Formulario: ${_formTitle(lead.formType)}');
    for (final entry in data.entries) {
      final key = entry.key;
      final value = (entry.value ?? '').toString().trim();
      if (key.startsWith('_') || value.isEmpty) continue;
      buffer.writeln('$key: $value');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Información copiada para guardar contacto.'),
        ),
      );
    }
  }

  bool _isEmailField(String key, String value) {
    final mailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final lowerKey = key.toLowerCase();
    return mailRegex.hasMatch(value) ||
        ((lowerKey.contains('correo') || lowerKey.contains('email')) &&
            value.contains('@'));
  }

  bool _isPhoneField(String key, String value) {
    final phoneRegex = RegExp(r'\+?\d[\d\s\-\(\)]{7,}');
    final lowerKey = key.toLowerCase();
    return phoneRegex.hasMatch(value) ||
        lowerKey.contains('telefono') ||
        lowerKey.contains('teléfono') ||
        lowerKey.contains('phone') ||
        lowerKey.contains('whatsapp');
  }

  Future<void> _copyField(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dato copiado.')));
    }
  }

  String _formTitle(String? formType) {
    switch (formType) {
      case 'cotizacion':
        return 'Solicitar cotización';
      case 'demo':
        return 'Agendar demo';
      case 'catalogo':
        return 'Descargar catálogo';
      case 'contacto':
        return 'Formulario de contacto';
      case 'propuesta':
        return 'Solicitar propuesta';
      default:
        return 'Formulario';
    }
  }

  void _show(BuildContext context) {
    final data = lead.formData!;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.assignment_ind_outlined,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formTitle(lead.formType),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: ctx.textPrimary,
                            ),
                          ),
                          Text(
                            lead.displayName,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              color: ctx.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: ctx.textMuted,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Divider(color: ctx.borderColor, height: 1),
              ),
              // ── Fields ──────────────────────────────────────────────
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  shrinkWrap: true,
                  children: [
                    for (final entry in data.entries)
                      if (!(entry.key.startsWith('_')) &&
                          ((entry.value as String?)?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Builder(
                            builder: (_) {
                              final key = entry.key;
                              final value = (entry.value ?? '') as String;
                              final isEmail = _isEmailField(key, value);
                              final isPhone = _isPhoneField(key, value);
                              final cleanPhone = value.replaceAll(
                                RegExp(r'[^0-9+]'),
                                '',
                              );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          key,
                                          style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: ctx.textMuted,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                      if (isEmail)
                                        _FieldCornerAction(
                                          icon: Icons.alternate_email_rounded,
                                          color: AppColors.primary,
                                          onTap: () =>
                                              _launch(context, 'mailto:$value'),
                                        ),
                                      if (isPhone)
                                        _FieldCornerAction(
                                          icon: Icons.call_outlined,
                                          color: const Color(0xFF16A34A),
                                          onTap: () => _launch(
                                            context,
                                            'tel:$cleanPhone',
                                          ),
                                        ),
                                      if (isPhone)
                                        _FieldCornerAction(
                                          icon:
                                              Icons.chat_bubble_outline_rounded,
                                          color: const Color(0xFF16A34A),
                                          onTap: () => _launch(
                                            context,
                                            'https://wa.me/$cleanPhone',
                                          ),
                                        ),
                                      _FieldCornerAction(
                                        icon: Icons.content_copy_rounded,
                                        color: context.textSecondary,
                                        onTap: () => _copyField(context, value),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ctx.bgSubtle,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: ctx.borderColor,
                                      ),
                                    ),
                                    child: Text(
                                      value,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        color: ctx.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _DialogPrimaryAction(
                    icon: Icons.save_alt_rounded,
                    label: 'Guardar contacto',
                    onTap: () => _saveLeadSummary(context, data),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFF1D4ED8).withValues(alpha: 0.1)
                : const Color(0xFF1D4ED8).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assignment_ind_outlined,
                size: 13,
                color: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 5),
              Text(
                'Ver formulario',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogPrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DialogPrimaryAction({
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: context.isDark
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldCornerAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FieldCornerAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: context.isDark
                  ? color.withValues(alpha: 0.1)
                  : color.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
        ),
      ),
    );
  }
}
