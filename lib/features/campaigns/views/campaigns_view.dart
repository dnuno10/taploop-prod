import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/campaign_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../analytics/models/visit_event_model.dart';
import '../models/campaign_model.dart';

String _fmtDate(DateTime d) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _fmtShortDate(DateTime d) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

class CampaignsView extends StatefulWidget {
  const CampaignsView({super.key});

  @override
  State<CampaignsView> createState() => _CampaignsViewState();
}

class _CampaignsViewState extends State<CampaignsView> {
  static final RegExp _uuidPattern = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );
  List<CampaignModel> _campaigns = [];
  bool _loading = true;
  String? _loadedOrgId;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeOrgId;

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
    final orgId = appState.currentUser?.orgId;
    _bindRealtime();
    if (orgId != _loadedOrgId) {
      _load();
    }
    if (!mounted) return;
    setState(() {});
  }

  void _bindRealtime() {
    final orgId = appState.currentUser?.orgId;
    if (orgId == _realtimeOrgId) return;
    _metricsRealtime?.close();
    _realtimeOrgId = orgId;
    if (orgId == null || orgId.isEmpty) return;
    _metricsRealtime = MetricsRealtimeSubscription.forOrganization(
      orgId: orgId,
      onRefresh: () {
        if (!mounted) return;
        _load();
      },
    );
  }

  Future<void> _load() async {
    try {
      final orgId = appState.currentUser?.orgId;
      final data = await CampaignRepository.fetchCampaignsForUser(orgId: orgId);
      if (mounted) {
        setState(() {
          _loadedOrgId = orgId;
          _campaigns = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadedOrgId = appState.currentUser?.orgId;
          _loading = false;
        });
      }
    }
  }

  Future<String> _friendlyCampaignErrorMessage(
    Object error, {
    String? orgId,
  }) async {
    final raw = error.toString();
    final normalized = raw.replaceAll('\n', ' ').trim();

    final userNameById = <String, String>{};
    if (orgId != null && orgId.isNotEmpty) {
      try {
        final users = await CampaignRepository.fetchOrgUsers(orgId);
        for (final user in users) {
          final id = user['id'];
          final name = user['name'];
          if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
            userNameById[id] = name;
          }
        }
      } catch (_) {}
    }

    final campaignNameById = <String, String>{
      for (final campaign in _campaigns) campaign.id: campaign.name,
    };
    if (orgId != null &&
        orgId.isNotEmpty &&
        _uuidPattern
            .allMatches(normalized)
            .map((m) => m.group(0)!)
            .any((id) => !campaignNameById.containsKey(id))) {
      try {
        final campaigns = await CampaignRepository.fetchCampaignsForUser(
          orgId: orgId,
        );
        for (final campaign in campaigns) {
          campaignNameById[campaign.id] = campaign.name;
        }
      } catch (_) {}
    }

    final ids = _uuidPattern
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .toList();
    final matchedUserId = ids.cast<String?>().firstWhere(
      (id) => id != null && userNameById.containsKey(id),
      orElse: () => null,
    );
    final matchedCampaignId = ids.cast<String?>().firstWhere(
      (id) => id != null && campaignNameById.containsKey(id),
      orElse: () => null,
    );

    if (normalized.toLowerCase().contains('horario traslapado')) {
      final userName = matchedUserId == null
          ? 'Este miembro'
          : userNameById[matchedUserId]!;
      final campaignName = matchedCampaignId == null
          ? 'otra campaña'
          : '"${campaignNameById[matchedCampaignId]!}"';
      return '$userName ya pertenece a $campaignName en un horario traslapado. Ajusta el horario o cambia el miembro seleccionado.';
    }

    var cleaned = normalized
        .replaceFirst(RegExp(r'^[A-Za-z]+Exception\(message:\s*'), '')
        .replaceFirst(RegExp(r',\s*code:.*$'), '')
        .trim();

    userNameById.forEach((id, name) {
      cleaned = cleaned.replaceAll(id, name);
    });
    campaignNameById.forEach((id, name) {
      cleaned = cleaned.replaceAll(id, name);
    });

    if (cleaned.isEmpty || cleaned == normalized) {
      return 'No se pudo guardar la campaña. Revisa los datos e inténtalo de nuevo.';
    }
    return cleaned;
  }

  void _showNewCampaignSheet() {
    Future<void> onSave(_CampaignEditorResult result) async {
      final orgId = appState.currentUser?.orgId;
      if (orgId == null || orgId.isEmpty) {
        if (mounted) {
          TapLoopToast.show(
            context,
            'Tu cuenta no tiene una organización asignada.',
            TapLoopToastType.warning,
          );
        }
        return;
      }
      try {
        final created = await CampaignRepository.createCampaign(
          result.campaign,
          orgId,
        );
        final memberIds = result.members
            .map((member) => member.userId)
            .toList();
        try {
          await CampaignRepository.addCampaignMembers(created.id, memberIds);
        } catch (memberError) {
          await CampaignRepository.deleteCampaign(created.id);
          rethrow;
        }
        await _load();
        if (!mounted) return;
        TapLoopToast.show(
          context,
          'Campaña creada correctamente.',
          TapLoopToastType.success,
        );
      } catch (e) {
        if (mounted) {
          final message = await _friendlyCampaignErrorMessage(e, orgId: orgId);
          if (!mounted) return;
          TapLoopToast.show(context, message, TapLoopToastType.error);
        }
      }
    }

    if (!Responsive.isMobile(context)) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: _NewCampaignSheet(isDialog: true, onSave: onSave),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _NewCampaignSheet(isDialog: false, onSave: onSave),
      );
    }
  }

  void _showEditCampaignSheet(CampaignModel campaign) {
    Future<void> onSave(_CampaignEditorResult result) async {
      try {
        final updated = await CampaignRepository.updateCampaign(
          result.campaign,
        );
        if (campaign.status != CampaignStatus.finished) {
          await CampaignRepository.replaceCampaignMembers(
            updated.id,
            result.members.map((member) => member.userId).toList(),
          );
        }
        final hydrated = updated.copyWith(
          assignedMemberNames: campaign.status == CampaignStatus.finished
              ? campaign.assignedMemberNames
              : result.members.map((member) => member.name).toList(),
          memberRoles: campaign.status == CampaignStatus.finished
              ? campaign.memberRoles
              : result.campaign.memberRoles,
        );
        if (mounted) {
          setState(() {
            final idx = _campaigns.indexWhere((x) => x.id == updated.id);
            if (idx != -1) _campaigns[idx] = hydrated;
          });
        }
      } catch (e) {
        if (mounted) {
          final message = await _friendlyCampaignErrorMessage(
            e,
            orgId: campaign.orgId ?? appState.currentUser?.orgId,
          );
          if (!mounted) return;
          TapLoopToast.show(context, message, TapLoopToastType.error);
        }
      }
    }

    if (!Responsive.isMobile(context)) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: _NewCampaignSheet(
            isDialog: true,
            onSave: onSave,
            existing: campaign,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _NewCampaignSheet(
          isDialog: false,
          onSave: onSave,
          existing: campaign,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLinkedCard = appState.currentCard != null;
    final active = _campaigns
        .where((c) => c.status == CampaignStatus.active)
        .toList();
    final upcoming = _campaigns
        .where((c) => c.status == CampaignStatus.upcoming)
        .toList();
    final finished = _campaigns
        .where((c) => c.status == CampaignStatus.finished)
        .toList();
    final hasCampaigns = _campaigns.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: context.bgCard,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Campañas',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Planea eventos, asigna equipo y centraliza las interacciones de cada campaña.',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!hasLinkedCard)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: CardInitialSetupState(onLinked: () => setState(() {})),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _CampaignOverviewPanel(
                  campaigns: _campaigns,
                  onCreate: _showNewCampaignSheet,
                ),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!hasCampaigns)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                  child: _CampaignEmptyState(onCreate: _showNewCampaignSheet),
                ),
              )
            else ...[
              if (active.isNotEmpty) ...[
                _SectionHeader(label: 'Activas', count: active.length),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _CampaignCard(
                        campaign: active[i],
                        onDeleted: () => setState(
                          () => _campaigns.removeWhere(
                            (c) => c.id == active[i].id,
                          ),
                        ),
                        onUpdated: (u) => setState(() {
                          final idx = _campaigns.indexWhere(
                            (c) => c.id == u.id,
                          );
                          if (idx != -1) _campaigns[idx] = u;
                        }),
                        onEdit: () => _showEditCampaignSheet(active[i]),
                      ),
                      childCount: active.length,
                    ),
                  ),
                ),
              ],

              if (upcoming.isNotEmpty) ...[
                _SectionHeader(label: 'Próximas', count: upcoming.length),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _CampaignCard(
                        campaign: upcoming[i],
                        onDeleted: () => setState(
                          () => _campaigns.removeWhere(
                            (c) => c.id == upcoming[i].id,
                          ),
                        ),
                        onUpdated: (u) => setState(() {
                          final idx = _campaigns.indexWhere(
                            (c) => c.id == u.id,
                          );
                          if (idx != -1) _campaigns[idx] = u;
                        }),
                        onEdit: () => _showEditCampaignSheet(upcoming[i]),
                      ),
                      childCount: upcoming.length,
                    ),
                  ),
                ),
              ],

              if (finished.isNotEmpty) ...[
                _SectionHeader(label: 'Terminadas', count: finished.length),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _CampaignCard(
                        campaign: finished[i],
                        onDeleted: () => setState(
                          () => _campaigns.removeWhere(
                            (c) => c.id == finished[i].id,
                          ),
                        ),
                        onUpdated: (u) => setState(() {
                          final idx = _campaigns.indexWhere(
                            (c) => c.id == u.id,
                          );
                          if (idx != -1) _campaigns[idx] = u;
                        }),
                        onEdit: () => _showEditCampaignSheet(finished[i]),
                      ),
                      childCount: finished.length,
                    ),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Summary Strip ────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final List<CampaignModel> campaigns;
  const _SummaryStrip({required this.campaigns});

  @override
  Widget build(BuildContext context) {
    final active = campaigns
        .where((campaign) => campaign.status == CampaignStatus.active)
        .length;
    final upcoming = campaigns
        .where((campaign) => campaign.status == CampaignStatus.upcoming)
        .length;
    final finished = campaigns
        .where((campaign) => campaign.status == CampaignStatus.finished)
        .length;
    final withSchedule = campaigns
        .where(
          (campaign) =>
              (campaign.startTime?.isNotEmpty ?? false) ||
              (campaign.endTime?.isNotEmpty ?? false),
        )
        .length;

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.subtleShadow,
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          _Metric(label: 'Campañas', value: '${campaigns.length}'),
          _VertDivider(),
          _Metric(label: 'Activas', value: '$active'),
          _VertDivider(),
          _Metric(label: 'Próximas', value: '$upcoming'),
          _VertDivider(),
          _Metric(label: 'Terminadas', value: '$finished'),
          _VertDivider(),
          _Metric(label: 'Con horario', value: '$withSchedule'),
        ],
      ),
    );
  }
}

class _CampaignOverviewPanel extends StatelessWidget {
  final List<CampaignModel> campaigns;
  final VoidCallback onCreate;

  const _CampaignOverviewPanel({
    required this.campaigns,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cómo funciona',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cada campaña reúne tres piezas: cuándo sucede, quién participa y qué interacciones deben quedar agrupadas.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        height: 1.45,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Crear campaña'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _CampaignFlowSteps(),
          const SizedBox(height: 18),
          _SummaryStrip(campaigns: campaigns),
        ],
      ),
    );
  }
}

class _CampaignFlowSteps extends StatelessWidget {
  const _CampaignFlowSteps();

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        '1. Programa',
        'Define fecha, lugar y horario para saber cuándo aplica la campaña.',
      ),
      (
        '2. Asigna equipo',
        'Selecciona a los usuarios que participarán en esa operación.',
      ),
      (
        '3. Da seguimiento',
        'Consulta la campaña correcta sin mezclar actividades de otros eventos.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width > 900
            ? (width - 24) / 3
            : width > 560
            ? (width - 12) / 2
            : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: steps
              .map(
                (step) => SizedBox(
                  width: itemWidth,
                  child: _FlowStepCard(title: step.$1, description: step.$2),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _FlowStepCard extends StatelessWidget {
  final String title;
  final String description;

  const _FlowStepCard({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDark
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.isDark
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              height: 1.4,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CampaignEmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _CampaignEmptyState({required this.onCreate});

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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.campaign_outlined,
            color: AppColors.primary,
            size: 34,
          ),
          const SizedBox(height: 18),
          Text(
            'Aún no hay campañas creadas',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Empieza con una campaña simple: fecha, horario y el equipo que participará. Después podrás revisar su seguimiento sin mezclarla con otras.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              height: 1.5,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear primera campaña'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: context.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: context.borderColor);
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Campaign Card ────────────────────────────────────────────────────────────

class _CampaignCard extends StatefulWidget {
  final CampaignModel campaign;
  final VoidCallback? onDeleted;
  final void Function(CampaignModel)? onUpdated;
  final VoidCallback? onEdit;

  const _CampaignCard({
    required this.campaign,
    this.onDeleted,
    this.onUpdated,
    this.onEdit,
  });

  @override
  State<_CampaignCard> createState() => _CampaignCardState();
}

class _CampaignCardState extends State<_CampaignCard> {
  bool _expanded = false;

  Future<void> _handleDelete(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar campaña'),
        content: Text(
          '¿Eliminar "${widget.campaign.name}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CampaignRepository.deleteCampaign(widget.campaign.id);
      widget.onDeleted?.call();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campaign;
    final memberCount = c.memberRoles.isNotEmpty
        ? c.memberRoles.length
        : c.assignedMemberNames.length;
    final scheduleLabel = _formatTimeRange(c.startTime, c.endTime);
    final infoItems = <_DetailInfoData>[
      _DetailInfoData('Tipo', c.eventType ?? 'Sin definir'),
      _DetailInfoData('Objetivo', c.objective?.label ?? 'Sin definir'),
      _DetailInfoData('Zona', c.zone ?? 'Sin definir'),
      _DetailInfoData(
        'Horario',
        _formatTimeRange(c.startTime, c.endTime) ?? 'Sin definir',
      ),
      _DetailInfoData(
        'Duración',
        _formatDuration(c.durationMinutes) ?? 'Sin definir',
      ),
      _DetailInfoData(
        'Meta leads',
        c.leadGoal != null ? '${c.leadGoal}' : 'Sin definir',
      ),
    ];
    final overviewTags = <Widget>[
      _InfoPill(
        icon: Icons.calendar_today_outlined,
        label: _fmtDate(c.eventDate),
      ),
      if (scheduleLabel != null)
        _InfoPill(icon: Icons.schedule_outlined, label: scheduleLabel),
      _InfoPill(
        icon: Icons.group_outlined,
        label: memberCount == 0
            ? 'Sin equipo asignado'
            : '$memberCount en equipo',
      ),
      _InfoPill(icon: Icons.location_on_outlined, label: c.location),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type icon
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    _eventIcon(c.eventType),
                    color: AppColors.darkGrey,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 10),
                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _campaignHeadline(c),
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          height: 1.4,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: c.status),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: context.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Eliminar',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'edit') widget.onEdit?.call();
                    if (val == 'delete') _handleDelete(context);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: overviewTags),
          ),

          if (c.status != CampaignStatus.upcoming)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _StatChip(
                    icon: Icons.bolt_outlined,
                    label: '${c.interactionCount} interacciones',
                  ),
                  _StatChip(
                    icon: Icons.person_add_alt_outlined,
                    label: '${c.leads} leads',
                  ),
                  _StatChip(
                    icon: Icons.handshake_outlined,
                    label: '${c.conversions} cierres',
                  ),
                  _StatChip(
                    icon: Icons.percent_outlined,
                    label: '${(c.conversionRate * 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
            ),

          if (c.status != CampaignStatus.upcoming) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c.conversionRate,
                  minHeight: 3,
                  backgroundColor: context.bgSubtle,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
            ),
          ],

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _AlwaysVisibleGeneralInfo(campaign: c, items: infoItems),
          ),

          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _expanded ? 'Ocultar detalle' : 'Ver detalle y equipo',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: context.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded
                ? _CampaignDetail(campaign: c)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── Campaign Detail (expanded) ───────────────────────────────────────────────

class _CampaignEditorResult {
  final CampaignModel campaign;
  final List<CampaignMemberAssignment> members;

  const _CampaignEditorResult({required this.campaign, required this.members});
}

class _CampaignDetail extends StatefulWidget {
  final CampaignModel campaign;
  const _CampaignDetail({required this.campaign});

  @override
  State<_CampaignDetail> createState() => _CampaignDetailState();
}

class _CampaignDetailState extends State<_CampaignDetail> {
  List<Map<String, String>> _members = [];
  bool _loadingMembers = true;

  bool get _membersLocked => widget.campaign.status == CampaignStatus.finished;

  void _showMembersLockedFeedback() {
    TapLoopToast.show(
      context,
      'No puedes modificar miembros porque se seleccionó una fecha pasada para la campaña. Cambia la fecha y actualiza la campaña para continuar.',
      TapLoopToastType.warning,
    );
  }

  Future<String> _friendlyMemberAssignmentErrorMessage(
    Object error, {
    List<Map<String, String>> attemptedUsers = const [],
  }) async {
    final raw = error.toString().replaceAll('\n', ' ').trim();
    final orgId = widget.campaign.orgId ?? appState.currentUser?.orgId;

    final userNameById = <String, String>{};
    if (orgId != null && orgId.isNotEmpty) {
      try {
        final users = await CampaignRepository.fetchOrgUsers(orgId);
        for (final user in users) {
          final id = user['id'];
          final name = user['name'];
          if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
            userNameById[id] = name;
          }
        }
      } catch (_) {}
    }

    final campaignNameById = <String, String>{
      widget.campaign.id: widget.campaign.name,
    };
    if (orgId != null && orgId.isNotEmpty) {
      try {
        final campaigns = await CampaignRepository.fetchCampaignsForUser(
          orgId: orgId,
        );
        for (final campaign in campaigns) {
          campaignNameById[campaign.id] = campaign.name;
        }
      } catch (_) {}
    }

    final ids = _CampaignsViewState._uuidPattern
        .allMatches(raw)
        .map((m) => m.group(0)!)
        .toList();
    final matchedUserId = ids.cast<String?>().firstWhere(
      (id) => id != null && userNameById.containsKey(id),
      orElse: () => null,
    );
    final matchedCampaignId = ids.cast<String?>().firstWhere(
      (id) => id != null && campaignNameById.containsKey(id),
      orElse: () => null,
    );
    final attemptedNames = attemptedUsers
        .map((user) => user['name']?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    if (raw.toLowerCase().contains(
          'duplicate key value violates unique constraint',
        ) ||
        raw.contains('campaign_members_campaign_user_uidx')) {
      if (attemptedNames.length == 1) {
        return '${attemptedNames.first} ya forma parte de esta campaña.';
      }
      if (attemptedNames.length > 1) {
        return 'Uno o más miembros seleccionados ya forman parte de esta campaña.';
      }
      return 'Ese miembro ya forma parte de esta campaña.';
    }

    if (raw.toLowerCase().contains('horario traslapado')) {
      final userName = matchedUserId == null
          ? 'Este miembro'
          : userNameById[matchedUserId]!;
      final campaignName = matchedCampaignId == null
          ? 'otra campaña'
          : '"${campaignNameById[matchedCampaignId]!}"';
      return '$userName ya pertenece a $campaignName en un horario traslapado. Ajusta el horario o cambia el miembro seleccionado.';
    }

    var cleaned = raw
        .replaceFirst(RegExp(r'^[A-Za-z]+Exception\(message:\s*'), '')
        .replaceFirst(RegExp(r',\s*code:.*$'), '')
        .trim();
    userNameById.forEach((id, name) => cleaned = cleaned.replaceAll(id, name));
    campaignNameById.forEach(
      (id, name) => cleaned = cleaned.replaceAll(id, name),
    );
    return cleaned.isEmpty || cleaned == raw
        ? 'No se pudo agregar el equipo. Revisa el horario y los miembros seleccionados.'
        : cleaned;
  }

  @override
  void initState() {
    super.initState();
    _members = _fallbackMembers();
    _loadingMembers = _members.isEmpty;
    _fetchMembers();
  }

  List<Map<String, String>> _fallbackMembers() {
    return widget.campaign.assignedMemberNames
        .map(
          (name) => <String, String>{
            'id': name,
            'name': name,
            'role': '',
            'job_title': '',
          },
        )
        .toList();
  }

  Future<void> _fetchMembers() async {
    final members = await CampaignRepository.fetchCampaignMembers(
      widget.campaign.id,
    );
    if (!mounted) return;
    setState(() {
      if (members.isNotEmpty) {
        _members = members;
      }
      _loadingMembers = false;
    });
  }

  Future<void> _removeMember(String userId) async {
    if (_membersLocked) {
      _showMembersLockedFeedback();
      return;
    }
    try {
      await CampaignRepository.removeCampaignMember(widget.campaign.id, userId);
      if (!mounted) return;
      setState(() => _members.removeWhere((member) => member['id'] == userId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al quitar miembro: $e')));
    }
  }

  Future<void> _showAddMemberPicker() async {
    if (_membersLocked) {
      _showMembersLockedFeedback();
      return;
    }
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) return;
    final allUsers = await CampaignRepository.fetchOrgUsers(orgId);
    final assignedIds = _members.map((member) => member['id']).toSet();
    final available = allUsers
        .where((user) => !assignedIds.contains(user['id']))
        .toList();
    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay más miembros disponibles')),
      );
      return;
    }
    final selected = await showDialog<List<Map<String, String>>>(
      context: context,
      builder: (_) => _MemberMultiSelectDialog(users: available),
    );
    if (selected == null || selected.isEmpty) return;
    try {
      await CampaignRepository.addCampaignMembers(
        widget.campaign.id,
        selected.map((user) => user['id']!).toList(),
      );
      if (!mounted) return;
      setState(() => _members = [..._members, ...selected]);
    } catch (e) {
      if (!mounted) return;
      final message = await _friendlyMemberAssignmentErrorMessage(
        e,
        attemptedUsers: selected,
      );
      if (!mounted) return;
      TapLoopToast.show(context, message, TapLoopToastType.error);
    }
  }

  Future<void> _showMemberAnalytics(Map<String, String> member) async {
    final userId = member['id'];
    if (userId == null || userId.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (_) => FutureBuilder<CampaignMemberAnalytics?>(
        future: CampaignRepository.fetchMemberAnalyticsForCampaign(
          campaignId: widget.campaign.id,
          userId: userId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Dialog(
              backgroundColor: context.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  height: 56,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            );
          }

          final data = snapshot.data;
          return _MemberAnalyticsDialog(
            campaignName: widget.campaign.name,
            memberName: member['name'] ?? '',
            fallbackRole: _resolveMemberRole(
              member['id'],
              member['role'],
              widget.campaign.memberRoles,
            ),
            fallbackJobTitle: member['job_title'],
            analytics: data,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;
    final visibleMemberCount = _members.isEmpty
        ? campaign.assignedMemberNames.length
        : _members.length;
    final memberCount = visibleMemberCount == 0 ? 1 : visibleMemberCount;
    final leadsPerMember = campaign.leads / memberCount;
    final interactionsPerMember = campaign.interactionCount / memberCount;
    final conversionsPerMember = campaign.conversions / memberCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 10),
          _DetailSection(
            title: 'Tracking',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(
                  icon: Icons.nfc_outlined,
                  label: campaign.sourceChannels.isEmpty
                      ? 'Fuentes: sin definir'
                      : 'Fuentes: ${campaign.sourceChannels.join(', ')}',
                ),
                _StatChip(
                  icon: Icons.person_add_alt_outlined,
                  label: '${campaign.leads} leads generados',
                ),
                _StatChip(
                  icon: Icons.bolt_outlined,
                  label: '${campaign.interactionCount} interacciones',
                ),
              ],
            ),
          ),
          _DetailSection(
            title: 'Rendimiento',
            child: Column(
              children: [
                _PerformanceChart(
                  interactions: campaign.interactionCount,
                  leads: campaign.leads,
                  conversions: campaign.conversions,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PerformanceKpi(
                        label: 'Miembros',
                        value: '$visibleMemberCount',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PerformanceKpi(
                        label: 'Leads / miembro',
                        value: leadsPerMember.toStringAsFixed(1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PerformanceKpi(
                        label: 'Interacciones / miembro',
                        value: interactionsPerMember.toStringAsFixed(1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PerformanceKpi(
                        label: 'Cierres / miembro',
                        value: conversionsPerMember.toStringAsFixed(1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _DetailSection(
            title: 'Equipo',
            trailing: TextButton.icon(
              onPressed: _showAddMemberPicker,
              icon: const Icon(Icons.group_add_outlined, size: 16),
              label: const Text('Agregar'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            child: _loadingMembers
                ? _members.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _members
                              .map(
                                (member) => _MemberCard(
                                  name: member['name'] ?? '',
                                  role: _resolveMemberRole(
                                    member['id'],
                                    member['role'],
                                    widget.campaign.memberRoles,
                                  ),
                                  jobTitle: member['job_title'],
                                  onInsights: () =>
                                      _showMemberAnalytics(member),
                                  onRemove: () => _removeMember(member['id']!),
                                ),
                              )
                              .toList(),
                        )
                : _members.isEmpty
                ? Text(
                    'Sin miembros asignados.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: context.textMuted,
                    ),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _members
                        .map(
                          (member) => _MemberCard(
                            name: member['name'] ?? '',
                            role: _resolveMemberRole(
                              member['id'],
                              member['role'],
                              widget.campaign.memberRoles,
                            ),
                            jobTitle: member['job_title'],
                            onInsights: () => _showMemberAnalytics(member),
                            onRemove: () => _removeMember(member['id']!),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (campaign.status != CampaignStatus.upcoming)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                campaign.leads > 0
                    ? 'Promedio actual: ${(campaign.interactionCount / campaign.leads).toStringAsFixed(1)} interacciones por lead.'
                    : 'Sin leads registrados aún.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final CampaignStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final Color bg;
    final Color fg;
    switch (status) {
      case CampaignStatus.active:
        bg = isDark
            ? const Color(0xFF166534).withValues(alpha: 0.3)
            : const Color(0xFFE6F4EA);
        fg = isDark ? const Color(0xFF86EFAC) : const Color(0xFF137333);
      case CampaignStatus.upcoming:
        bg = isDark
            ? const Color(0xFF1E40AF).withValues(alpha: 0.3)
            : const Color(0xFFE8F0FE);
        fg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1A56DB);
      case CampaignStatus.finished:
        bg = isDark ? const Color(0xFF334155) : const Color(0xFFF1F3F4);
        fg = context.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.bgPage,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlwaysVisibleGeneralInfo extends StatelessWidget {
  final CampaignModel campaign;
  final List<_DetailInfoData> items;

  const _AlwaysVisibleGeneralInfo({
    required this.campaign,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Información general',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
            if (campaign.description != null &&
                campaign.description!.trim().isNotEmpty)
              Flexible(
                child: Text(
                  campaign.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _DetailInfoGrid(items: items),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _DetailSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DetailInfoData {
  final String label;
  final String value;

  const _DetailInfoData(this.label, this.value);
}

class _DetailInfoGrid extends StatelessWidget {
  final List<_DetailInfoData> items;
  const _DetailInfoGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 860
            ? 4
            : constraints.maxWidth > 520
            ? 2
            : 1;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _DetailInfoTile(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DetailInfoTile extends StatelessWidget {
  final _DetailInfoData item;
  const _DetailInfoTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final String name;
  final String? role;
  final String? jobTitle;
  final VoidCallback onInsights;
  final VoidCallback? onRemove;

  const _MemberCard({
    required this.name,
    required this.onInsights,
    this.onRemove,
    this.role,
    this.jobTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                if (role != null || (jobTitle != null && jobTitle!.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (role != null) role!,
                        if (jobTitle != null && jobTitle!.isNotEmpty) jobTitle!,
                      ].join(' • '),
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onInsights,
            icon: Icon(
              Icons.query_stats_outlined,
              size: 18,
              color: context.textMuted,
            ),
            tooltip: 'Ver analítica',
            visualDensity: VisualDensity.compact,
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: context.textMuted,
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _MemberAnalyticsDialog extends StatelessWidget {
  final String campaignName;
  final String memberName;
  final String? fallbackRole;
  final String? fallbackJobTitle;
  final CampaignMemberAnalytics? analytics;

  const _MemberAnalyticsDialog({
    required this.campaignName,
    required this.memberName,
    this.fallbackRole,
    this.fallbackJobTitle,
    this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final data = analytics;
    final roleLine = [
      if (fallbackRole != null && fallbackRole!.isNotEmpty) fallbackRole!,
      if ((data?.jobTitle ?? fallbackJobTitle)?.isNotEmpty == true)
        data?.jobTitle ?? fallbackJobTitle!,
    ].join(' • ');

    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                          memberName,
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Analítica dentro de $campaignName',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                        if (roleLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            roleLine,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              color: context.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: data == null
                      ? Text(
                          'No se pudo cargar la analítica de este miembro.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _PerformanceKpi(
                                    label: 'Vistas',
                                    value: '${data.profileViews}',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PerformanceKpi(
                                    label: 'Clicks',
                                    value: '${data.clicks}',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PerformanceKpi(
                                    label: 'Formularios',
                                    value: '${data.forms}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _PerformanceKpi(
                                    label: 'Interacciones',
                                    value: '${data.interactions}',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PerformanceKpi(
                                    label: 'Leads',
                                    value: '${data.leads}',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PerformanceKpi(
                                    label: 'Cierres',
                                    value: '${data.conversions}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _DetailSection(
                              title: 'Fuentes dentro de campaña',
                              child: data.sources.isEmpty
                                  ? Text(
                                      'Sin interacciones registradas todavía.',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: context.textMuted,
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: data.sources
                                          .map(
                                            (source) => _StatChip(
                                              icon: Icons.bolt_outlined,
                                              label: source,
                                            ),
                                          )
                                          .toList(),
                                    ),
                            ),
                            const SizedBox(height: 14),
                            _DetailSection(
                              title: 'Actividad reciente',
                              child: data.recentEvents.isEmpty
                                  ? Text(
                                      'Sin actividad reciente atribuida a esta campaña.',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: context.textMuted,
                                      ),
                                    )
                                  : Column(
                                      children: data.recentEvents
                                          .map(
                                            (event) => Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: _CampaignMemberEventRow(
                                                event: event,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                            ),
                          ],
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

class _CampaignMemberEventRow extends StatelessWidget {
  final VisitEventModel event;

  const _CampaignMemberEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final source = (event.source ?? 'interaccion').toUpperCase();
    final label = event.label?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgPage,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.timeline_outlined,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label?.isNotEmpty == true ? label! : source,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$source • ${event.formattedDate} • ${event.formattedTime}',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textSecondary,
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

class _PerformanceChart extends StatelessWidget {
  final int interactions;
  final int leads;
  final int conversions;

  const _PerformanceChart({
    required this.interactions,
    required this.leads,
    required this.conversions,
  });

  @override
  Widget build(BuildContext context) {
    final values = [interactions, leads, conversions];
    final maxValue = values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return Column(
      children: [
        _MetricBarRow(
          label: 'Interacciones',
          value: interactions,
          ratio: interactions / maxValue,
        ),
        const SizedBox(height: 10),
        _MetricBarRow(label: 'Leads', value: leads, ratio: leads / maxValue),
        const SizedBox(height: 10),
        _MetricBarRow(
          label: 'Cierres',
          value: conversions,
          ratio: conversions / maxValue,
        ),
      ],
    );
  }
}

class _MetricBarRow extends StatelessWidget {
  final String label;
  final int value;
  final double ratio;

  const _MetricBarRow({
    required this.label,
    required this.value,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 8,
              backgroundColor: context.borderColor,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 46,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PerformanceKpi extends StatelessWidget {
  final String label;
  final String value;

  const _PerformanceKpi({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberMultiSelectDialog extends StatefulWidget {
  final List<Map<String, String>> users;
  final Set<String> initiallySelected;

  const _MemberMultiSelectDialog({
    required this.users,
    this.initiallySelected = const {},
  });

  @override
  State<_MemberMultiSelectDialog> createState() =>
      _MemberMultiSelectDialogState();
}

class _MemberMultiSelectDialogState extends State<_MemberMultiSelectDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initiallySelected};
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agregar miembros',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecciona uno o varios usuarios para asignarlos a la campaña.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.users.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: context.borderColor),
                  itemBuilder: (context, index) {
                    final user = widget.users[index];
                    final id = user['id']!;
                    final selected = _selectedIds.contains(id);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (_) {
                        setState(() {
                          if (selected) {
                            _selectedIds.remove(id);
                          } else {
                            _selectedIds.add(id);
                          }
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        user['name'] ?? '',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        [
                              if ((user['role'] ?? '').isNotEmpty)
                                user['role']!,
                              if ((user['job_title'] ?? '').isNotEmpty)
                                user['job_title']!,
                            ].join(' • ').isEmpty
                            ? 'Sin rol definido'
                            : [
                                if ((user['role'] ?? '').isNotEmpty)
                                  user['role']!,
                                if ((user['job_title'] ?? '').isNotEmpty)
                                  user['job_title']!,
                              ].join(' • '),
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () {
                            Navigator.pop(
                              context,
                              widget.users
                                  .where(
                                    (user) => _selectedIds.contains(user['id']),
                                  )
                                  .toList(),
                            );
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                    ),
                    child: Text('Agregar ${_selectedIds.length}'),
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

IconData _eventIcon(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'expo':
    case 'evento':
      return Icons.campaign_outlined;
    case 'feria':
      return Icons.storefront_outlined;
    case 'congreso':
      return Icons.apartment_outlined;
    case 'activación':
    case 'activacion':
      return Icons.flash_on_outlined;
    case 'networking':
      return Icons.groups_outlined;
    default:
      return Icons.groups_outlined;
  }
}

// ─── New Campaign Sheet ───────────────────────────────────────────────────────

class _NewCampaignSheet extends StatefulWidget {
  final void Function(_CampaignEditorResult) onSave;
  final bool isDialog;
  final CampaignModel? existing;

  const _NewCampaignSheet({
    required this.onSave,
    this.isDialog = false,
    this.existing,
  });

  @override
  State<_NewCampaignSheet> createState() => _NewCampaignSheetState();
}

class _NewCampaignSheetState extends State<_NewCampaignSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _zoneCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _leadGoalCtrl;
  late DateTime _date;
  late String _type;
  CampaignObjective? _objective;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _loadingUsers = false;
  List<Map<String, String>> _orgUsers = [];
  List<CampaignMemberAssignment> _selectedMembers = [];

  bool get _isEditing => widget.existing != null;
  bool get _teamLocked => widget.existing?.status == CampaignStatus.finished;

  void _showMembersDateFeedback() {
    TapLoopToast.show(
      context,
      'No puedes modificar miembros porque se seleccionó una fecha pasada para la campaña. Cambia la fecha y actualiza la campaña para continuar.',
      TapLoopToastType.warning,
    );
  }

  static const _types = [
    'Evento',
    'Activación',
    'Expo',
    'Feria',
    'Congreso',
    'Networking',
    'Roadshow',
  ];
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _locationCtrl = TextEditingController(text: existing?.location ?? '');
    _zoneCtrl = TextEditingController(text: existing?.zone ?? '');
    _descCtrl = TextEditingController(text: existing?.description ?? '');
    _leadGoalCtrl = TextEditingController(
      text: existing?.leadGoal?.toString() ?? '',
    );
    final now = DateTime.now();
    _date = existing?.eventDate ?? DateTime(now.year, now.month, now.day);
    _type = existing?.eventType ?? 'Evento';
    _objective = existing?.objective;
    const fallbackStart = TimeOfDay(hour: 9, minute: 0);
    const fallbackEnd = TimeOfDay(hour: 18, minute: 0);
    _startTime = _parseTimeOfDay(existing?.startTime) ?? fallbackStart;
    _endTime = _parseTimeOfDay(existing?.endTime) ?? fallbackEnd;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) return;
    setState(() => _loadingUsers = true);
    final users = await CampaignRepository.fetchOrgUsers(orgId);
    List<CampaignMemberAssignment> selectedMembers = [];
    if (_isEditing && widget.existing != null) {
      final existingMembers = await CampaignRepository.fetchCampaignMembers(
        widget.existing!.id,
      );
      selectedMembers = existingMembers
          .map(
            (member) => CampaignMemberAssignment(
              userId: member['id'] ?? '',
              name: member['name'] ?? '',
              jobTitle: member['job_title'],
              role:
                  _roleFromMapValue(
                    widget.existing!.memberRoles[member['id']],
                  ) ??
                  _roleFromMapValue(member['role']),
            ),
          )
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _orgUsers = users;
      _selectedMembers = selectedMembers;
      _loadingUsers = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _zoneCtrl.dispose();
    _descCtrl.dispose();
    _leadGoalCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final minDate = _isEditing && _date.isBefore(today)
        ? _date
        : DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: minDate,
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = start
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 18, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _selectMembers() async {
    if (_teamLocked) {
      _showMembersDateFeedback();
      return;
    }
    final selected = await showDialog<List<Map<String, String>>>(
      context: context,
      builder: (_) => _MemberMultiSelectDialog(
        users: _orgUsers,
        initiallySelected: _selectedMembers
            .map((member) => member.userId)
            .toSet(),
      ),
    );
    if (selected == null) return;
    setState(() {
      _selectedMembers = selected.map((user) {
        final existingRole = _selectedMembers
            .where((member) => member.userId == user['id'])
            .map((member) => member.role)
            .cast<CampaignMemberRole?>()
            .firstWhere((_) => true, orElse: () => null);
        return CampaignMemberAssignment(
          userId: user['id'] ?? '',
          name: user['name'] ?? '',
          jobTitle: user['job_title'],
          role: existingRole ?? _roleFromMapValue(user['role']),
        );
      }).toList();
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final today = DateTime.now();
    final campaignDate = DateTime(_date.year, _date.month, _date.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    if (name.isEmpty) {
      TapLoopToast.show(
        context,
        'Ingresa el nombre de la campaña.',
        TapLoopToastType.warning,
      );
      return;
    }
    if (!_isEditing && campaignDate.isBefore(todayDate)) {
      TapLoopToast.show(
        context,
        'No puedes guardar la campaña porque la fecha seleccionada ya pasó.',
        TapLoopToastType.warning,
      );
      return;
    }
    if (_startTime == null || _endTime == null) {
      TapLoopToast.show(
        context,
        'Selecciona una hora de inicio y una hora de fin.',
        TapLoopToastType.warning,
      );
      return;
    }
    if (!_isValidTimeRange(_startTime!, _endTime!)) {
      TapLoopToast.show(
        context,
        'La hora de fin debe ser posterior a la hora de inicio.',
        TapLoopToastType.warning,
      );
      return;
    }
    final existing = widget.existing;
    final memberRoles = <String, String>{
      for (final member in _selectedMembers)
        if (member.role != null) member.userId: member.role!.name,
    };
    final campaign = CampaignModel(
      id: existing?.id ?? '',
      orgId: existing?.orgId,
      name: name,
      eventType: _type,
      eventDate: _date,
      location: _locationCtrl.text.trim().isEmpty
          ? 'Por definir'
          : _locationCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      status: _deriveCampaignStatusForEditor(_date, _startTime!, _endTime!),
      taps: existing?.taps ?? 0,
      leads: existing?.leads ?? 0,
      conversions: existing?.conversions ?? 0,
      assignedMemberNames: _selectedMembers
          .map((member) => member.name)
          .toList(),
      zone: _zoneCtrl.text.trim().isEmpty ? null : _zoneCtrl.text.trim(),
      startTime: _formatTimeOfDay(_startTime),
      endTime: _formatTimeOfDay(_endTime),
      durationMinutes: null,
      shiftNotes: null,
      objective: _objective,
      leadGoal: int.tryParse(_leadGoalCtrl.text.trim()),
      sourceChannels: existing?.sourceChannels ?? const [],
      interactionCount: existing?.interactionCount ?? 0,
      captureFields: const [],
      memberRoles: memberRoles,
    );
    widget.onSave(
      _CampaignEditorResult(campaign: campaign, members: _selectedMembers),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDialog = widget.isDialog;
    final bottom = isDialog ? 0.0 : MediaQuery.of(context).viewInsets.bottom;
    final sectionSpacing = const SizedBox(height: 18);

    Widget content = Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: isDialog
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDialog)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )
              else
                const SizedBox(height: 10),
              Text(
                _isEditing ? 'Editar campaña' : 'Nueva campaña',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Completa los pasos principales para que cualquier persona entienda cuándo sucede, quién participa y qué se espera de esta campaña.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
              sectionSpacing,
              _EditorProgressSummary(
                date: _date,
                startTime: _startTime,
                endTime: _endTime,
                selectedMembers: _selectedMembers.length,
                objective: _objective?.label,
              ),
              sectionSpacing,
              _FormSection(
                title: '1. Define la campaña',
                subtitle:
                    'Ponle un nombre claro y deja explícito qué tipo de evento es.',
                child: Column(
                  children: [
                    _SheetField(
                      controller: _nameCtrl,
                      label: 'Nombre de la campaña',
                      hint: 'Ej. Expo Industrial 2026',
                      maxLength: 300,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          _campaignSingleLinePattern,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SheetDropdownField<String>(
                            label: 'Tipo de campaña',
                            value: _type,
                            items: _types,
                            itemLabel: (value) => value,
                            onChanged: (value) {
                              if (value != null) setState(() => _type = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SheetDropdownField<CampaignObjective?>(
                            label: 'Objetivo',
                            value: _objective,
                            items: [null, ...CampaignObjective.values],
                            itemLabel: (value) =>
                                value?.label ?? 'Seleccionar objetivo',
                            onChanged: (value) =>
                                setState(() => _objective = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SheetField(
                      controller: _descCtrl,
                      label: 'Descripción estratégica',
                      hint:
                          'Qué se busca validar, captar o posicionar en esta campaña.',
                      maxLines: 4,
                      maxLength: 300,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          _campaignMultilinePattern,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              sectionSpacing,
              _FormSection(
                title: '2. Ubicación',
                subtitle:
                    'Escribe el lugar para que el equipo sepa dónde aplica esta campaña.',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SheetField(
                            controller: _locationCtrl,
                            label: 'Ubicación principal',
                            hint: 'Ej. Monterrey, NL',
                            maxLength: 300,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                _campaignSingleLinePattern,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SheetField(
                            controller: _zoneCtrl,
                            label: 'Zona',
                            hint: 'Ej. Stand A12, VIP, Entrada',
                            maxLength: 300,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                _campaignSingleLinePattern,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Preparado para geolocalización futura sobre esta estructura base.',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              sectionSpacing,
              _FormSection(
                title: '3. Fecha y horario',
                subtitle:
                    'Este bloque define cuándo debe considerarse activa la campaña.',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Fecha',
                            value: _fmtDate(_date),
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimeField(
                            label: 'Hora de inicio',
                            value: _formatTimeOfDay(_startTime)!,
                            onTap: () => _pickTime(start: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimeField(
                            label: 'Hora de fin',
                            value: _formatTimeOfDay(_endTime)!,
                            onTap: () => _pickTime(start: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'El rango horario es obligatorio y la hora de fin debe ser posterior a la de inicio.',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              sectionSpacing,
              _FormSection(
                title: '4. Equipo',
                subtitle:
                    'Selecciona a los usuarios que participarán y asigna su rol operativo.',
                trailing: _loadingUsers
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        onPressed: _orgUsers.isEmpty ? null : _selectMembers,
                        icon: const Icon(Icons.group_add_outlined, size: 16),
                        label: const Text('Agregar'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                child: _selectedMembers.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Asigna supervisor, ejecutivo o promotor según la operación.',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: context.textMuted,
                          ),
                        ),
                      )
                    : Column(
                        children: _selectedMembers
                            .asMap()
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      entry.key == _selectedMembers.length - 1
                                      ? 0
                                      : 10,
                                ),
                                child: _SelectedMemberRow(
                                  member: entry.value,
                                  onRoleChanged: (role) {
                                    if (_teamLocked) {
                                      _showMembersDateFeedback();
                                      return;
                                    }
                                    setState(() {
                                      _selectedMembers[entry.key] = entry.value
                                          .copyWith(role: role);
                                    });
                                  },
                                  onRemove: () {
                                    if (_teamLocked) {
                                      _showMembersDateFeedback();
                                      return;
                                    }
                                    setState(() {
                                      _selectedMembers.removeAt(entry.key);
                                    });
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              sectionSpacing,
              _FormSection(
                title: '5. Objetivo comercial',
                subtitle:
                    'Define la meta para que la campaña tenga una expectativa clara.',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SheetField(
                            controller: _leadGoalCtrl,
                            label: 'Meta de leads',
                            hint: 'Ej. 250',
                            keyboardType: TextInputType.number,
                            maxLength: 300,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'El estado se calcula automáticamente: próxima, activa o terminada según la fecha y el horario.',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isEditing ? 'Guardar cambios' : 'Crear campaña',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isDialog) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
        child: content,
      );
    }
    return content;
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final String? subtitle;

  const _FormSection({
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                height: 1.4,
                color: context.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EditorProgressSummary extends StatelessWidget {
  final DateTime date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final int selectedMembers;
  final String? objective;

  const _EditorProgressSummary({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.selectedMembers,
    required this.objective,
  });

  @override
  Widget build(BuildContext context) {
    final schedule = _formatTimeRange(
      _formatTimeOfDay(startTime),
      _formatTimeOfDay(endTime),
    );
    final chips = <String>[
      'Fecha ${_fmtShortDate(date)}',
      if (schedule != null) 'Horario $schedule',
      if (selectedMembers > 0) '$selectedMembers miembros',
      objective ?? 'Objetivo por definir',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgPage,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips
            .map(
              (chip) =>
                  _InfoPill(icon: Icons.check_circle_outline, label: chip),
            )
            .toList(),
      ),
    );
  }
}

String _campaignHeadline(CampaignModel campaign) {
  final schedule = _formatTimeRange(campaign.startTime, campaign.endTime);
  final parts = <String>[
    if (campaign.eventType != null && campaign.eventType!.trim().isNotEmpty)
      campaign.eventType!,
    'el ${_fmtShortDate(campaign.eventDate)}',
    if (schedule != null) 'de $schedule',
  ];
  return parts.join(' ');
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TapField(
      label: label,
      value: value,
      icon: Icons.calendar_today_outlined,
      onTap: onTap,
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TapField(
      label: label,
      value: value,
      icon: Icons.schedule_outlined,
      onTap: onTap,
    );
  }
}

class _TapField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _TapField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: context.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: context.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T?>? onChanged;

  const _SheetDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.bgCard,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: context.textPrimary,
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(itemLabel(item)),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectedMemberRow extends StatelessWidget {
  final CampaignMemberAssignment member;
  final ValueChanged<CampaignMemberRole?>? onRoleChanged;
  final VoidCallback? onRemove;

  const _SelectedMemberRow({
    required this.member,
    required this.onRoleChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.jobTitle?.isNotEmpty == true
                      ? member.jobTitle!
                      : 'Sin puesto definido',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 160,
            child: _SheetDropdownField<CampaignMemberRole?>(
              label: 'Rol',
              value: member.role,
              items: [null, ...CampaignMemberRole.values],
              itemLabel: (value) => value?.label ?? 'Sin rol',
              onChanged: onRoleChanged,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 18, color: context.textMuted),
          ),
        ],
      ),
    );
  }
}

final RegExp _campaignSingleLinePattern = RegExp(
  r"[a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ\s.,;:!¡?¿()#@&/_\-%']",
);
final RegExp _campaignMultilinePattern = RegExp(
  r"[a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ\s.,;:!¡?¿()#@&/_\-%'\n]",
);

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final int maxLength;
  final List<TextInputFormatter>? inputFormatters;

  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.maxLength = 300,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveInputFormatters = <TextInputFormatter>[
      ...?inputFormatters,
      LengthLimitingTextInputFormatter(maxLength),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return Text(
                  '${value.text.length}/$maxLength',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.textMuted,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: effectiveInputFormatters,
          maxLength: maxLength,
          style: GoogleFonts.dmSans(fontSize: 13, color: context.textPrimary),
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textMuted,
            ),
            filled: true,
            fillColor: context.bgCard,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

TimeOfDay? _parseTimeOfDay(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String? _formatTimeOfDay(TimeOfDay? value) {
  if (value == null) return null;
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String? _formatTimeRange(String? start, String? end) {
  if (start == null && end == null) return null;
  if (start != null && end != null) return '$start - $end';
  return start ?? end;
}

String? _formatDuration(int? minutes) {
  if (minutes == null || minutes <= 0) return null;
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (remaining == 0) return '$hours h';
  return '$hours h $remaining min';
}

bool _isValidTimeRange(TimeOfDay start, TimeOfDay end) {
  final startMinutes = (start.hour * 60) + start.minute;
  final endMinutes = (end.hour * 60) + end.minute;
  return endMinutes > startMinutes;
}

CampaignStatus _deriveCampaignStatusForEditor(
  DateTime date,
  TimeOfDay start,
  TimeOfDay end,
) {
  final startsAt = DateTime(
    date.year,
    date.month,
    date.day,
    start.hour,
    start.minute,
  );
  final endsAt = DateTime(
    date.year,
    date.month,
    date.day,
    end.hour,
    end.minute,
  );
  final now = DateTime.now();
  if (now.isBefore(startsAt)) return CampaignStatus.upcoming;
  if (now.isAfter(endsAt)) return CampaignStatus.finished;
  return CampaignStatus.active;
}

CampaignMemberRole? _roleFromMapValue(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  for (final role in CampaignMemberRole.values) {
    if (role.name == value.toLowerCase() ||
        role.label.toLowerCase() == value.toLowerCase()) {
      return role;
    }
  }
  return null;
}

String? _resolveMemberRole(
  String? userId,
  String? rawRole,
  Map<String, String> memberRoles,
) {
  final mapped = _roleFromMapValue(userId != null ? memberRoles[userId] : null);
  if (mapped != null) return mapped.label;
  final raw = _roleFromMapValue(rawRole);
  if (raw != null) return raw.label;
  if (rawRole == null || rawRole.trim().isEmpty) return null;
  return rawRole;
}
