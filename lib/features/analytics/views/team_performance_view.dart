import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../models/lead_model.dart';
import '../models/team_member_model.dart';

Color _teamAnalyticsSurfaceColor(BuildContext context) =>
    context.bgSubtle.withValues(alpha: 0.5);

Color _teamAnalyticsBorderColor(BuildContext context) => context.borderSoft;

class TeamPerformanceView extends StatefulWidget {
  const TeamPerformanceView({super.key});

  @override
  State<TeamPerformanceView> createState() => _TeamPerformanceViewState();
}

class _TeamPerformanceViewState extends State<TeamPerformanceView> {
  List<TeamMemberModel> _members = [];
  Map<String, List<LeadModel>> _memberLeads = {};
  bool _loading = true;
  String? _loadedOrgId;
  String? _selectedMemberId;
  final TextEditingController _searchCtrl = TextEditingController();
  String _memberSearch = '';
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeOrgId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _loadMembers();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final orgId = appState.currentUser?.orgId;
    _bindRealtime();
    if (orgId == null || orgId == _loadedOrgId) return;
    if (!mounted) return;
    setState(() => _loading = true);
    _loadMembers();
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
        _loadMembers();
      },
    );
  }

  Future<void> _loadMembers() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null) {
      _loadedOrgId = null;
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final members = await AdminRepository.fetchTeamMembers(orgId);
      final allCardIds = members
          .expand((member) => member.cardIds)
          .toSet()
          .toList();
      final leadsByCard = await LeadRepository.fetchLeadsForCards(allCardIds);
      final leadsByMember = <String, List<LeadModel>>{};
      for (final member in members) {
        final memberLeads = <LeadModel>[];
        for (final cardId in member.cardIds) {
          memberLeads.addAll(leadsByCard[cardId] ?? const []);
        }
        memberLeads.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        leadsByMember[member.id] = memberLeads;
      }
      if (!mounted) return;
      setState(() {
        _loadedOrgId = orgId;
        _members = members..sort((a, b) => b.leads.compareTo(a.leads));
        _memberLeads = leadsByMember;
        _selectedMemberId = _resolveSelectedMemberId(
          sortedMembers: _members,
          currentSelectedId: _selectedMemberId,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadedOrgId = orgId;
        _loading = false;
      });
    }
  }

  String? _resolveSelectedMemberId({
    required List<TeamMemberModel> sortedMembers,
    required String? currentSelectedId,
  }) {
    if (sortedMembers.isEmpty) return null;
    final exists = sortedMembers.any(
      (member) => member.id == currentSelectedId,
    );
    return exists ? currentSelectedId : sortedMembers.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final totalViews = _members.fold<int>(
      0,
      (sum, member) => sum + member.profileViews,
    );
    final totalTaps = _members.fold<int>(0, (sum, member) => sum + member.taps);
    final totalClicks = _members.fold<int>(
      0,
      (sum, member) => sum + member.totalClicks,
    );
    final totalLeads = _members.fold<int>(
      0,
      (sum, member) => sum + member.leads,
    );
    final viewsSeries = _sumSeries(
      _members.map((member) => member.viewsByDay).toList(),
    );
    final tapsSeries = _sumSeries(
      _members.map((member) => member.tapsByDay).toList(),
    );
    final clicksSeries = _sumSeries(
      _members.map((member) => member.clicksByDay).toList(),
    );
    final rankedMembers = [..._members]
      ..sort((a, b) => b.leads.compareTo(a.leads));
    final filteredMembers = rankedMembers.where((member) {
      final query = _memberSearch.trim().toLowerCase();
      if (query.isEmpty) return true;
      return member.name.toLowerCase().contains(query) ||
          member.jobTitle.toLowerCase().contains(query);
    }).toList();
    final topMember = rankedMembers.isNotEmpty ? rankedMembers.first : null;
    final selectionPool = filteredMembers.isNotEmpty
        ? filteredMembers
        : rankedMembers;
    final selectedMember = selectionPool.firstWhere(
      (member) => member.id == _selectedMemberId,
      orElse: () =>
          selectionPool.isNotEmpty ? selectionPool.first : _emptyMember,
    );
    final hasSelectedMember = selectionPool.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadMembers,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(
                  Responsive.isMobile(context) ? 20 : 32,
                  24,
                  Responsive.isMobile(context) ? 20 : 32,
                  18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equipo',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rendimiento del equipo y visibilidad por miembro en un mismo panel.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.isMobile(context) ? 20 : 32,
                    24,
                    Responsive.isMobile(context) ? 20 : 32,
                    0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _teamAnalyticsSurfaceColor(context),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _teamAnalyticsBorderColor(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visión general del equipo',
                          style: GoogleFonts.outfit(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_members.length} miembros activos con links, leads y recorrido de interacción visible.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _OverviewMetricsLine(
                          activeMembers: _members.length,
                          totalViews: totalViews,
                          totalTaps: totalTaps,
                          totalClicks: totalClicks,
                          totalLeads: totalLeads,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.isMobile(context) ? 20 : 32,
                    16,
                    Responsive.isMobile(context) ? 20 : 32,
                    0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _teamAnalyticsSurfaceColor(context),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _teamAnalyticsBorderColor(context),
                      ),
                    ),
                    child: Responsive.isDesktop(context)
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _TeamLeaderPanel(
                                  member: topMember,
                                  totalMembers: _members.length,
                                  totalLeads: totalLeads,
                                  totalViews: totalViews,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 4,
                                child: _TopMembersColumn(
                                  members: rankedMembers,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _TeamLeaderPanel(
                                member: topMember,
                                totalMembers: _members.length,
                                totalLeads: totalLeads,
                                totalViews: totalViews,
                              ),
                              const SizedBox(height: 20),
                              _TopMembersColumn(members: rankedMembers),
                            ],
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.isMobile(context) ? 20 : 32,
                    16,
                    Responsive.isMobile(context) ? 20 : 32,
                    0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _teamAnalyticsSurfaceColor(context),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _teamAnalyticsBorderColor(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tendencias del equipo',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Comparativa semanal de vistas, taps y clicks para entender el ritmo del equipo.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _TeamTrendSection(
                          viewsSeries: viewsSeries,
                          tapsSeries: tapsSeries,
                          clicksSeries: clicksSeries,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.isMobile(context) ? 20 : 32,
                    16,
                    Responsive.isMobile(context) ? 20 : 32,
                    0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _teamAnalyticsSurfaceColor(context),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _teamAnalyticsBorderColor(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Explorador del equipo',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Selecciona un miembro para revisar su desempeño, leads capturados y comportamiento comercial.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _TeamMemberExplorer(
                          searchController: _searchCtrl,
                          onSearchChanged: (value) {
                            setState(() => _memberSearch = value);
                          },
                          members: filteredMembers,
                          selectedMemberId: _selectedMemberId,
                          onSelectMember: (member) {
                            setState(() => _selectedMemberId = member.id);
                          },
                          detail: hasSelectedMember
                              ? _MemberAnalyticsCard(
                                  member: selectedMember,
                                  leads:
                                      _memberLeads[selectedMember.id] ??
                                      const [],
                                  rank:
                                      rankedMembers.indexWhere(
                                        (member) =>
                                            member.id == selectedMember.id,
                                      ) +
                                      1,
                                )
                              : const _EmptyTeamExplorer(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeamMemberExplorer extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<TeamMemberModel> members;
  final String? selectedMemberId;
  final ValueChanged<TeamMemberModel> onSelectMember;
  final Widget detail;

  const _TeamMemberExplorer({
    required this.searchController,
    required this.onSearchChanged,
    required this.members,
    required this.selectedMemberId,
    required this.onSelectMember,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    if (!isDesktop) {
      return Column(
        children: [
          _ExplorerSearchField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 14),
          ...members.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExplorerMemberTile(
                member: member,
                active: member.id == selectedMemberId,
                onTap: () => onSelectMember(member),
              ),
            ),
          ),
          const SizedBox(height: 18),
          detail,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Miembros',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecciona un perfil para inspeccionar su rendimiento.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _ExplorerSearchField(
                controller: searchController,
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: 14),
              const _ExplorerHeaderRow(),
              const SizedBox(height: 10),
              ...members.map(
                (member) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ExplorerMemberTile(
                    member: member,
                    active: member.id == selectedMemberId,
                    onTap: () => onSelectMember(member),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: detail),
      ],
    );
  }
}

class _ExplorerSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _ExplorerSearchField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      inputFormatters: [LengthLimitingTextInputFormatter(200)],
      maxLength: 200,
      decoration: InputDecoration(
        hintText: 'Buscar miembro',
        counterText: '',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: const Color(0xFFF7F7F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8E8E3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8E8E3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _ExplorerHeaderRow extends StatelessWidget {
  const _ExplorerHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.dmSans(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: context.textMuted,
      letterSpacing: 0.8,
    );

    return Row(
      children: [
        Expanded(flex: 6, child: Text('MIEMBRO', style: style)),
        Expanded(flex: 2, child: Text('LEADS', style: style)),
        Expanded(flex: 2, child: Text('CLICKS', style: style)),
      ],
    );
  }
}

class _ExplorerMemberTile extends StatelessWidget {
  final TeamMemberModel member;
  final bool active;
  final VoidCallback onTap;

  const _ExplorerMemberTile({
    required this.member,
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
            color: active
                ? AppColors.primary.withValues(alpha: 0.08)
                : _teamAnalyticsSurfaceColor(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? AppColors.primary
                  : _teamAnalyticsBorderColor(context),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.jobTitle.trim().isNotEmpty
                          ? member.jobTitle
                          : 'Perfil del equipo',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: Text(
                  '${member.leads}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '${member.totalClicks}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
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

class _EmptyTeamExplorer extends StatelessWidget {
  const _EmptyTeamExplorer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _teamAnalyticsSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _teamAnalyticsBorderColor(context)),
      ),
      child: Text(
        'No hay miembros disponibles para mostrar.',
        style: GoogleFonts.dmSans(fontSize: 13, color: context.textSecondary),
      ),
    );
  }
}

final TeamMemberModel _emptyMember = TeamMemberModel(
  id: '',
  cardIds: const [],
  name: '',
  jobTitle: '',
  taps: 0,
  profileViews: 0,
  contactsSaved: 0,
  viewsByDay: const [0, 0, 0, 0, 0, 0, 0],
  tapsByDay: const [0, 0, 0, 0, 0, 0, 0],
  clicksByDay: const [0, 0, 0, 0, 0, 0, 0],
  linkStats: const [],
);

List<int> _sumSeries(List<List<int>> all) {
  final result = List.filled(7, 0);
  for (final series in all) {
    for (var i = 0; i < 7 && i < series.length; i++) {
      result[i] += series[i];
    }
  }
  return result;
}

class _OverviewMetricsLine extends StatelessWidget {
  final int activeMembers;
  final int totalViews;
  final int totalTaps;
  final int totalClicks;
  final int totalLeads;

  const _OverviewMetricsLine({
    required this.activeMembers,
    required this.totalViews,
    required this.totalTaps,
    required this.totalClicks,
    required this.totalLeads,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Miembros activos', '$activeMembers'),
      ('Vistas del equipo', '$totalViews'),
      ('Taps del equipo', '$totalTaps'),
      ('Clicks en enlaces', '$totalClicks'),
      ('Leads registrados', '$totalLeads'),
    ];

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: items
          .map(
            (item) => SizedBox(
              width: 148,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$2,
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.$1,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TeamLeaderPanel extends StatelessWidget {
  final TeamMemberModel? member;
  final int totalMembers;
  final int totalLeads;
  final int totalViews;

  const _TeamLeaderPanel({
    required this.member,
    required this.totalMembers,
    required this.totalLeads,
    required this.totalViews,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen ejecutivo',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Lectura rápida del equipo y del miembro con mayor tracción comercial.',
          style: GoogleFonts.dmSans(fontSize: 12, color: context.textSecondary),
        ),
        const SizedBox(height: 18),
        if (member != null) ...[
          Text(
            'Miembro destacado',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            member!.name,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${member!.leads} leads • ${member!.profileViews} vistas • ${member!.totalClicks} clicks',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
        ] else
          Text(
            'No hay miembros activos para mostrar.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _InlineFact(label: 'Equipo', value: '$totalMembers'),
            _InlineFact(label: 'Leads', value: '$totalLeads'),
            _InlineFact(label: 'Vistas', value: '$totalViews'),
          ],
        ),
      ],
    );
  }
}

class _InlineFact extends StatelessWidget {
  final String label;
  final String value;

  const _InlineFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 11, color: context.textSecondary),
        ),
      ],
    );
  }
}

class _TeamTrendSection extends StatelessWidget {
  final List<int> viewsSeries;
  final List<int> tapsSeries;
  final List<int> clicksSeries;

  const _TeamTrendSection({
    required this.viewsSeries,
    required this.tapsSeries,
    required this.clicksSeries,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrendRow(
          label: 'Vistas',
          total: viewsSeries.fold(0, (a, b) => a + b),
          series: viewsSeries,
          color: AppColors.primary,
        ),
        const SizedBox(height: 12),
        _TrendRow(
          label: 'Taps',
          total: tapsSeries.fold(0, (a, b) => a + b),
          series: tapsSeries,
          color: const Color(0xFF0F9D58),
        ),
        const SizedBox(height: 12),
        _TrendRow(
          label: 'Clicks en enlace',
          total: clicksSeries.fold(0, (a, b) => a + b),
          series: clicksSeries,
          color: const Color(0xFFE67E22),
        ),
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  final String label;
  final int total;
  final List<int> series;
  final Color color;

  const _TrendRow({
    required this.label,
    required this.total,
    required this.series,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = series.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '$total',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(series.length, (index) {
              final value = series[index];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == series.length - 1 ? 0 : 6,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: ((value / maxValue) * 48)
                                .clamp(4, 48)
                                .toDouble(),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dayLabel(index),
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _TopMembersColumn extends StatelessWidget {
  final List<TeamMemberModel> members;

  const _TopMembersColumn({required this.members});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top desempeño',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Miembros con mayor impacto comercial.',
          style: GoogleFonts.dmSans(fontSize: 12, color: context.textSecondary),
        ),
        const SizedBox(height: 12),
        ...members
            .take(4)
            .toList()
            .asMap()
            .entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      '${entry.key + 1}.',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value.name,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            '${entry.value.leads} leads · ${entry.value.totalClicks} clicks · ${entry.value.taps} taps',
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
              ),
            ),
      ],
    );
  }
}

class _MemberAnalyticsCard extends StatefulWidget {
  final TeamMemberModel member;
  final List<LeadModel> leads;
  final int rank;

  const _MemberAnalyticsCard({
    required this.member,
    required this.leads,
    required this.rank,
  });

  @override
  State<_MemberAnalyticsCard> createState() => _MemberAnalyticsCardState();
}

class _MemberAnalyticsCardState extends State<_MemberAnalyticsCard> {
  String? _selectedLeadId;

  @override
  void didUpdateWidget(covariant _MemberAnalyticsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedLeadId == null) return;
    final stillExists = widget.leads.any((lead) => lead.id == _selectedLeadId);
    if (!stillExists) {
      _selectedLeadId = widget.leads.isNotEmpty ? widget.leads.first.id : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final selectedLead = widget.leads.firstWhere(
      (lead) => lead.id == _selectedLeadId,
      orElse: () => widget.leads.isNotEmpty ? widget.leads.first : _emptyLead,
    );
    final hasSelectedLead = widget.leads.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _teamAnalyticsSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _teamAnalyticsBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MemberOverviewHeader(member: widget.member, rank: widget.rank),
          const SizedBox(height: 18),
          _MemberKpiGrid(
            member: widget.member,
            leadsCount: widget.leads.length,
          ),
          const SizedBox(height: 22),
          isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _MemberFunnelPanel(member: widget.member),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _MemberLinksPanel(
                        linkStats: widget.member.linkStats,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _MemberFunnelPanel(member: widget.member),
                    const SizedBox(height: 18),
                    _MemberLinksPanel(linkStats: widget.member.linkStats),
                  ],
                ),
          const SizedBox(height: 22),
          _MemberLeadsPanel(
            leads: widget.leads,
            selectedLead: hasSelectedLead ? selectedLead : null,
            onSelectLead: (lead) {
              setState(() => _selectedLeadId = lead.id);
            },
          ),
        ],
      ),
    );
  }
}

class _MemberOverviewHeader extends StatelessWidget {
  final TeamMemberModel member;
  final int rank;

  const _MemberOverviewHeader({required this.member, required this.rank});

  @override
  Widget build(BuildContext context) {
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
                    member.name,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'Miembro #$rank',
                      if (member.jobTitle.trim().isNotEmpty) member.jobTitle,
                    ].join(' · '),
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
        const SizedBox(height: 14),
        Divider(color: context.borderColor, height: 1),
      ],
    );
  }
}

class _MemberKpiGrid extends StatelessWidget {
  final TeamMemberModel member;
  final int leadsCount;

  const _MemberKpiGrid({required this.member, required this.leadsCount});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Visitas', '${member.profileViews}'),
      ('Taps', '${member.taps}'),
      ('Clicks', '${member.totalClicks}'),
      ('Leads', '$leadsCount'),
    ];
    return Wrap(
      spacing: 28,
      runSpacing: 14,
      children: items
          .map(
            (item) => SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$2,
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.$1,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MemberFunnelPanel extends StatelessWidget {
  final TeamMemberModel member;

  const _MemberFunnelPanel({required this.member});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _FunnelStepData(
        label: 'Vistas',
        value: member.profileViews,
        color: AppColors.primary,
      ),
      _FunnelStepData(
        label: 'Taps',
        value: member.taps,
        color: const Color(0xFF0F9D58),
      ),
      _FunnelStepData(
        label: 'Clicks',
        value: member.totalClicks,
        color: const Color(0xFFE67E22),
      ),
      _FunnelStepData(
        label: 'Leads',
        value: member.leads,
        color: const Color(0xFFEF6820),
      ),
    ];

    return _MemberSectionPanel(
      title: 'Embudo de conversión',
      subtitle: 'Dónde avanza la interacción y dónde se cae el flujo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...steps.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final previous = index == 0 ? null : steps[index - 1];
            final ratio = previous == null || previous.value == 0
                ? 1.0
                : item.value / previous.value;
            final isLast = index == steps.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: _FunnelStepRow(
                data: item,
                ratio: ratio.clamp(0.0, 1.0),
                percentage: previous == null
                    ? null
                    : previous.value == 0
                    ? 0
                    : ((item.value / previous.value) * 100).round(),
              ),
            );
          }),
          const SizedBox(height: 16),
          Text(
            _funnelInsight(member),
            style: GoogleFonts.dmSans(
              fontSize: 12,
              height: 1.55,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelStepData {
  final String label;
  final int value;
  final Color color;

  const _FunnelStepData({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _FunnelStepRow extends StatelessWidget {
  final _FunnelStepData data;
  final double ratio;
  final int? percentage;

  const _FunnelStepRow({
    required this.data,
    required this.ratio,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              data.label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${data.value}',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
            if (percentage != null) ...[
              const SizedBox(width: 8),
              Text(
                '$percentage%',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return Stack(
                children: [
                  Container(height: 12, color: context.borderColor),
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.04, 1.0),
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(color: data.color),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MemberLinksPanel extends StatelessWidget {
  final List<TeamMemberLinkStat> linkStats;

  const _MemberLinksPanel({required this.linkStats});

  @override
  Widget build(BuildContext context) {
    final ranked = [...linkStats]..sort((a, b) => b.clicks.compareTo(a.clicks));
    final total = ranked.fold<int>(0, (sum, link) => sum + link.clicks);
    return _MemberSectionPanel(
      title: 'Top links e insight',
      subtitle: 'Qué enlace concentra la intención y qué canal pesa más.',
      child: ranked.isEmpty
          ? Text(
              'Sin clicks en enlaces registrados.',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...ranked.take(5).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final link = entry.value;
                  final maxClicks = ranked.first.clicks == 0
                      ? 1
                      : ranked.first.clicks;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == ranked.take(5).length - 1 ? 0 : 12,
                    ),
                    child: _LinkInsightRow(
                      link: link,
                      rank: index + 1,
                      ratio: link.clicks / maxClicks,
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  _topLinkInsight(ranked, total),
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    height: 1.55,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
    );
  }
}

class _MemberLeadsPanel extends StatelessWidget {
  final List<LeadModel> leads;
  final LeadModel? selectedLead;
  final ValueChanged<LeadModel> onSelectLead;

  const _MemberLeadsPanel({
    required this.leads,
    required this.selectedLead,
    required this.onSelectLead,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return _MemberSectionPanel(
      title: 'Leads capturados',
      subtitle:
          'Lista priorizada por intención; el detalle de interacción aparece al seleccionar un lead.',
      child: leads.isEmpty
          ? Text(
              'No hay leads registrados para este miembro.',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            )
          : isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      const _LeadListHeader(),
                      const SizedBox(height: 10),
                      ...leads.map(
                        (lead) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LeadCompactCard(
                            lead: lead,
                            selected: selectedLead?.id == lead.id,
                            onTap: () => onSelectLead(lead),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 5,
                  child: selectedLead == null
                      ? const SizedBox.shrink()
                      : _LeadDetailPanel(lead: selectedLead!),
                ),
              ],
            )
          : Column(
              children: [
                const _LeadListHeader(),
                const SizedBox(height: 10),
                ...leads.map(
                  (lead) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LeadCompactCard(
                      lead: lead,
                      selected: selectedLead?.id == lead.id,
                      onTap: () => onSelectLead(lead),
                    ),
                  ),
                ),
                if (selectedLead != null) _LeadDetailPanel(lead: selectedLead!),
              ],
            ),
    );
  }
}

class _MemberSectionPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _MemberSectionPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LeadListHeader extends StatelessWidget {
  const _LeadListHeader();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.dmSans(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: context.textMuted,
      letterSpacing: 0.8,
    );

    return Row(
      children: [
        Expanded(flex: 5, child: Text('LEAD', style: style)),
        Expanded(flex: 3, child: Text('SEÑALES', style: style)),
      ],
    );
  }
}

class _LinkInsightRow extends StatelessWidget {
  final TeamMemberLinkStat link;
  final int rank;
  final double ratio;

  const _LinkInsightRow({
    required this.link,
    required this.rank,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$rank.',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _platformIcon(link.platform),
              size: 15,
              color: context.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: context.textPrimary,
                  ),
                  children: [
                    TextSpan(
                      text: link.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '  ${link.clicks}',
                      style: TextStyle(
                        fontFamily: GoogleFonts.outfit().fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 8, color: context.borderColor),
              FractionallySizedBox(
                widthFactor: ratio.clamp(0.05, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFE67E22).withValues(alpha: 0.65),
                        const Color(0xFFE67E22),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeadCompactCard extends StatelessWidget {
  final LeadModel lead;
  final bool selected;
  final VoidCallback onTap;

  const _LeadCompactCard({
    required this.lead,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tags = _leadTags(lead);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : _teamAnalyticsSurfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? const Color(0xFFFFC7A8)
              : _teamAnalyticsBorderColor(context),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lead.displayName,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if ((lead.company ?? '').trim().isNotEmpty)
                            lead.company!,
                          'Última actividad ${_relativeDate(lead.lastSeen)}',
                        ].join(' · '),
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    tags.take(2).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
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

class _LeadDetailFact extends StatelessWidget {
  final String label;
  final String value;

  const _LeadDetailFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 11, color: context.textSecondary),
        ),
      ],
    );
  }
}

class _LeadDetailPanel extends StatelessWidget {
  final LeadModel lead;

  const _LeadDetailPanel({required this.lead});

  @override
  Widget build(BuildContext context) {
    final actions = [...lead.actions]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _teamAnalyticsSurfaceColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _teamAnalyticsBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lead.displayName,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if ((lead.company ?? '').trim().isNotEmpty) lead.company!,
                  if ((lead.location ?? '').trim().isNotEmpty) lead.location!,
                ].join(' · '),
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _LeadDetailFact(
                label: 'Primera visita',
                value: _relativeDate(lead.firstSeen),
              ),
              _LeadDetailFact(
                label: 'Último evento',
                value: _relativeDate(lead.lastSeen),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            lead.aiSummary,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              height: 1.55,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Recorrido de interacción',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Desliza para ver más',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          actions.isEmpty
              ? Text(
                  'Sin eventos detallados todavía.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                )
              : _LeadJourneyTimeline(actions: actions),
        ],
      ),
    );
  }
}

class _LeadJourneyTimeline extends StatelessWidget {
  final List<LeadActionEvent> actions;

  const _LeadJourneyTimeline({required this.actions});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: actions.asMap().entries.map((entry) {
          final isLast = entry.key == actions.length - 1;
          final action = entry.value;
          return Row(
            children: [
              Container(
                width: 156,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _teamAnalyticsSurfaceColor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _teamAnalyticsBorderColor(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relativeDate(action.timestamp),
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: context.textMuted,
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

final LeadModel _emptyLead = LeadModel(
  id: '__empty__',
  firstSeen: DateTime.fromMillisecondsSinceEpoch(0),
  lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
);

String _funnelInsight(TeamMemberModel member) {
  final viewToTap = member.profileViews == 0
      ? 0
      : ((member.taps / member.profileViews) * 100).round();
  final tapToClick = member.taps == 0
      ? 0
      : ((member.totalClicks / member.taps) * 100).round();
  final clickToLead = member.totalClicks == 0
      ? 0
      : ((member.leads / member.totalClicks) * 100).round();

  if (tapToClick < viewToTap && tapToClick < clickToLead) {
    return 'El mayor drop-off ocurre entre taps y clicks. Conviene reforzar CTAs y enlaces de alto valor.';
  }
  if (clickToLead < 20 && member.totalClicks > 0) {
    return 'Hay interés real, pero los clicks todavía no convierten en lead con suficiente fuerza.';
  }
  return 'El flujo se mantiene sano desde la visita hasta el lead. Este miembro sostiene intención comercial consistente.';
}

String _topLinkInsight(List<TeamMemberLinkStat> links, int totalClicks) {
  if (links.isEmpty || totalClicks == 0) {
    return 'Aún no hay suficiente interacción para detectar un canal dominante.';
  }
  final top = links.first;
  final share = ((top.clicks / totalClicks) * 100).round();
  return '${top.label} genera el $share% de la interacción total en enlaces.';
}

List<String> _leadTags(LeadModel lead) {
  final tags = <String>{};
  for (final action in lead.actions) {
    switch (action.action) {
      case LeadAction.visitedProfile:
        tags.add('Visita');
        break;
      case LeadAction.clickedLinkedIn:
        tags.add('LinkedIn');
        break;
      case LeadAction.clickedWebsite:
        tags.add('Web');
        break;
      case LeadAction.clickedWhatsApp:
        tags.add('WhatsApp');
        break;
      case LeadAction.downloadedContact:
        tags.add('Contacto');
        break;
      case LeadAction.filledForm:
        tags.add('Formulario');
        break;
    }
  }
  return tags.take(4).toList();
}

IconData _platformIcon(String platform) {
  switch (platform.toLowerCase()) {
    case 'linkedin':
      return Icons.work_outline_rounded;
    case 'instagram':
      return Icons.camera_alt_outlined;
    case 'facebook':
      return Icons.facebook_outlined;
    case 'whatsapp':
      return Icons.chat_outlined;
    case 'website':
    case 'web':
      return Icons.language_outlined;
    default:
      return Icons.link_rounded;
  }
}

String _dayLabel(int index) {
  const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  return labels[index % labels.length];
}

String _relativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes.clamp(1, 59)} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'hace ${diff.inDays} d';
  return '${date.day}/${date.month}/${date.year}';
}
