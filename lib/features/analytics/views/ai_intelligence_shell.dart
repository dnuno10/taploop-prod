import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import 'lead_intelligence_view.dart';
import 'team_performance_view.dart';
import 'sales_outcome_view.dart';

class AIIntelligenceShell extends StatefulWidget {
  const AIIntelligenceShell({super.key});

  @override
  State<AIIntelligenceShell> createState() => _AIIntelligenceShellState();
}

class _AIIntelligenceShellState extends State<AIIntelligenceShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: context.bgCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'IA',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Inteligencia',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              Container(height: 1, color: context.borderColor),
              TabBar(
                controller: _tabController,
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                labelColor: AppColors.primary,
                unselectedLabelColor: context.textMuted,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(text: 'Leads'),
                  Tab(text: 'Equipo'),
                  Tab(text: 'Ventas'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TabBody(child: LeadIntelligenceView()),
          _TabBody(child: TeamPerformanceView()),
          _TabBody(child: SalesOutcomeView()),
        ],
      ),
    );
  }
}

/// Strips the inner Scaffold's AppBar since the shell provides navigation.
class _TabBody extends StatelessWidget {
  final Widget child;
  const _TabBody({required this.child});

  @override
  Widget build(BuildContext context) => child;
}
