// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/taploop_button.dart';
import '../../../core/widgets/taploop_text_field.dart';
import '../../analytics/models/team_member_model.dart';
import '../../card/models/digital_card_model.dart';
import '../../card/models/contact_item_model.dart';
import '../../card/models/social_link_model.dart';
import '../../card/widgets/digital_profile_preview.dart';

// ─── Form & Calendar support ─────────────────────────────────────────────────

enum _AdminFieldType { text, email, phone, textarea, select }

extension _AdminFieldTypeX on _AdminFieldType {
  String get label => switch (this) {
    _AdminFieldType.text => 'Texto',
    _AdminFieldType.email => 'Email',
    _AdminFieldType.phone => 'Teléfono',
    _AdminFieldType.textarea => 'Mensaje',
    _AdminFieldType.select => 'Selección',
  };

  IconData get icon => switch (this) {
    _AdminFieldType.text => Icons.short_text,
    _AdminFieldType.email => Icons.alternate_email,
    _AdminFieldType.phone => Icons.phone_outlined,
    _AdminFieldType.textarea => Icons.notes_outlined,
    _AdminFieldType.select => Icons.arrow_drop_down_circle_outlined,
  };

  Color get color => switch (this) {
    _AdminFieldType.text => const Color(0xFF64748B),
    _AdminFieldType.email => AppColors.primary,
    _AdminFieldType.phone => const Color(0xFF10B981),
    _AdminFieldType.textarea => const Color(0xFFF59E0B),
    _AdminFieldType.select => const Color(0xFF8B5CF6),
  };
}

class _AdminFormField {
  String label;
  _AdminFieldType type;
  bool required;
  _AdminFormField({
    required this.label,
    this.type = _AdminFieldType.text,
    this.required = false,
  });
}

class _AdminSmartForm {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  bool enabled;
  List<_AdminFormField> fields;
  _AdminSmartForm({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.enabled = false,
    required this.fields,
  });
}

enum _AdminCalProvider { googleCalendar, calendly, outlook }

extension _AdminCalProviderX on _AdminCalProvider {
  String get label => switch (this) {
    _AdminCalProvider.googleCalendar => 'Google Calendar',
    _AdminCalProvider.calendly => 'Calendly',
    _AdminCalProvider.outlook => 'Outlook',
  };

  IconData get icon => switch (this) {
    _AdminCalProvider.googleCalendar => Icons.event_outlined,
    _AdminCalProvider.calendly => Icons.calendar_today_outlined,
    _AdminCalProvider.outlook => Icons.mail_outline_rounded,
  };

  String get hint => switch (this) {
    _AdminCalProvider.googleCalendar => 'https://calendar.google.com/...',
    _AdminCalProvider.calendly => 'https://calendly.com/tu-nombre',
    _AdminCalProvider.outlook => 'https://outlook.office365.com/...',
  };
}

// ─── Local data model ─────────────────────────────────────────────────────────

class _AdminMember {
  final TeamMemberModel member;
  DigitalCardModel card;
  bool isActive;
  List<_AdminSmartForm> forms;
  _AdminCalProvider? calendarProvider;
  String? calendarioUrl;

  _AdminMember({
    required this.member,
    required this.card,
    this.isActive = true,
    List<_AdminSmartForm>? forms,
    this.calendarProvider,
    this.calendarioUrl,
  }) : forms = forms ?? _defaultForms();

  static List<_AdminSmartForm> _defaultForms() => [
    _AdminSmartForm(
      id: 'cotizacion',
      title: 'Solicitar cotización',
      description:
          'El prospecto llena sus datos y recibe una cotización personalizada.',
      icon: Icons.request_quote_outlined,
      enabled: true,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Empresa',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Teléfono',
          type: _AdminFieldType.phone,
          required: true,
        ),
        _AdminFormField(
          label: 'Correo electrónico',
          type: _AdminFieldType.email,
        ),
        _AdminFormField(
          label: 'Descripción del proyecto',
          type: _AdminFieldType.textarea,
          required: true,
        ),
      ],
    ),
    _AdminSmartForm(
      id: 'demo',
      title: 'Agendar demo',
      description: 'El prospecto reserva una demostración en el calendario.',
      icon: Icons.videocam_outlined,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Correo electrónico',
          type: _AdminFieldType.email,
          required: true,
        ),
        _AdminFormField(label: 'Teléfono', type: _AdminFieldType.phone),
        _AdminFormField(label: 'Área de interés', type: _AdminFieldType.text),
      ],
    ),
    _AdminSmartForm(
      id: 'catalogo',
      title: 'Descargar catálogo',
      description: 'El prospecto deja su email para recibir el catálogo.',
      icon: Icons.download_outlined,
      enabled: true,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Correo corporativo',
          type: _AdminFieldType.email,
          required: true,
        ),
        _AdminFormField(label: 'Empresa', type: _AdminFieldType.text),
      ],
    ),
    _AdminSmartForm(
      id: 'contacto',
      title: 'Formulario de contacto',
      description: 'Formulario rápido ideal para ferias y eventos.',
      icon: Icons.contact_page_outlined,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(label: 'Empresa', type: _AdminFieldType.text),
        _AdminFormField(
          label: 'Mensaje',
          type: _AdminFieldType.textarea,
          required: true,
        ),
      ],
    ),
  ];
}

// ─── AdminView ────────────────────────────────────────────────────────────────

class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  List<_AdminMember> _members = [];
  bool _loading = true;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeOrgId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _loadData();
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
    if (!mounted || orgId == null) return;
    setState(() => _loading = true);
    _loadData();
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
        _loadData();
      },
    );
  }

  Future<void> _loadData() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final teamMembers = await AdminRepository.fetchTeamMembers(orgId);
      final hydratedMembers = await _buildMembers(teamMembers);
      if (mounted) {
        setState(() {
          _members = hydratedMembers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<List<_AdminMember>> _buildMembers(
    List<TeamMemberModel> teamMembers,
  ) async {
    final styles = [
      CardThemeStyle.white,
      CardThemeStyle.frosted,
      CardThemeStyle.dark,
      CardThemeStyle.custom,
    ];
    final colors = [
      const Color(0xFF0D0D0D),
      const Color(0xFF1F2937),
      const Color(0xFF374151),
      const Color(0xFF6B7280),
    ];
    return Future.wait(
      teamMembers.asMap().entries.map((e) async {
        final i = e.key;
        final m = e.value;
        final fetchedCard = await AdminRepository.fetchCardForUser(m.id);
        final card =
            fetchedCard ??
            _fallbackCard(member: m, index: i, colors: colors, styles: styles);

        return _AdminMember(
          member: m,
          card: card,
          isActive: card.isActive,
          forms: _formsFromCard(card),
          calendarProvider: _providerFromUrl(card.calendarUrl),
          calendarioUrl: card.calendarUrl,
        );
      }),
    );
  }

  static DigitalCardModel _fallbackCard({
    required TeamMemberModel member,
    required int index,
    required List<Color> colors,
    required List<CardThemeStyle> styles,
  }) {
    return DigitalCardModel(
      id: member.cardIds.isNotEmpty ? member.cardIds.first : member.id,
      userId: member.id,
      name: member.name,
      jobTitle: member.jobTitle,
      company: '',
      publicSlug: member.name.toLowerCase().replaceAll(' ', '-'),
      themeStyle: styles[index % styles.length],
      primaryColor: colors[index % colors.length],
      contactItems: const [],
      socialLinks: const [],
    );
  }

  static List<_AdminSmartForm> _formsFromCard(DigitalCardModel card) {
    final enabledIds = card.enabledForms.toSet();
    return _AdminMember._defaultForms()
        .map(
          (form) => _AdminSmartForm(
            id: form.id,
            title: form.title,
            description: form.description,
            icon: form.icon,
            enabled: enabledIds.contains(form.id),
            fields: form.fields
                .map(
                  (field) => _AdminFormField(
                    label: field.label,
                    type: field.type,
                    required: field.required,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  static _AdminCalProvider? _providerFromUrl(String? url) {
    final value = url?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (value.contains('calendly')) return _AdminCalProvider.calendly;
    if (value.contains('calendar.google')) {
      return _AdminCalProvider.googleCalendar;
    }
    if (value.contains('outlook') || value.contains('office365')) {
      return _AdminCalProvider.outlook;
    }
    return null;
  }

  void _editMember(_AdminMember member) {
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: ctx.bgCard,
          child: SizedBox(
            width: (MediaQuery.of(ctx).size.width * 0.9)
                .clamp(960.0, 1180.0)
                .toDouble(),
            height: MediaQuery.of(context).size.height * 0.88,
            child: _EditMemberDialog(
              member: member,
              onSave: (updated) {
                setState(() {
                  final idx = _members.indexWhere(
                    (m) => m.member.id == updated.member.id,
                  );
                  if (idx != -1) _members[idx] = updated;
                });
              },
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (ctx, ctrl) => Container(
            decoration: BoxDecoration(
              color: ctx.bgCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: _EditMemberDialog(
              member: member,
              scrollController: ctrl,
              onSave: (updated) {
                setState(() {
                  final idx = _members.indexWhere(
                    (m) => m.member.id == updated.member.id,
                  );
                  if (idx != -1) _members[idx] = updated;
                });
              },
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isDesktop = Responsive.isDesktop(context);
    final hPad = Responsive.isMobile(context)
        ? 20.0
        : isDesktop
        ? 48.0
        : 32.0;
    final activeMembers = _members.where((member) => member.isActive).toList();
    final activeCount = activeMembers.length;
    final totalTaps = activeMembers.fold(
      0,
      (sum, member) => sum + member.member.taps,
    );
    final totalLeads = activeMembers.fold(
      0,
      (sum, member) => sum + member.member.leads,
    );
    final totalViews = activeMembers.fold(
      0,
      (sum, member) => sum + member.member.profileViews,
    );
    final totalClicks = activeMembers.fold(
      0,
      (sum, member) => sum + member.member.totalClicks,
    );
    final viewsSeries = _sumAdminSeries(
      activeMembers.map((member) => member.member.viewsByDay).toList(),
    );
    final tapsSeries = _sumAdminSeries(
      activeMembers.map((member) => member.member.tapsByDay).toList(),
    );
    final clicksSeries = _sumAdminSeries(
      activeMembers.map((member) => member.member.clicksByDay).toList(),
    );
    final rankedMembers = [...activeMembers]
      ..sort((a, b) => b.member.leads.compareTo(a.member.leads));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: context.bgCard,
              padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administración',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Controla el equipo, formularios, calendario y configuración operativa desde un solo lugar.',
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
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─ Company header ──────────────────────────
                    _CompanyHeader(),
                    const SizedBox(height: 18),

                    _AdminSummaryStrip(
                      activeCount: activeCount,
                      totalCount: _members.length,
                      totalTaps: totalTaps,
                      totalLeads: totalLeads,
                      totalViews: totalViews,
                      totalClicks: totalClicks,
                    ),
                    const SizedBox(height: 18),

                    isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _AdminPerformancePanel(
                                  viewsSeries: viewsSeries,
                                  tapsSeries: tapsSeries,
                                  clicksSeries: clicksSeries,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 4,
                                child: _AdminTeamHighlights(
                                  members: rankedMembers,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _AdminPerformancePanel(
                                viewsSeries: viewsSeries,
                                tapsSeries: tapsSeries,
                                clicksSeries: clicksSeries,
                              ),
                              const SizedBox(height: 16),
                              _AdminTeamHighlights(members: rankedMembers),
                            ],
                          ),
                    const SizedBox(height: 24),

                    // ─ Members list ───────────────────────────
                    Text(
                      'Equipo',
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    isDesktop
                        ? _DesktopMemberGrid(
                            members: _members,
                            onEdit: _editMember,
                            onToggle: _toggleMember,
                          )
                        : _MobileMembers(
                            members: _members,
                            onEdit: _editMember,
                            onToggle: _toggleMember,
                          ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMember(_AdminMember m, bool value) async {
    final previous = m.isActive;
    setState(() => m.isActive = value);
    try {
      await AdminRepository.updateCardActivation(
        cardId: m.card.id,
        isActive: value,
        reason: value ? null : 'Tarjeta digital desactivada por seguridad',
      );
      m.card = m.card.copyWith(
        isActive: value,
        deactivatedAt: value ? null : DateTime.now(),
        deactivationReason: value
            ? null
            : 'Tarjeta digital desactivada por seguridad',
      );
      if (appState.currentCard?.id == m.card.id) {
        appState.updateCard(m.card);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => m.isActive = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la tarjeta: $e')),
      );
    }
  }
}

// ─── Company Header ───────────────────────────────────────────────────────────

class _CompanyHeader extends StatefulWidget {
  const _CompanyHeader();

  @override
  State<_CompanyHeader> createState() => _CompanyHeaderState();
}

class _CompanyHeaderState extends State<_CompanyHeader> {
  bool _uploading = false;
  String? _organizationLogoUrl;
  String? _organizationLogoPath;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _loadOrganizationLogo();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    _loadOrganizationLogo();
  }

  Future<void> _loadOrganizationLogo() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _organizationLogoUrl = null;
        _organizationLogoPath = null;
      });
      return;
    }
    final orgData = await AdminRepository.fetchOrg(orgId);
    final logoPath = orgData?['company_logo'] as String?;
    final logoUrl = CardRepository.resolveCompanyLogoUrl(logoPath);
    if (!mounted) return;
    setState(() {
      _organizationLogoPath = logoPath;
      _organizationLogoUrl = logoUrl;
    });
  }

  String _initials(String company) {
    final parts = company.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  Future<void> _pickAndUploadLogo() async {
    if (!kIsWeb || _uploading) return;
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) return;

    final input = html.FileUploadInputElement()
      ..accept = 'image/jpeg,image/png,image/webp,image/svg+xml';
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;

    if (file.size > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La imagen supera el limite de 5 MB.')),
        );
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final bytes = reader.result as Uint8List;

      final ext = file.type.contains('png')
          ? 'png'
          : file.type.contains('svg')
          ? 'svg'
          : 'jpg';
      final path = '$orgId/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseService.client.storage
          .from('company-logos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: file.type),
          );

      await AdminRepository.updateOrgLogo(orgId: orgId, companyLogo: path);

      final previousPath = _organizationLogoPath;
      if (previousPath != null &&
          previousPath.isNotEmpty &&
          previousPath != path) {
        try {
          await SupabaseService.client.storage.from('company-logos').remove([
            previousPath,
          ]);
        } catch (_) {}
      }

      final rawUrl = CardRepository.resolveCompanyLogoUrl(path);
      final updatedLogoUrl = rawUrl == null
          ? null
          : '$rawUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      final currentCard = appState.currentCard;
      if (updatedLogoUrl != null &&
          currentCard != null &&
          currentCard.orgId == orgId) {
        appState.updateCard(
          currentCard.copyWith(companyLogoUrl: updatedLogoUrl),
        );
      }
      if (mounted) {
        setState(() {
          _organizationLogoPath = path;
          _organizationLogoUrl = updatedLogoUrl;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Logo actualizado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir logo: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final card = appState.currentCard;
        final company = card?.company ?? '';
        final logoUrl = _organizationLogoUrl ?? card?.companyLogoUrl;
        final content = Row(
          children: [
            GestureDetector(
              onTap: appState.currentUser?.orgId == null
                  ? null
                  : _pickAndUploadLogo,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: context.bgPage,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                  image: logoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(logoUrl),
                          fit: BoxFit.contain,
                        )
                      : null,
                ),
                child: logoUrl == null
                    ? Center(
                        child: Text(
                          _initials(company),
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: context.textSecondary,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    company,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Centro de administración del equipo y su operación comercial.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                  if (appState.currentUser?.orgId != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickAndUploadLogo,
                      icon: _uploading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.textPrimary,
                              ),
                            )
                          : const Icon(Icons.upload_outlined, size: 16),
                      label: Text(_uploading ? 'Cargando...' : 'Cargar imagen'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: context.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: content,
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
      },
    );
  }
}

// ─── Summary Strip ────────────────────────────────────────────────────────────

class _AdminSummaryStrip extends StatelessWidget {
  final int activeCount;
  final int totalCount;
  final int totalTaps;
  final int totalLeads;
  final int totalViews;
  final int totalClicks;

  const _AdminSummaryStrip({
    required this.activeCount,
    required this.totalCount,
    required this.totalTaps,
    required this.totalLeads,
    required this.totalViews,
    required this.totalClicks,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('$activeCount / $totalCount', 'Miembros activos', Icons.people_outlined),
      ('$totalViews', 'Vistas del equipo', Icons.visibility_outlined),
      ('$totalTaps', 'Taps del equipo', Icons.touch_app_outlined),
      ('$totalClicks', 'Clicks en enlace', Icons.ads_click_outlined),
      ('$totalLeads', 'Leads del equipo', Icons.bolt_outlined),
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: stats.asMap().entries.map((entry) {
          final s = entry.value;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(s.$3, size: 16, color: context.textSecondary),
                      const SizedBox(height: 6),
                      Text(
                        s.$1,
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.$2,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.key < stats.length - 1)
                  Container(width: 1, height: 42, color: context.borderColor),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AdminPerformancePanel extends StatelessWidget {
  final List<int> viewsSeries;
  final List<int> tapsSeries;
  final List<int> clicksSeries;

  const _AdminPerformancePanel({
    required this.viewsSeries,
    required this.tapsSeries,
    required this.clicksSeries,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rendimiento del equipo',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Vista consolidada de vistas, taps y clicks en enlaces de todos los miembros activos.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _AdminTrendRow(
            label: 'Vistas',
            total: viewsSeries.fold(0, (a, b) => a + b),
            series: viewsSeries,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _AdminTrendRow(
            label: 'Taps',
            total: tapsSeries.fold(0, (a, b) => a + b),
            series: tapsSeries,
            color: const Color(0xFF0F9D58),
          ),
          const SizedBox(height: 12),
          _AdminTrendRow(
            label: 'Clicks en enlace',
            total: clicksSeries.fold(0, (a, b) => a + b),
            series: clicksSeries,
            color: const Color(0xFFE67E22),
          ),
        ],
      ),
    );
  }
}

class _AdminTrendRow extends StatelessWidget {
  final String label;
  final int total;
  final List<int> series;
  final Color color;

  const _AdminTrendRow({
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
                        _adminDayLabel(index),
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

class _AdminTeamHighlights extends StatelessWidget {
  final List<_AdminMember> members;

  const _AdminTeamHighlights({required this.members});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Highlights del equipo',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Miembros con mayor generación de leads y actividad comercial.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (members.isEmpty)
            Text(
              'Sin miembros activos.',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            )
          else
            ...members
                .take(4)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: entry.key == 3 ? 0 : 12),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.bgPage,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value.member.name,
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                '${entry.value.member.leads} leads · ${entry.value.member.totalClicks} clicks · ${entry.value.member.taps} taps',
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
      ),
    );
  }
}

// ─── Desktop Grid ─────────────────────────────────────────────────────────────

class _DesktopMemberGrid extends StatelessWidget {
  final List<_AdminMember> members;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;
  const _DesktopMemberGrid({
    required this.members,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 100,
      ),
      itemCount: members.length,
      itemBuilder: (_, i) =>
          _MemberCard(member: members[i], onEdit: onEdit, onToggle: onToggle),
    );
  }
}

// ─── Mobile List ──────────────────────────────────────────────────────────────

class _MobileMembers extends StatelessWidget {
  final List<_AdminMember> members;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;
  const _MobileMembers({
    required this.members,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: members
          .map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MemberCard(member: m, onEdit: onEdit, onToggle: onToggle),
            ),
          )
          .toList(),
    );
  }
}

// ─── Member Card ──────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final _AdminMember member;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;
  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final m = member.member;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: member.isActive ? context.bgCard : context.bgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m.name,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: member.isActive
                        ? context.textPrimary
                        : context.textMuted,
                  ),
                ),
                Text(
                  m.jobTitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${m.taps} taps · ${m.conversions} conv.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Switch.adaptive(
                value: member.isActive,
                onChanged: (v) => onToggle(member, v),
                activeTrackColor: context.textPrimary,
              ),
              const SizedBox(height: 4),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onEdit(member),
                  child: Text(
                    'Editar',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Edit Member Dialog / Sheet ───────────────────────────────────────────────

class _EditMemberDialog extends StatefulWidget {
  final _AdminMember member;
  final ValueChanged<_AdminMember> onSave;
  final ScrollController? scrollController;
  const _EditMemberDialog({
    required this.member,
    required this.onSave,
    this.scrollController,
  });

  @override
  State<_EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends State<_EditMemberDialog>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _companyCtrl;
  late DigitalCardModel _card;
  late List<TextEditingController> _contactCtrls;
  late List<TextEditingController> _contactLabelCtrls;
  late List<TextEditingController> _socialCtrls;
  late List<TextEditingController> _socialLabelCtrls;
  late List<_AdminSmartForm> _forms;
  _AdminCalProvider? _calProvider;
  late TextEditingController _calUrlCtrl;

  static const _preferredColors = <Color>[
    Color(0xFF0D0D0D),
    AppColors.primary,
    Color(0xFF6C4FE8),
    Color(0xFF1A73E8),
    Color(0xFF1A8C4E),
    Color(0xFFD93025),
    Color(0xFF00ACC1),
    Color(0xFFF5A623),
  ];

  static const _steps = <_AdminEditStepData>[
    _AdminEditStepData('Perfil', Icons.person_outline_rounded),
    _AdminEditStepData('Contacto', Icons.call_outlined),
    _AdminEditStepData('Redes', Icons.alternate_email_rounded),
    _AdminEditStepData('Diseño', Icons.palette_outlined),
    _AdminEditStepData('Formularios', Icons.description_outlined),
    _AdminEditStepData('Calendario', Icons.calendar_today_outlined),
  ];

  int get _stepIndex => _tabController.index;
  bool get _unsaved => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _card = widget.member.card;
    _nameCtrl = TextEditingController(text: _card.name);
    _titleCtrl = TextEditingController(text: _card.jobTitle);
    _bioCtrl = TextEditingController(text: _card.bio ?? '');
    _companyCtrl = TextEditingController(text: _card.company);
    _contactCtrls = _card.contactItems
        .map((c) => TextEditingController(text: c.value))
        .toList();
    _contactLabelCtrls = _card.contactItems
        .map((c) => TextEditingController(text: c.label ?? ''))
        .toList();
    _socialCtrls = _card.socialLinks
        .map((s) => TextEditingController(text: s.url))
        .toList();
    _socialLabelCtrls = _card.socialLinks
        .map((s) => TextEditingController(text: s.customLabel ?? ''))
        .toList();
    // Deep-copy forms so cancelling dialog doesn't mutate originals
    _forms = widget.member.forms
        .map(
          (f) => _AdminSmartForm(
            id: f.id,
            title: f.title,
            description: f.description,
            icon: f.icon,
            enabled: f.enabled,
            fields: f.fields
                .map(
                  (fld) => _AdminFormField(
                    label: fld.label,
                    type: fld.type,
                    required: fld.required,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    _calProvider = widget.member.calendarProvider;
    _calUrlCtrl = TextEditingController(
      text: widget.member.calendarioUrl ?? '',
    );
    _nameCtrl.addListener(_updateCard);
    _titleCtrl.addListener(_updateCard);
    _bioCtrl.addListener(_updateCard);
  }

  void _updateCard() {
    setState(() {
      _card = _card.copyWith(
        name: _nameCtrl.text,
        jobTitle: _titleCtrl.text,
        bio: _bioCtrl.text,
      );
    });
  }

  void _goToStep(int index) {
    _tabController.animateTo(index);
    setState(() {});
  }

  void _prevStep() {
    if (_stepIndex > 0) {
      _goToStep(_stepIndex - 1);
    }
  }

  void _nextStep() {
    if (_stepIndex < _steps.length - 1) {
      _goToStep(_stepIndex + 1);
    }
  }

  List<bool> _stepCompletion() {
    return [
      _nameCtrl.text.trim().isNotEmpty && _titleCtrl.text.trim().isNotEmpty,
      _card.contactItems.any((item) => item.value.trim().isNotEmpty),
      _card.socialLinks.any((item) => item.url.trim().isNotEmpty),
      true,
      _forms.any((form) => form.enabled),
      _calProvider != null && _calUrlCtrl.text.trim().isNotEmpty,
    ];
  }

  void _save() {
    final updated = _AdminMember(
      member: widget.member.member,
      card: _card,
      isActive: widget.member.isActive,
      forms: _forms,
      calendarProvider: _calProvider,
      calendarioUrl: _calUrlCtrl.text.trim().isEmpty
          ? null
          : _calUrlCtrl.text.trim(),
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _bioCtrl.dispose();
    _companyCtrl.dispose();
    _calUrlCtrl.dispose();
    for (final c in _contactCtrls) {
      c.dispose();
    }
    for (final c in _contactLabelCtrls) {
      c.dispose();
    }
    for (final c in _socialCtrls) {
      c.dispose();
    }
    for (final c in _socialLabelCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDialog = widget.scrollController == null;
    final stepCompletion = _stepCompletion();
    final stepProgress = (_stepIndex + 1) / _steps.length;

    Widget contentScroll({ScrollController? controller}) {
      return SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(24),
        child: _buildTabContent(_stepIndex),
      );
    }

    Widget topHeader = Container(
      color: context.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Editar miembro',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              if (_unsaved) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Paso ${_stepIndex + 1} de ${_steps.length}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _steps[_stepIndex].label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _steps[_stepIndex].icon,
                size: 16,
                color: context.textSecondary,
              ),
              const Spacer(),
              _AdminStepNavButton(
                icon: Icons.arrow_back_rounded,
                enabled: _stepIndex > 0,
                onTap: _prevStep,
              ),
              const SizedBox(width: 6),
              _AdminStepNavButton(
                icon: Icons.arrow_forward_rounded,
                enabled: _stepIndex < _steps.length - 1,
                onTap: _nextStep,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            minHeight: 5,
            value: stepProgress,
            color: AppColors.primary,
            backgroundColor: context.borderColor,
          ),
        ],
      ),
    );

    if (isDialog) {
      return Column(
        children: [
          topHeader,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: _AdminVerticalStepRail(
                    steps: _steps,
                    completedSteps: stepCompletion,
                    currentIndex: _stepIndex,
                    onTap: _goToStep,
                  ),
                ),
                Container(width: 1, color: context.borderColor),
                Expanded(child: contentScroll()),
                Container(width: 1, color: context.borderColor),
                SizedBox(width: 320, child: _AdminPreviewPanel(card: _card)),
              ],
            ),
          ),
          Container(height: 1, color: context.borderColor),
          _AdminBottomStepNav(
            currentIndex: _stepIndex,
            totalSteps: _steps.length,
            onPrev: _prevStep,
            onNext: _nextStep,
            onSave: _save,
          ),
        ],
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        topHeader,
        _AdminHorizontalStepSelector(
          steps: _steps,
          completedSteps: stepCompletion,
          currentIndex: _stepIndex,
          onTap: _goToStep,
        ),
        Divider(color: context.borderColor, height: 1),
        Expanded(child: contentScroll(controller: widget.scrollController)),
        Container(height: 1, color: context.borderColor),
        _AdminBottomStepNav(
          currentIndex: _stepIndex,
          totalSteps: _steps.length,
          onPrev: _prevStep,
          onNext: _nextStep,
          onSave: _save,
        ),
      ],
    );
  }

  Widget _buildTabContent(int idx) {
    switch (idx) {
      case 0:
        return _buildPerfilTab();
      case 1:
        return _buildContactoTab();
      case 2:
        return _buildRedesTab();
      case 3:
        return _buildDisenoTab();
      case 4:
        return _buildFormulariosTab();
      case 5:
        return _buildCalendarioTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPerfilTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapLoopTextField(
          label: 'Nombre',
          controller: _nameCtrl,
          hint: 'Nombre completo',
        ),
        const SizedBox(height: 16),
        TapLoopTextField(
          label: 'Cargo',
          controller: _titleCtrl,
          hint: 'Cargo o puesto',
        ),
        const SizedBox(height: 16),
        TapLoopTextField(
          label: 'Empresa',
          controller: _companyCtrl,
          hint: 'Empresa',
          enabled: false,
        ),
        const SizedBox(height: 16),
        TapLoopTextField(
          label: 'Bio / Descripción',
          controller: _bioCtrl,
          hint: 'Una breve descripción profesional...',
          maxLines: 3,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildContactoTab() {
    final contacts = _card.contactItems;
    return _adminStepPageShell(
      title: 'Contacto',
      subtitle:
          '${contacts.where((c) => c.isVisible).length} de ${contacts.length} visibles',
      action: TapLoopButton(
        label: 'Añadir',
        width: 120,
        height: 38,
        icon: const Icon(Icons.add_rounded, size: 16),
        onPressed: _addContact,
      ),
      child: contacts.isEmpty
          ? const _AdminEditEmptyState(
              message: 'Sin información de contacto',
              hint: 'Añade teléfono, correo o sitio web del miembro.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildContactEditors(),
                const SizedBox(height: 12),
                Text(
                  'Activa Visible para mostrar el dato en la tarjeta del miembro.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRedesTab() {
    final socials = _card.socialLinks;
    return _adminStepPageShell(
      title: 'Redes sociales',
      subtitle:
          '${socials.where((s) => s.isVisible).length} de ${socials.length} visibles',
      action: TapLoopButton(
        label: 'Añadir',
        width: 120,
        height: 38,
        icon: const Icon(Icons.add_rounded, size: 16),
        onPressed: _addSocial,
      ),
      child: socials.isEmpty
          ? const _AdminEditEmptyState(
              message: 'Sin redes sociales',
              hint: 'Añade LinkedIn, Instagram u otros enlaces del miembro.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildSocialEditors(),
                const SizedBox(height: 12),
                Text(
                  'Los enlaces marcados como visibles aparecerán en la tarjeta.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDisenoTab() {
    final stylePreviews = [
      (CardThemeStyle.white, 'Blanco'),
      (CardThemeStyle.dark, 'Oscuro'),
      (CardThemeStyle.gradient, 'Degradado'),
      (CardThemeStyle.neon, 'Neón'),
      (CardThemeStyle.premium, 'Premium'),
      (CardThemeStyle.frosted, 'Frosted'),
      (CardThemeStyle.retro, 'Retro'),
    ];
    final layoutOptions = [
      (CardLayoutStyle.centered, 'Centrado'),
      (CardLayoutStyle.leftAligned, 'Izquierda'),
      (CardLayoutStyle.compact, 'Compacto'),
    ];
    return _adminStepPageShell(
      title: 'Diseño',
      subtitle: 'Ajusta estilo, layout y color principal de la tarjeta.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Color preferido'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _preferredColors.map((c) {
              final selected = _card.primaryColor == c;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _card = _card.copyWith(primaryColor: c)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.textPrimary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Estilo de tarjeta'),
          const SizedBox(height: 8),
          Text(
            'Selecciona el tono visual que mejor representa a este miembro.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stylePreviews.map((s) {
              final selected = _card.themeStyle == s.$1;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _card = _card.copyWith(themeStyle: s.$1)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? context.textPrimary : context.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.textPrimary
                            : context.borderColor,
                      ),
                    ),
                    child: Text(
                      s.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? (context.isDark ? Colors.black : Colors.white)
                            : context.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Layout'),
          const SizedBox(height: 8),
          Text(
            'Define cómo se organiza el contenido dentro de la tarjeta.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: layoutOptions.map((opt) {
              final selected = _card.layoutStyle == opt.$1;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(
                    () => _card = _card.copyWith(layoutStyle: opt.$1),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? context.textPrimary : context.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.textPrimary
                            : context.borderColor,
                      ),
                    ),
                    child: Text(
                      opt.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? (context.isDark ? Colors.black : Colors.white)
                            : context.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulariosTab() {
    final active = _forms.where((f) => f.enabled).length;
    return _adminStepPageShell(
      title: 'Formularios inteligentes',
      subtitle: '$active activos · cada uno crea un lead',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._forms.asMap().entries.map((e) {
            final i = e.key;
            final form = e.value;
            return Column(
              children: [
                _AdminFormRow(
                  form: form,
                  onToggle: (v) => setState(() => form.enabled = v),
                  onChanged: () => setState(() {}),
                ),
                if (i < _forms.length - 1)
                  Divider(color: context.borderColor, height: 1),
              ],
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cada formulario completado crea un lead en el pipeline del miembro.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.primary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarioTab() {
    return _adminStepPageShell(
      title: 'Calendario de reuniones',
      subtitle:
          'Conecta el calendario para que los prospectos agenden directamente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Plataforma'),
          const SizedBox(height: 12),
          ...List.generate(_AdminCalProvider.values.length, (i) {
            final provider = _AdminCalProvider.values[i];
            final selected = _calProvider == provider;
            return GestureDetector(
              onTap: () => setState(() => _calProvider = provider),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : context.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.primary : context.borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      provider.icon,
                      size: 18,
                      color: selected
                          ? AppColors.primary
                          : context.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.label,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: selected
                              ? AppColors.primary
                              : context.textPrimary,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                  ],
                ),
              ),
            );
          }),
          if (_calProvider != null) ...[
            const SizedBox(height: 16),
            _sectionTitle('URL del calendario'),
            const SizedBox(height: 10),
            TextField(
              controller: _calUrlCtrl,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: _calProvider!.hint,
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: context.bgInput,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Esta URL aparecerá en la tarjeta digital del miembro.',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color: context.textMuted,
                height: 1.5,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Selecciona una plataforma para configurar el enlace del calendario.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Text(
      label,
      style: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
      ),
    );
  }

  Widget _adminStepPageShell({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
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
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
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
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (action != null) ...[const SizedBox(width: 16), action],
                ],
              ),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContactEditors() {
    if (_card.contactItems.isEmpty) {
      return [
        Text(
          'Sin contactos todavía.',
          style: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
        ),
      ];
    }

    return _card.contactItems.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Contacto ${i + 1}',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _removeContact(i),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label: const Text('Eliminar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ContactType>(
                initialValue: item.type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: ContactType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(_contactTypeLabel(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _replaceContact(i, item.copyWith(type: v));
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactCtrls[i],
                decoration: const InputDecoration(labelText: 'Valor'),
                onChanged: (v) => _replaceContact(i, item.copyWith(value: v)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactLabelCtrls[i],
                decoration: const InputDecoration(
                  labelText: 'Etiqueta personalizada (opcional)',
                  hintText: 'Ej: Trabajo, Personal…',
                ),
                onChanged: (v) => _replaceContact(
                  i,
                  item.copyWith(label: v.trim().isEmpty ? null : v.trim()),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Switch.adaptive(
                    value: item.isVisible,
                    onChanged: (v) =>
                        _replaceContact(i, item.copyWith(isVisible: v)),
                    activeTrackColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.isVisible
                        ? 'Visible en la tarjeta'
                        : 'Oculto en la tarjeta',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: item.isVisible
                          ? context.textPrimary
                          : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildSocialEditors() {
    if (_card.socialLinks.isEmpty) {
      return [
        Text(
          'Sin redes todavía.',
          style: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
        ),
      ];
    }

    return _card.socialLinks.asMap().entries.map((entry) {
      final i = entry.key;
      final link = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Red ${i + 1}',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _removeSocial(i),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label: const Text('Eliminar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SocialPlatform>(
                initialValue: link.platform,
                decoration: const InputDecoration(labelText: 'Red'),
                items: SocialPlatform.values
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(_socialPlatformLabel(p)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _replaceSocial(i, link.copyWith(platform: v));
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _socialCtrls[i],
                decoration: const InputDecoration(labelText: 'URL'),
                onChanged: (v) => _replaceSocial(i, link.copyWith(url: v)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _socialLabelCtrls[i],
                decoration: const InputDecoration(
                  labelText: 'Etiqueta personalizada (opcional)',
                  hintText: 'Ej: Mi LinkedIn, Portafolio…',
                ),
                onChanged: (v) => _replaceSocial(
                  i,
                  link.copyWith(
                    customLabel: v.trim().isEmpty ? null : v.trim(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Switch.adaptive(
                    value: link.isVisible,
                    onChanged: (v) =>
                        _replaceSocial(i, link.copyWith(isVisible: v)),
                    activeTrackColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    link.isVisible
                        ? 'Visible en la tarjeta'
                        : 'Oculta en la tarjeta',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: link.isVisible
                          ? context.textPrimary
                          : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _addContact() {
    final item = ContactItemModel(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      type: ContactType.phone,
      value: '',
    );
    setState(() {
      _contactCtrls.add(TextEditingController());
      _contactLabelCtrls.add(TextEditingController());
      _card = _card.copyWith(contactItems: [..._card.contactItems, item]);
    });
  }

  void _removeContact(int index) {
    setState(() {
      _contactCtrls[index].dispose();
      _contactCtrls.removeAt(index);
      _contactLabelCtrls[index].dispose();
      _contactLabelCtrls.removeAt(index);
      final updated = [..._card.contactItems]..removeAt(index);
      _card = _card.copyWith(contactItems: updated);
    });
  }

  void _replaceContact(int index, ContactItemModel item) {
    setState(() {
      final updated = [..._card.contactItems];
      updated[index] = item;
      _card = _card.copyWith(contactItems: updated);
    });
  }

  void _addSocial() {
    final link = SocialLinkModel(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      platform: SocialPlatform.linkedin,
      url: '',
    );
    setState(() {
      _socialCtrls.add(TextEditingController());
      _socialLabelCtrls.add(TextEditingController());
      _card = _card.copyWith(socialLinks: [..._card.socialLinks, link]);
    });
  }

  void _removeSocial(int index) {
    setState(() {
      _socialCtrls[index].dispose();
      _socialCtrls.removeAt(index);
      _socialLabelCtrls[index].dispose();
      _socialLabelCtrls.removeAt(index);
      final updated = [..._card.socialLinks]..removeAt(index);
      _card = _card.copyWith(socialLinks: updated);
    });
  }

  void _replaceSocial(int index, SocialLinkModel item) {
    setState(() {
      final updated = [..._card.socialLinks];
      updated[index] = item;
      _card = _card.copyWith(socialLinks: updated);
    });
  }

  String _contactTypeLabel(ContactType type) => switch (type) {
    ContactType.phone => 'Teléfono',
    ContactType.whatsapp => 'WhatsApp',
    ContactType.email => 'Email',
    ContactType.address => 'Dirección',
    ContactType.website => 'Sitio web',
  };

  String _socialPlatformLabel(SocialPlatform platform) => switch (platform) {
    SocialPlatform.linkedin => 'LinkedIn',
    SocialPlatform.instagram => 'Instagram',
    SocialPlatform.facebook => 'Facebook',
    SocialPlatform.tiktok => 'TikTok',
    SocialPlatform.twitter => 'X / Twitter',
    SocialPlatform.youtube => 'YouTube',
    SocialPlatform.calendly => 'Calendly',
    SocialPlatform.github => 'GitHub',
    SocialPlatform.custom => 'Enlace',
  };
}

class _AdminEditStepData {
  final String label;
  final IconData icon;

  const _AdminEditStepData(this.label, this.icon);
}

class _AdminEditEmptyState extends StatelessWidget {
  final String message;
  final String hint;

  const _AdminEditEmptyState({required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: context.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminStepNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _AdminStepNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.08)
                : context.bgPage,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : context.borderColor,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.primary : context.textMuted,
          ),
        ),
      ),
    );
  }
}

class _AdminHorizontalStepSelector extends StatelessWidget {
  final List<_AdminEditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AdminHorizontalStepSelector({
    required this.steps,
    required this.completedSteps,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final active = index == currentIndex;
          final completed = completedSteps[index];
          return InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : context.bgCard,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? AppColors.primary : context.borderColor,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : context.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    steps[index].label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? AppColors.primary : context.textSecondary,
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdminVerticalStepRail extends StatelessWidget {
  final List<_AdminEditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AdminVerticalStepRail({
    required this.steps,
    required this.completedSteps,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      itemCount: steps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        final active = index == currentIndex;
        final completed = completedSteps[index];
        return InkWell(
          onTap: () => onTap(index),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : context.bgCard,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? AppColors.primary : context.borderColor,
                    ),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[index].label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? AppColors.primary : context.textSecondary,
                    ),
                  ),
                ),
                if (completed)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: AppColors.success,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminBottomStepNav extends StatelessWidget {
  final int currentIndex;
  final int totalSteps;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSave;

  const _AdminBottomStepNav({
    required this.currentIndex,
    required this.totalSteps,
    required this.onPrev,
    required this.onNext,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex < totalSteps - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: TapLoopButton(
                label: 'Paso anterior',
                onPressed: hasPrev ? onPrev : null,
                variant: TapLoopButtonVariant.outline,
                height: 44,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TapLoopButton(
                label: hasNext ? 'Siguiente paso' : 'Guardar cambios',
                onPressed: hasNext ? onNext : onSave,
                height: 44,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPreviewPanel extends StatelessWidget {
  final DigitalCardModel card;

  const _AdminPreviewPanel({required this.card});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VISTA PREVIA',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'liomont.taploop.com.mx/${card.publicSlug}',
            style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
          ),
          const SizedBox(height: 24),
          Center(child: DigitalProfilePreview(card: card, width: 240)),
        ],
      ),
    );
  }
}

List<int> _sumAdminSeries(List<List<int>> all) {
  final result = List.filled(7, 0);
  for (final series in all) {
    for (var i = 0; i < 7 && i < series.length; i++) {
      result[i] += series[i];
    }
  }
  return result;
}

String _adminDayLabel(int index) {
  const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  return labels[index % labels.length];
}

// ─── Admin Form Row ───────────────────────────────────────────────────────────

class _AdminFormRow extends StatefulWidget {
  final _AdminSmartForm form;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChanged;

  const _AdminFormRow({
    required this.form,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  State<_AdminFormRow> createState() => _AdminFormRowState();
}

class _AdminFormRowState extends State<_AdminFormRow> {
  bool _fieldsOpen = false;
  int? _editingIdx;
  final _addCtrl = TextEditingController();
  _AdminFieldType _addType = _AdminFieldType.text;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: form.enabled
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : context.bgSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  form.icon,
                  size: 18,
                  color: form.enabled ? AppColors.primary : context.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form.title,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: form.enabled
                            ? context.textPrimary
                            : context.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      form.description,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    if (form.enabled) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          _fieldsOpen = !_fieldsOpen;
                          if (!_fieldsOpen) _editingIdx = null;
                        }),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedRotation(
                              turns: _fieldsOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 15,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _fieldsOpen
                                  ? 'Ocultar campos'
                                  : 'Personalizar campos (${form.fields.length})',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: form.enabled,
                onChanged: (v) {
                  widget.onToggle(v);
                  if (!v) setState(() => _fieldsOpen = false);
                },
                activeTrackColor: AppColors.primary,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _fieldsOpen
              ? Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.bgSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Campos del formulario',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${form.fields.where((f) => f.required).length} obligatorios',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: context.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        onReorder: (oldIdx, newIdx) {
                          setState(() {
                            if (newIdx > oldIdx) newIdx--;
                            final item = form.fields.removeAt(oldIdx);
                            form.fields.insert(newIdx, item);
                            if (_editingIdx != null) {
                              if (_editingIdx == oldIdx) {
                                _editingIdx = newIdx;
                              } else if (oldIdx < _editingIdx! &&
                                  newIdx >= _editingIdx!) {
                                _editingIdx = _editingIdx! - 1;
                              } else if (oldIdx > _editingIdx! &&
                                  newIdx <= _editingIdx!) {
                                _editingIdx = _editingIdx! + 1;
                              }
                            }
                          });
                          widget.onChanged();
                        },
                        children: form.fields.asMap().entries.map((e) {
                          final idx = e.key;
                          final field = e.value;
                          final isEditing = _editingIdx == idx;
                          return Column(
                            key: ValueKey('af_${form.id}_$idx'),
                            children: [
                              GestureDetector(
                                onTap: () => setState(
                                  () => _editingIdx = isEditing ? null : idx,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: idx,
                                        child: Icon(
                                          Icons.drag_indicator,
                                          size: 15,
                                          color: context.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: field.type.color.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              field.type.icon,
                                              size: 10,
                                              color: field.type.color,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              field.type.label,
                                              style: GoogleFonts.dmSans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: field.type.color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          field.label,
                                          style: GoogleFonts.dmSans(
                                            fontSize: 12,
                                            color: context.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (field.required)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Req',
                                            style: GoogleFonts.dmSans(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ),
                                      AnimatedRotation(
                                        turns: isEditing ? 0.5 : 0,
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: Icon(
                                          Icons.expand_more_rounded,
                                          size: 14,
                                          color: context.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            form.fields.removeAt(idx);
                                            if (_editingIdx == idx) {
                                              _editingIdx = null;
                                            } else if (_editingIdx != null &&
                                                _editingIdx! > idx) {
                                              _editingIdx = _editingIdx! - 1;
                                            }
                                          });
                                          widget.onChanged();
                                        },
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: context.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeInOut,
                                child: isEditing
                                    ? Container(
                                        margin: const EdgeInsets.only(
                                          left: 20,
                                          bottom: 4,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: context.bgCard,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: context.borderColor,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tipo de campo',
                                              style: GoogleFonts.dmSans(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: context.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: _AdminFieldType.values.map((
                                                t,
                                              ) {
                                                final sel = field.type == t;
                                                return GestureDetector(
                                                  onTap: () => setState(
                                                    () => field.type = t,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: sel
                                                          ? t.color.withValues(
                                                              alpha: 0.15,
                                                            )
                                                          : context.bgSubtle,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: sel
                                                            ? t.color
                                                            : context
                                                                  .borderColor,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          t.icon,
                                                          size: 11,
                                                          color: sel
                                                              ? t.color
                                                              : context
                                                                    .textMuted,
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Text(
                                                          t.label,
                                                          style: GoogleFonts.dmSans(
                                                            fontSize: 10,
                                                            fontWeight: sel
                                                                ? FontWeight
                                                                      .w700
                                                                : FontWeight
                                                                      .w400,
                                                            color: sel
                                                                ? t.color
                                                                : context
                                                                      .textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                            const SizedBox(height: 8),
                                            GestureDetector(
                                              onTap: () => setState(
                                                () => field.required =
                                                    !field.required,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    field.required
                                                        ? Icons
                                                              .check_box_rounded
                                                        : Icons
                                                              .check_box_outline_blank_rounded,
                                                    size: 15,
                                                    color: field.required
                                                        ? AppColors.primary
                                                        : context.textMuted,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Campo obligatorio',
                                                    style: GoogleFonts.dmSans(
                                                      fontSize: 12,
                                                      color:
                                                          context.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      Divider(color: context.borderColor, height: 16),
                      Text(
                        'Agregar campo',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: _AdminFieldType.values.map((t) {
                          final sel = _addType == t;
                          return GestureDetector(
                            onTap: () => setState(() => _addType = t),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: sel
                                    ? t.color.withValues(alpha: 0.15)
                                    : context.bgCard,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: sel ? t.color : context.borderColor,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    t.icon,
                                    size: 11,
                                    color: sel ? t.color : context.textMuted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    t.label,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 10,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: sel
                                          ? t.color
                                          : context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addCtrl,
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: context.textPrimary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Nombre del campo...',
                                hintStyle: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: context.textMuted,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: context.borderColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: context.borderColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: context.bgCard,
                              ),
                              onSubmitted: (v) {
                                final val = v.trim();
                                if (val.isNotEmpty) {
                                  setState(() {
                                    form.fields.add(
                                      _AdminFormField(
                                        label: val,
                                        type: _addType,
                                      ),
                                    );
                                    _addCtrl.clear();
                                  });
                                  widget.onChanged();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final val = _addCtrl.text.trim();
                              if (val.isNotEmpty) {
                                setState(() {
                                  form.fields.add(
                                    _AdminFormField(label: val, type: _addType),
                                  );
                                  _addCtrl.clear();
                                });
                                widget.onChanged();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
