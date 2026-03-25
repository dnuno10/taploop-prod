// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../core/widgets/taploop_button.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/digital_card_model.dart';
import '../models/social_link_model.dart';
import '../models/contact_item_model.dart';
import '../models/smart_form_model.dart';
import '../utils/calendar_links.dart';
import '../widgets/digital_profile_preview.dart';

class EditCardView extends StatefulWidget {
  const EditCardView({super.key});

  @override
  State<EditCardView> createState() => _EditCardViewState();
}

class _EditCardViewState extends State<EditCardView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late DigitalCardModel _card;
  int _stepIndex = 0;
  bool _hasCompletedForm = false;

  static const _steps = <_EditStepData>[
    _EditStepData('Perfil', Icons.person_outline_rounded),
    _EditStepData('Contacto', Icons.call_outlined),
    _EditStepData('Redes', Icons.language_rounded),
    _EditStepData('Diseño', Icons.palette_outlined),
    _EditStepData('Formularios', Icons.assignment_outlined),
    _EditStepData('Calendario', Icons.event_outlined),
  ];

  late TextEditingController _nameCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _companyCtrl;
  late TextEditingController _bioCtrl;

  bool _unsaved = false;
  bool _saving = false;
  bool _suppressTextSync = false;
  String? _organizationName;
  bool _syncingOrganizationCompany = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _tab.addListener(_syncStepWithTab);
    appState.addListener(_onAppStateChanged);
    _card =
        appState.currentCard ??
        DigitalCardModel(
          id: '',
          userId: '',
          name: '',
          jobTitle: '',
          company: '',
          contactItems: const [],
          socialLinks: const [],
          publicSlug: '',
        );
    _nameCtrl = TextEditingController(text: _card.name);
    _titleCtrl = TextEditingController(text: _card.jobTitle);
    _companyCtrl = TextEditingController(text: _card.company);
    _bioCtrl = TextEditingController(text: _card.bio ?? '');
    for (final ctrl in [_nameCtrl, _titleCtrl, _companyCtrl, _bioCtrl]) {
      ctrl.addListener(_onTextChanged);
    }
    _loadOrganizationName();
    _loadFormCompletion();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _tab.removeListener(_syncStepWithTab);
    _tab.dispose();
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final card = appState.currentCard;
    if (card != null &&
        (card.id != _card.id ||
            card.companyLogoUrl != _card.companyLogoUrl ||
            card.profilePhotoUrl != _card.profilePhotoUrl ||
            card.name != _card.name ||
            card.jobTitle != _card.jobTitle ||
            card.company != _card.company ||
            card.bio != _card.bio)) {
      _applyCard(card);
    }
    _loadOrganizationName();
    _loadFormCompletion();
  }

  void _applyCard(DigitalCardModel card) {
    _syncControllers(
      name: card.name,
      title: card.jobTitle,
      company: _organizationName ?? card.company,
      bio: card.bio ?? '',
    );
    if (!mounted) return;
    setState(() {
      _card = card.copyWith(company: _organizationName ?? card.company);
    });
    _loadFormCompletion();
  }

  void _onTextChanged() {
    if (_suppressTextSync) return;
    setState(() {
      _card = _card.copyWith(
        name: _nameCtrl.text,
        jobTitle: _titleCtrl.text,
        company: _companyCtrl.text,
        bio: _bioCtrl.text,
      );
      _unsaved = true;
    });
  }

  Future<void> _loadOrganizationName() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) {
      if (!mounted) return;
      setState(() => _organizationName = null);
      return;
    }

    try {
      final rows = await SupabaseService.client
          .from('organizations')
          .select('name')
          .eq('id', orgId)
          .limit(1);
      final orgName = (rows as List).isNotEmpty
          ? (rows.first['name'] as String?)?.trim()
          : null;
      if (!mounted || orgName == null || orgName.isEmpty) return;

      final shouldPersistCompany =
          _card.id.isNotEmpty && _card.company.trim() != orgName;
      final previousUnsaved = _unsaved;
      _syncControllers(company: orgName);
      setState(() {
        _organizationName = orgName;
        _card = _card.copyWith(company: orgName);
        _unsaved = previousUnsaved;
      });
      if (shouldPersistCompany) {
        await _persistOrganizationCompanyIfNeeded(orgId, orgName);
      }
    } catch (_) {}
  }

  Future<void> _persistOrganizationCompanyIfNeeded(
    String orgId,
    String orgName,
  ) async {
    if (_syncingOrganizationCompany || _card.id.isEmpty) return;

    _syncingOrganizationCompany = true;
    try {
      await CardRepository.syncCardOrganizationCompany(
        cardId: _card.id,
        company: orgName,
        orgId: orgId,
      );
      if (!mounted) return;
      final updatedCard = _card.copyWith(company: orgName, orgId: orgId);
      appState.updateCard(updatedCard);
      setState(() => _card = updatedCard);
    } catch (_) {
    } finally {
      _syncingOrganizationCompany = false;
    }
  }

  void _syncControllers({
    String? name,
    String? title,
    String? company,
    String? bio,
  }) {
    _suppressTextSync = true;
    if (name != null) _nameCtrl.text = name;
    if (title != null) _titleCtrl.text = title;
    if (company != null) _companyCtrl.text = company;
    if (bio != null) _bioCtrl.text = bio;
    _suppressTextSync = false;
  }

  Future<void> _loadFormCompletion() async {
    final cardId = _card.id;
    if (cardId.isEmpty) {
      if (!mounted || !_hasCompletedForm) return;
      setState(() => _hasCompletedForm = false);
      return;
    }

    try {
      final forms = await CardRepository.fetchSmartForms(cardId);
      final hasCompletedForm = forms.any(
        (form) => form.isActive && form.fields.isNotEmpty,
      );
      if (!mounted || _hasCompletedForm == hasCompletedForm) return;
      setState(() => _hasCompletedForm = hasCompletedForm);
    } catch (_) {}
  }

  void _syncStepWithTab() {
    if (!_tab.indexIsChanging && _stepIndex != _tab.index) {
      setState(() => _stepIndex = _tab.index);
    }
  }

  void _goToStep(int index) {
    if (index < 0 || index >= _steps.length) return;
    setState(() => _stepIndex = index);
    _tab.animateTo(index);
  }

  void _nextStep() {
    if (_stepIndex >= _steps.length - 1) return;
    _goToStep(_stepIndex + 1);
  }

  void _prevStep() {
    if (_stepIndex <= 0) return;
    _goToStep(_stepIndex - 1);
  }

  List<bool> _stepCompletion() {
    final hasVisibleContact = _card.contactItems.any(
      (item) => item.isVisible && item.value.trim().isNotEmpty,
    );
    final hasVisibleSocial = _card.socialLinks.any(
      (link) => link.isVisible && link.url.trim().isNotEmpty,
    );
    final hasCalendar =
        _card.calendarEnabled && (_card.calendarUrl?.trim().isNotEmpty == true);

    return [
      _nameCtrl.text.trim().isNotEmpty &&
          _titleCtrl.text.trim().isNotEmpty &&
          _companyCtrl.text.trim().isNotEmpty &&
          _bioCtrl.text.trim().isNotEmpty,
      hasVisibleContact,
      hasVisibleSocial,
      true,
      _hasCompletedForm,
      hasCalendar,
    ];
  }

  Future<void> _onSave() async {
    if (_saving) return;
    if (_card.id.isEmpty) {
      TapLoopToast.show(
        context,
        'No hay tarjeta activa. Recarga la página.',
        TapLoopToastType.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await CardRepository.saveCard(_card);
      appState.updateCard(_card);
      if (mounted) {
        setState(() {
          _saving = false;
          _unsaved = false;
        });
        TapLoopToast.show(
          context,
          'Cambios guardados correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        TapLoopToast.show(
          context,
          'No se pudieron guardar los cambios. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  void _showAddContact() {
    void onAdd(ContactItemModel item) => _persistNewContact(item);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: ctx.bgCard,
          child: SizedBox(
            width: 480,
            child: _AddContactSheet(onSubmit: onAdd, isDialog: true),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddContactSheet(onSubmit: onAdd),
      );
    }
  }

  void _showEditContact(ContactItemModel item) {
    void onSave(ContactItemModel updated) => _persistEditedContact(updated);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: ctx.bgCard,
          child: SizedBox(
            width: 480,
            child: _AddContactSheet(
              onSubmit: onSave,
              isDialog: true,
              initialItem: item,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddContactSheet(onSubmit: onSave, initialItem: item),
      );
    }
  }

  Future<void> _persistNewContact(ContactItemModel item) async {
    try {
      final saved = await CardRepository.addContactItem(_card.id, item);
      if (mounted) {
        setState(
          () => _card = _card.copyWith(
            contactItems: [..._card.contactItems, saved],
          ),
        );
        TapLoopToast.show(
          context,
          'Contacto añadido correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo añadir el contacto. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _persistEditedContact(ContactItemModel updatedItem) async {
    try {
      await CardRepository.updateContactItem(updatedItem);
      if (mounted) {
        setState(
          () => _card = _card.copyWith(
            contactItems: _card.contactItems
                .map((c) => c.id == updatedItem.id ? updatedItem : c)
                .toList(),
          ),
        );
        TapLoopToast.show(
          context,
          'Contacto actualizado correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar el contacto. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  void _showAddSocial() {
    void onAdd(SocialLinkModel link) => _persistNewSocial(link);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: ctx.bgCard,
          child: SizedBox(
            width: 480,
            child: _AddSocialSheet(onSubmit: onAdd, isDialog: true),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddSocialSheet(onSubmit: onAdd),
      );
    }
  }

  void _showEditSocial(SocialLinkModel link) {
    void onSave(SocialLinkModel updated) => _persistEditedSocial(updated);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: ctx.bgCard,
          child: SizedBox(
            width: 480,
            child: _AddSocialSheet(
              onSubmit: onSave,
              isDialog: true,
              initialLink: link,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddSocialSheet(onSubmit: onSave, initialLink: link),
      );
    }
  }

  Future<void> _persistNewSocial(SocialLinkModel link) async {
    try {
      final saved = await CardRepository.addSocialLink(_card.id, link);
      if (mounted) {
        setState(
          () => _card = _card.copyWith(
            socialLinks: [..._card.socialLinks, saved],
          ),
        );
        TapLoopToast.show(
          context,
          'Red social añadida correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo añadir la red social. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _persistEditedSocial(SocialLinkModel updatedLink) async {
    try {
      await CardRepository.updateSocialLink(updatedLink);
      if (mounted) {
        setState(
          () => _card = _card.copyWith(
            socialLinks: _card.socialLinks
                .map((s) => s.id == updatedLink.id ? updatedLink : s)
                .toList(),
          ),
        );
        TapLoopToast.show(
          context,
          'Red social actualizada correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar la red social. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _handleContactsChanged(DigitalCardModel updated) async {
    final oldItems = _card.contactItems;
    final newItems = updated.contactItems
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    if (mounted) {
      setState(() => _card = updated.copyWith(contactItems: newItems));
    }
    try {
      for (final old in oldItems) {
        if (!newItems.any((i) => i.id == old.id)) {
          await CardRepository.deleteContactItem(old.id);
        }
      }
      for (final item in newItems) {
        final old = oldItems.firstWhere(
          (i) => i.id == item.id,
          orElse: () => item,
        );
        if (old.type != item.type ||
            old.value != item.value ||
            old.label != item.label ||
            old.isVisible != item.isVisible ||
            old.sortOrder != item.sortOrder) {
          await CardRepository.updateContactItem(item);
        }
      }
      await CardRepository.reorderContactItems(newItems);
      if (mounted && newItems.length < oldItems.length) {
        TapLoopToast.show(
          context,
          'Contacto eliminado.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _card = _card.copyWith(contactItems: oldItems));
        TapLoopToast.show(
          context,
          'No se pudieron actualizar los contactos. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _handleSocialsChanged(DigitalCardModel updated) async {
    final oldLinks = _card.socialLinks;
    final newLinks = updated.socialLinks
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    if (mounted) {
      setState(() => _card = updated.copyWith(socialLinks: newLinks));
    }
    try {
      for (final old in oldLinks) {
        if (!newLinks.any((i) => i.id == old.id)) {
          await CardRepository.deleteSocialLink(old.id);
        }
      }
      for (final link in newLinks) {
        final old = oldLinks.firstWhere(
          (i) => i.id == link.id,
          orElse: () => link,
        );
        if (old.platform != link.platform ||
            old.url != link.url ||
            old.customLabel != link.customLabel ||
            old.isVisible != link.isVisible ||
            old.sortOrder != link.sortOrder) {
          await CardRepository.updateSocialLink(link);
        }
      }
      await CardRepository.reorderSocialLinks(newLinks);
      if (mounted && newLinks.length < oldLinks.length) {
        TapLoopToast.show(
          context,
          'Red social eliminada.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _card = _card.copyWith(socialLinks: oldLinks));
        TapLoopToast.show(
          context,
          'No se pudieron actualizar las redes sociales. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final stepProgress = (_stepIndex + 1) / _steps.length;
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
                      maxWidth: isDesktop ? 460 : double.infinity,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Tarjeta',
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
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
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Edita tu perfil, contacto, diseño y flujos de captura desde un mismo espacio.',
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
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: context.bgCard,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            'Paso ${_stepIndex + 1} de ${_steps.length}: ${_steps[_stepIndex].label}',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        _StepNavButton(
                          icon: Icons.arrow_back_rounded,
                          enabled: _stepIndex > 0,
                          onTap: _prevStep,
                        ),
                        _StepNavButton(
                          icon: Icons.arrow_forward_rounded,
                          enabled: _stepIndex < _steps.length - 1,
                          onTap: _nextStep,
                        ),
                        _SaveButton(
                          unsaved: _unsaved,
                          saving: _saving,
                          onSave: _onSave,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      minHeight: 4,
                      value: stepProgress,
                      color: AppColors.primary,
                      backgroundColor: context.bgSubtle,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: hasLinkedCard
                  ? (isDesktop ? _desktopLayout() : _mobileLayout())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      child: CardInitialSetupState(
                        onLinked: () => _applyCard(appState.currentCard!),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileLayout() {
    final stepCompletion = _stepCompletion();
    return Container(
      color: context.bgPage,
      child: Column(
        children: [
          Container(
            color: context.bgPage,
            child: _HorizontalStepSelector(
              steps: _steps,
              completedSteps: stepCompletion,
              currentIndex: _stepIndex,
              onTap: _goToStep,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(color: context.borderColor),
                ),
                clipBehavior: Clip.hardEdge,
                child: TabBarView(
                  controller: _tab,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _tabChildren(),
                ),
              ),
            ),
          ),
          _BottomStepNav(
            currentIndex: _stepIndex,
            totalSteps: _steps.length,
            onPrev: _prevStep,
            onNext: _nextStep,
          ),
        ],
      ),
    );
  }

  Widget _desktopLayout() {
    final stepCompletion = _stepCompletion();
    return Container(
      color: context.bgPage,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 228,
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: context.borderColor),
              ),
              child: _VerticalStepRail(
                steps: _steps,
                completedSteps: stepCompletion,
                currentIndex: _stepIndex,
                onTap: _goToStep,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: context.borderColor),
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: [
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _tabChildren(),
                      ),
                    ),
                    _BottomStepNav(
                      currentIndex: _stepIndex,
                      totalSteps: _steps.length,
                      onPrev: _prevStep,
                      onNext: _nextStep,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(width: 320, child: _LivePreviewPanel(card: _card)),
          ],
        ),
      ),
    );
  }

  List<Widget> _tabChildren() => [
    _ProfileTab(
      nameCtrl: _nameCtrl,
      titleCtrl: _titleCtrl,
      companyCtrl: _companyCtrl,
      bioCtrl: _bioCtrl,
      card: _card,
      companyLocked: _organizationName != null,
      onPhotoChanged: (url) => setState(() {
        _card = _card.copyWith(profilePhotoUrl: url);
        _unsaved = true;
      }),
    ),
    _ContactTab(
      card: _card,
      onChanged: (c) => _handleContactsChanged(c),
      onAdd: _showAddContact,
      onEdit: _showEditContact,
    ),
    _SocialTab(
      card: _card,
      onChanged: (c) => _handleSocialsChanged(c),
      onAdd: _showAddSocial,
      onEdit: _showEditSocial,
    ),
    _DesignTab(
      card: _card,
      onChanged: (c) => setState(() {
        _card = c;
        _unsaved = true;
      }),
    ),
    _FormulariosTab(
      cardId: _card.id,
      onCompletionChanged: (hasCompletedForm) {
        if (_hasCompletedForm == hasCompletedForm) return;
        setState(() => _hasCompletedForm = hasCompletedForm);
      },
    ),
    _CalendarioTab(
      calendarEnabled: _card.calendarEnabled,
      calendarUrl: _card.calendarUrl,
      onChanged: (enabled, url) => setState(() {
        _card = _card.copyWith(
          calendarEnabled: enabled,
          calendarUrl: url.isEmpty ? null : url,
        );
        _unsaved = true;
      }),
    ),
  ];
}

class _EditStepData {
  final String label;
  final IconData icon;
  const _EditStepData(this.label, this.icon);
}

class _StepNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepNavButton({
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
            color: context.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? AppColors.primary : context.borderColor,
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

class _HorizontalStepSelector extends StatelessWidget {
  final List<_EditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _HorizontalStepSelector({
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
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final step = steps[i];
          final completed = completedSteps[i];
          final active = i == currentIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? AppColors.primary : context.borderColor,
                      ),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? AppColors.primary
                            : context.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    step.label,
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

class _VerticalStepRail extends StatelessWidget {
  final List<_EditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _VerticalStepRail({
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
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final step = steps[i];
        final completed = completedSteps[i];
        final active = i == currentIndex;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? AppColors.primary : context.borderColor,
                    ),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.primary : context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: active
                                ? AppColors.primary
                                : context.textSecondary,
                          ),
                        ),
                      ),
                      if (completed) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppColors.success,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomStepNav extends StatelessWidget {
  final int currentIndex;
  final int totalSteps;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _BottomStepNav({
    required this.currentIndex,
    required this.totalSteps,
    required this.onPrev,
    required this.onNext,
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
                label: hasNext ? 'Siguiente paso' : 'Ultimo paso',
                onPressed: hasNext ? onNext : null,
                height: 44,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab selector ─────────────────────────────────────────────────────────────

// ─── Live Preview (desktop) ───────────────────────────────────────────────────

class _LivePreviewPanel extends StatelessWidget {
  final DigitalCardModel card;
  const _LivePreviewPanel({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.borderColor),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vista previa',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF181411),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Así se verá tu perfil público en TapLoop.',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.borderColor),
              ),
              child: Text(
                'liomont.taploop.com.mx/${card.publicSlug}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(child: DigitalProfilePreview(card: card, width: 240)),
            const SizedBox(height: 24),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 16),
            Text(
              card.name.isEmpty ? 'Nombre' : card.name,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: card.name.isEmpty
                    ? context.textMuted
                    : context.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              card.jobTitle.isEmpty
                  ? 'Cargo · Empresa'
                  : '${card.jobTitle} · ${card.company}',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
            if (card.bio?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                card.bio!,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Profile Tab ─────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController titleCtrl;
  final TextEditingController companyCtrl;
  final TextEditingController bioCtrl;
  final DigitalCardModel card;
  final bool companyLocked;
  final ValueChanged<String> onPhotoChanged;

  const _ProfileTab({
    required this.nameCtrl,
    required this.titleCtrl,
    required this.companyCtrl,
    required this.bioCtrl,
    required this.card,
    required this.companyLocked,
    required this.onPhotoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarPicker(card: card, onPhotoChanged: onPhotoChanged),
              const SizedBox(height: 32),
              Divider(color: context.borderColor, height: 1),
              const SizedBox(height: 28),
              Text(
                'Información personal',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _EditInputField(
                label: 'Nombre completo',
                controller: nameCtrl,
                hint: 'Ej: Juan García',
              ),
              const SizedBox(height: 18),
              _EditInputField(
                label: 'Cargo / Rol',
                controller: titleCtrl,
                hint: 'Ej: Software Engineer',
              ),
              const SizedBox(height: 18),
              _EditInputField(
                label: 'Empresa',
                controller: companyCtrl,
                hint: 'Ej: TapLoop Inc.',
                enabled: !companyLocked,
              ),
              if (companyLocked) ...[
                const SizedBox(height: 8),
                Text(
                  'Este campo se completa automaticamente segun la organizacion del usuario y no puede modificarse.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Divider(color: context.borderColor, height: 1),
              const SizedBox(height: 28),
              Text(
                'Sobre ti',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Una breve presentación que verán las personas que abran tu tarjeta.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _EditInputField(
                label: 'Biografía',
                controller: bioCtrl,
                hint: 'Especialista en...',
                maxLines: 4,
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatefulWidget {
  final DigitalCardModel card;
  final ValueChanged<String> onPhotoChanged;
  const _AvatarPicker({required this.card, required this.onPhotoChanged});

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  bool _uploading = false;

  String _initials() {
    final name = widget.card.name.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  Future<void> _pickAndUpload() async {
    if (!kIsWeb) return;
    final input = html.FileUploadInputElement()
      ..accept = 'image/jpeg,image/png';
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;

    // Validar tipo de archivo
    const tiposPermitidos = ['image/jpeg', 'image/png'];
    if (!tiposPermitidos.contains(file.type)) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'Solo se permiten imágenes en formato JPG o PNG.',
          TapLoopToastType.error,
        );
      }
      return;
    }

    // Validar tamaño
    if (file.size > 5 * 1024 * 1024) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'La imagen supera el límite de 5 MB.',
          TapLoopToastType.error,
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

      final userId = widget.card.userId ?? 'unknown';
      final cardId = widget.card.id;
      final ext = file.type == 'image/png' ? 'png' : 'jpg';
      final path = '$userId/$cardId/profile.$ext';

      await SupabaseService.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: file.type),
          );

      final rawUrl = SupabaseService.client.storage
          .from('avatars')
          .getPublicUrl(path);
      final url = '$rawUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      widget.onPhotoChanged(url);
      if (mounted) {
        TapLoopToast.show(
          context,
          'Foto de perfil actualizada.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo subir la imagen. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.card.profilePhotoUrl;
    return Row(
      children: [
        GestureDetector(
          onTap: _uploading ? null : _pickAndUpload,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary,
                backgroundImage: photoUrl != null
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null
                    ? Text(
                        _initials(),
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: context.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: _uploading
                      ? const Padding(
                          padding: EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera,
                          size: 14,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _uploading ? null : _pickAndUpload,
              child: Text(
                'Cambiar foto',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'JPG, PNG · máx 5 MB',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Contact Tab ─────────────────────────────────────────────────────────────

class _ContactTab extends StatefulWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;
  final VoidCallback onAdd;
  final ValueChanged<ContactItemModel> onEdit;
  const _ContactTab({
    required this.card,
    required this.onChanged,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_ContactTab> createState() => _ContactTabState();
}

class _ContactTabState extends State<_ContactTab> {
  void _onReorder(int oldIndex, int newIndex) {
    final items = [...widget.card.contactItems];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final normalized = items
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    widget.onChanged(widget.card.copyWith(contactItems: normalized));
  }

  @override
  Widget build(BuildContext context) {
    final contacts = [...widget.card.contactItems]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                          'Contacto',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${contacts.where((c) => c.isVisible).length} de ${contacts.length} visibles',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TapLoopButton(
                    label: 'Añadir',
                    width: 120,
                    height: 38,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: widget.onAdd,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (contacts.isEmpty)
                _EmptyState(
                  message: 'Sin información de contacto',
                  hint: 'Añade tu teléfono, email u otros datos.',
                )
              else ...[
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: contacts.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, i) {
                    final item = contacts[i];
                    return _ContactRow(
                      key: ValueKey('contact_${item.id}'),
                      index: i,
                      item: item,
                      onEdit: () => widget.onEdit(item),
                      onToggle: (val) {
                        final updated = contacts
                            .map(
                              (c) => c.id == item.id
                                  ? c.copyWith(isVisible: val)
                                  : c,
                            )
                            .toList();
                        widget.onChanged(
                          widget.card.copyWith(contactItems: updated),
                        );
                      },
                      onDelete: () {
                        final updated = contacts
                            .where((c) => c.id != item.id)
                            .toList();
                        widget.onChanged(
                          widget.card.copyWith(contactItems: updated),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Arrastra para ordenar (el primero se mostrará primero).',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final int index;
  final ContactItemModel item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ContactRow({
    super.key,
    required this.index,
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.borderColor),
            ),
            child: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_indicator_rounded,
                color: context.textMuted,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayLabel,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: item.isVisible
                        ? context.textPrimary
                        : context.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: item.isVisible,
            onChanged: onToggle,
            activeTrackColor: AppColors.primary,
          ),
          IconButton(
            tooltip: 'Editar contacto',
            onPressed: onEdit,
            icon: Icon(
              Icons.edit_outlined,
              color: context.textSecondary,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Eliminar contacto',
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Social Tab ──────────────────────────────────────────────────────────────

class _SocialTab extends StatefulWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;
  final VoidCallback onAdd;
  final ValueChanged<SocialLinkModel> onEdit;
  const _SocialTab({
    required this.card,
    required this.onChanged,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_SocialTab> createState() => _SocialTabState();
}

class _SocialTabState extends State<_SocialTab> {
  void _onReorder(List<SocialLinkModel> baseItems, int oldIndex, int newIndex) {
    final items = [...baseItems];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final normalized = items
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    widget.onChanged(widget.card.copyWith(socialLinks: normalized));
  }

  @override
  Widget build(BuildContext context) {
    final socials = [...widget.card.socialLinks]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                          'Redes sociales',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${socials.where((s) => s.isVisible).length} de ${socials.length} visibles',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TapLoopButton(
                    label: 'Añadir',
                    width: 120,
                    height: 38,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: widget.onAdd,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (socials.isEmpty)
                _EmptyState(
                  message: 'Sin redes sociales',
                  hint: 'Añade LinkedIn, Instagram y más.',
                )
              else ...[
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: socials.length,
                  onReorder: (oldIndex, newIndex) =>
                      _onReorder(socials, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final link = socials[i];
                    return _SocialRow(
                      key: ValueKey('social_${link.id}'),
                      index: i,
                      link: link,
                      onEdit: () => widget.onEdit(link),
                      onDelete: () {
                        final updated = socials
                            .where((s) => s.id != link.id)
                            .toList();
                        widget.onChanged(
                          widget.card.copyWith(socialLinks: updated),
                        );
                      },
                      onToggle: (val) {
                        final updated = socials
                            .map(
                              (s) => s.id == link.id
                                  ? s.copyWith(isVisible: val)
                                  : s,
                            )
                            .toList();
                        widget.onChanged(
                          widget.card.copyWith(socialLinks: updated),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Arrastra para ordenar (la primera se mostrará primero).',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  final int index;
  final SocialLinkModel link;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SocialRow({
    super.key,
    required this.index,
    required this.link,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.borderColor),
            ),
            child: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_indicator_rounded,
                color: context.textMuted,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.label,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: link.isVisible
                        ? context.textPrimary
                        : context.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  link.url,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: link.isVisible,
            onChanged: onToggle,
            activeTrackColor: AppColors.primary,
          ),
          IconButton(
            tooltip: 'Editar red social',
            onPressed: onEdit,
            icon: Icon(
              Icons.edit_outlined,
              color: context.textSecondary,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Eliminar red',
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignTab extends StatelessWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;
  const _DesignTab({required this.card, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return Column(
      children: [
        if (!isDesktop) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: DigitalProfilePreview(card: card, width: 138)),
          ),
          Divider(color: context.borderColor, height: 1),
        ],
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estilo de tarjeta',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: CardThemeStyle.values.map((style) {
                        return _ThemeChip(
                          style: style,
                          selected: card.themeStyle == style,
                          onTap: () =>
                              onChanged(card.copyWith(themeStyle: style)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Tipo de Layout',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cambia completamente la estructura visual de tu tarjeta.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: CardLayoutStyle.values.map((layout) {
                        return _LayoutChip(
                          layout: layout,
                          selected: card.layoutStyle == layout,
                          onTap: () =>
                              onChanged(card.copyWith(layoutStyle: layout)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Color principal',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Se aplica al encabezado y detalles de tu tarjeta.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children:
                          const [
                            Color(0xFFEF6820),
                            Color(0xFF6C4FE8),
                            Color(0xFF1A73E8),
                            Color(0xFF1A8C4E),
                            Color(0xFFD93025),
                            Color(0xFF0D0D0D),
                            Color(0xFF00ACC1),
                            Color(0xFFF5A623),
                          ].map((c) {
                            return _ColorDot(
                              color: c,
                              selected: card.primaryColor == c,
                              onTap: () =>
                                  onChanged(card.copyWith(primaryColor: c)),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 14),
                    _CustomColorPanel(
                      color: card.primaryColor,
                      onChanged: (c) => onChanged(
                        card.copyWith(
                          primaryColor: c,
                          themeStyle: card.themeStyle == CardThemeStyle.custom
                              ? card.themeStyle
                              : CardThemeStyle.custom,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Fondo de tarjeta ──────────────────────────────
                    Text(
                      'Fondo de tarjeta',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Personaliza el color y estilo del fondo.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: CardBgStyle.values.map((s) {
                        return _BgStyleChip(
                          style: s,
                          selected: card.bgStyle == s,
                          onTap: () => onChanged(card.copyWith(bgStyle: s)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Color de fondo',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children:
                          const [
                            Colors.white,
                            Color(0xFFF4F4F6),
                            Color(0xFFF0F4FF),
                            Color(0xFFF0FFF4),
                            Color(0xFFFFF8F0),
                            Color(0xFF0D0D0D),
                            Color(0xFF1C1C2E),
                            Color(0xFF6C4FE8),
                          ].map((c) {
                            return _ColorDot(
                              color: c,
                              selected: card.bgColor == c,
                              onTap: () => onChanged(card.copyWith(bgColor: c)),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _CustomColorPanel(
                      color: card.bgColor ?? Colors.white,
                      onChanged: (c) => onChanged(card.copyWith(bgColor: c)),
                    ),
                    if (card.bgStyle == CardBgStyle.gradient ||
                        card.bgStyle == CardBgStyle.mesh) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Color secundario',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children:
                            const [
                              Color(0xFF6C4FE8),
                              Color(0xFF1A73E8),
                              Color(0xFF1A8C4E),
                              Color(0xFFD93025),
                              Color(0xFF0D0D0D),
                              Color(0xFF00ACC1),
                              Color(0xFFF5A623),
                              Color(0xFFEF6820),
                            ].map((c) {
                              return _ColorDot(
                                color: c,
                                selected: card.bgColorEnd == c,
                                onTap: () =>
                                    onChanged(card.copyWith(bgColorEnd: c)),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 12),
                      _CustomColorPanel(
                        color: card.bgColorEnd ?? const Color(0xFF6C4FE8),
                        onChanged: (c) =>
                            onChanged(card.copyWith(bgColorEnd: c)),
                      ),
                    ],
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BgStyleChip extends StatelessWidget {
  final CardBgStyle style;
  final bool selected;
  final VoidCallback onTap;
  const _BgStyleChip({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (style) {
      CardBgStyle.plain => 'Liso',
      CardBgStyle.gradient => 'Degradado',
      CardBgStyle.mesh => 'Malla',
      CardBgStyle.stripes => 'Rayas',
    };
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.textPrimary : context.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? context.textPrimary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? (context.isDark ? Colors.black : Colors.white)
                : context.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final CardThemeStyle style;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeChip({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (style) {
      CardThemeStyle.white => 'Blanco',
      CardThemeStyle.dark => 'Oscuro',
      CardThemeStyle.gradient => 'Degradado',
      CardThemeStyle.frosted => 'Esmerilado',
      CardThemeStyle.neon => 'Neón',
      CardThemeStyle.premium => 'Premium',
      CardThemeStyle.retro => 'Retro',
      CardThemeStyle.custom => 'Custom',
    };
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.textPrimary : context.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? context.textPrimary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? (context.isDark ? Colors.black : Colors.white)
                : context.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _LayoutChip extends StatelessWidget {
  final CardLayoutStyle layout;
  final bool selected;
  final VoidCallback onTap;
  const _LayoutChip({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (layout) {
      CardLayoutStyle.centered => Icons.person_outline,
      CardLayoutStyle.leftAligned => Icons.format_align_left,
      CardLayoutStyle.compact => Icons.view_compact,
      CardLayoutStyle.banner => Icons.view_headline,
      CardLayoutStyle.minimal => Icons.radio_button_unchecked,
    };
    final label = switch (layout) {
      CardLayoutStyle.centered => 'Clásico',
      CardLayoutStyle.leftAligned => 'Izquierda',
      CardLayoutStyle.compact => 'Compacto',
      CardLayoutStyle.banner => 'Banner',
      CardLayoutStyle.minimal => 'Minimalista',
    };
    final desc = switch (layout) {
      CardLayoutStyle.centered => 'Avatar arriba centrado',
      CardLayoutStyle.leftAligned => 'Contenido a la izquierda',
      CardLayoutStyle.compact => 'Vista condensada',
      CardLayoutStyle.banner => 'Avatar y nombre en fila',
      CardLayoutStyle.minimal => 'Sin banda de encabezado',
    };
    final fgPrimary = selected ? AppColors.primary : context.textPrimary;
    final fgSub = context.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 188,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : context.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(icon, size: 18, color: fgPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fgPrimary,
                    ),
                  ),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontSize: 10, color: fgSub),
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

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: context.textPrimary, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

class _CustomColorPanel extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _CustomColorPanel({required this.color, required this.onChanged});

  @override
  State<_CustomColorPanel> createState() => _CustomColorPanelState();
}

class _CustomColorPanelState extends State<_CustomColorPanel> {
  late final TextEditingController _hexCtrl;
  bool _settingFromSlider = false;

  static String _toHex(Color c) {
    final argb = c.toARGB32();
    return ((argb) & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  static Color? _parseHex(String input) {
    final clean = input.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: _toHex(widget.color));
    _hexCtrl.addListener(_onHexChanged);
  }

  @override
  void didUpdateWidget(covariant _CustomColorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_settingFromSlider && oldWidget.color != widget.color) {
      final newHex = _toHex(widget.color);
      if (_hexCtrl.text.toUpperCase() != newHex) {
        _hexCtrl.removeListener(_onHexChanged);
        _hexCtrl.text = newHex;
        _hexCtrl.addListener(_onHexChanged);
      }
    }
  }

  void _onHexChanged() {
    final parsed = _parseHex(_hexCtrl.text);
    if (parsed != null) {
      _settingFromSlider = false;
      widget.onChanged(parsed);
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final argb = widget.color.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Custom',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.borderColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Hex Input ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 32,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.bgSubtle,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  '#',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                    letterSpacing: 1.8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── RGB Sliders ──────────────────────────────────────────────
          _ColorSlider(
            label: 'R',
            value: r.toDouble(),
            activeColor: Colors.red,
            onChanged: (v) {
              _settingFromSlider = true;
              widget.onChanged(Color.fromARGB(a, v.round(), g, b));
            },
          ),
          _ColorSlider(
            label: 'G',
            value: g.toDouble(),
            activeColor: Colors.green,
            onChanged: (v) {
              _settingFromSlider = true;
              widget.onChanged(Color.fromARGB(a, r, v.round(), b));
            },
          ),
          _ColorSlider(
            label: 'B',
            value: b.toDouble(),
            activeColor: AppColors.primary,
            onChanged: (v) {
              _settingFromSlider = true;
              widget.onChanged(Color.fromARGB(a, r, g, v.round()));
            },
          ),
        ],
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color activeColor;
  final ValueChanged<double> onChanged;
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(
              context,
            ).copyWith(activeTrackColor: activeColor, thumbColor: activeColor),
            child: Slider(min: 0, max: 255, value: value, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

// ─── Save Button ──────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool unsaved;
  final bool saving;
  final Future<void> Function() onSave;
  const _SaveButton({
    required this.unsaved,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: unsaved && !saving ? () => onSave() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: saving
              ? AppColors.success.withValues(alpha: 0.1)
              : unsaved
              ? context.textPrimary
              : context.bgSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: unsaved && !saving
                ? context.textPrimary
                : context.borderColor,
          ),
        ),
        child: saving
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Guardando...',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              )
            : Text(
                unsaved ? 'Guardar' : '✓ Guardado',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: unsaved
                      ? (context.isDark ? Colors.black : Colors.white)
                      : context.textMuted,
                ),
              ),
      ),
    );
  }
}

// ─── Add Contact Sheet ────────────────────────────────────────────────────────

class _AddContactSheet extends StatefulWidget {
  final ValueChanged<ContactItemModel> onSubmit;
  final ContactItemModel? initialItem;
  final bool isDialog;
  const _AddContactSheet({
    required this.onSubmit,
    this.initialItem,
    this.isDialog = false,
  });

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  ContactType _type = ContactType.phone;
  final _valueCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  bool get _isEditing => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    if (initial != null) {
      _type = initial.type;
      _valueCtrl.text = initial.value;
      _labelCtrl.text = initial.label ?? '';
    }
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  static const _hints = {
    ContactType.phone: '+52 55 1234 5678',
    ContactType.whatsapp: '+52 55 1234 5678',
    ContactType.email: 'tu@email.com',
    ContactType.address: 'Ciudad de México, CDMX',
    ContactType.website: 'https://tuwebsite.com',
  };

  static const _labels = {
    ContactType.phone: 'Teléfono',
    ContactType.whatsapp: 'WhatsApp',
    ContactType.email: 'Email',
    ContactType.address: 'Dirección',
    ContactType.website: 'Sitio web',
  };

  static const _icons = {
    ContactType.phone: Icons.phone_outlined,
    ContactType.whatsapp: Icons.chat_outlined,
    ContactType.email: Icons.email_outlined,
    ContactType.address: Icons.location_on_outlined,
    ContactType.website: Icons.language_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final bottomPad = widget.isDialog
        ? 28.0
        : MediaQuery.of(context).viewInsets.bottom + 28;
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isDialog)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Row(
            children: [
              Text(
                _isEditing ? 'Editar contacto' : 'Añadir contacto',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              if (widget.isDialog) ...[
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: ContactType.values.map((t) {
              final active = _type == t;
              return GestureDetector(
                onTap: () => setState(() => _type = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : (context.isDark
                              ? const Color(0xFF171717)
                              : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active ? AppColors.primary : context.borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _icons[t]!,
                        size: 16,
                        color: active ? Colors.white : context.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _labels[t]!,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : context.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _EditInputField(
            label: _labels[_type]!,
            controller: _valueCtrl,
            hint: _hints[_type],
          ),
          const SizedBox(height: 14),
          _EditInputField(
            label: 'Etiqueta (opcional)',
            controller: _labelCtrl,
            hint: 'Ej: Oficina',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TapLoopButton(
              label: _isEditing ? 'Guardar cambios' : 'Añadir',
              onPressed: () {
                if (_valueCtrl.text.trim().isEmpty) return;
                final initial = widget.initialItem;
                widget.onSubmit(
                  ContactItemModel(
                    id:
                        initial?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    type: _type,
                    value: _valueCtrl.text.trim(),
                    label: _labelCtrl.text.trim().isEmpty
                        ? null
                        : _labelCtrl.text.trim(),
                    isVisible: initial?.isVisible ?? true,
                    sortOrder: initial?.sortOrder ?? 0,
                  ),
                );
                if (!widget.isDialog) Navigator.pop(context);
                if (widget.isDialog && context.mounted) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Social Sheet ─────────────────────────────────────────────────────────

class _AddSocialSheet extends StatefulWidget {
  final ValueChanged<SocialLinkModel> onSubmit;
  final SocialLinkModel? initialLink;
  final bool isDialog;
  const _AddSocialSheet({
    required this.onSubmit,
    this.initialLink,
    this.isDialog = false,
  });

  @override
  State<_AddSocialSheet> createState() => _AddSocialSheetState();
}

class _AddSocialSheetState extends State<_AddSocialSheet> {
  SocialPlatform _platform = SocialPlatform.linkedin;
  final _urlCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  bool get _isEditing => widget.initialLink != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLink;
    if (initial != null) {
      _platform = initial.platform;
      _urlCtrl.text = initial.url;
      _labelCtrl.text = initial.customLabel ?? '';
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  static const _platformLabels = {
    SocialPlatform.linkedin: 'LinkedIn',
    SocialPlatform.instagram: 'Instagram',
    SocialPlatform.facebook: 'Facebook',
    SocialPlatform.tiktok: 'TikTok',
    SocialPlatform.twitter: 'X / Twitter',
    SocialPlatform.youtube: 'YouTube',
    SocialPlatform.calendly: 'Calendly',
    SocialPlatform.github: 'GitHub',
    SocialPlatform.custom: 'Otro enlace',
  };

  static const _platformHints = {
    SocialPlatform.linkedin: 'https://linkedin.com/in/tu-usuario',
    SocialPlatform.instagram: 'https://instagram.com/tu_usuario',
    SocialPlatform.facebook: 'https://facebook.com/tu-pagina',
    SocialPlatform.tiktok: 'https://tiktok.com/@tu_usuario',
    SocialPlatform.twitter: 'https://x.com/tu_usuario',
    SocialPlatform.youtube: 'https://youtube.com/@canal',
    SocialPlatform.calendly: 'https://calendly.com/tu-nombre',
    SocialPlatform.github: 'https://github.com/tu-usuario',
    SocialPlatform.custom: 'https://tuenlace.com',
  };

  static const _platformIcons = {
    SocialPlatform.linkedin: Icons.work_outline,
    SocialPlatform.instagram: Icons.photo_camera_outlined,
    SocialPlatform.facebook: Icons.people_outlined,
    SocialPlatform.tiktok: Icons.music_note_outlined,
    SocialPlatform.twitter: Icons.tag,
    SocialPlatform.youtube: Icons.play_circle_outline,
    SocialPlatform.calendly: Icons.calendar_today_outlined,
    SocialPlatform.github: Icons.code_outlined,
    SocialPlatform.custom: Icons.link_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final bottomPad = widget.isDialog
        ? 28.0
        : MediaQuery.of(context).viewInsets.bottom + 28;
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isDialog)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Row(
            children: [
              Text(
                _isEditing ? 'Editar red social' : 'Añadir red social',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              if (widget.isDialog) ...[
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: SocialPlatform.values.map((p) {
              final active = _platform == p;
              final shortLabel = _platformLabels[p]!.split(' ').first;
              return GestureDetector(
                onTap: () => setState(() => _platform = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : (context.isDark
                              ? const Color(0xFF171717)
                              : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active ? AppColors.primary : context.borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _platformIcons[p]!,
                        size: 16,
                        color: active ? Colors.white : context.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        shortLabel,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : context.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _EditInputField(
            label: _platformLabels[_platform]!,
            controller: _urlCtrl,
            hint: _platformHints[_platform],
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 14),
          _EditInputField(
            label: 'Etiqueta (opcional)',
            controller: _labelCtrl,
            hint: 'Ej: Mi canal principal',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TapLoopButton(
              label: _isEditing ? 'Guardar cambios' : 'Añadir',
              onPressed: () {
                if (_urlCtrl.text.trim().isEmpty) return;
                final initial = widget.initialLink;
                widget.onSubmit(
                  SocialLinkModel(
                    id:
                        initial?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    platform: _platform,
                    url: _urlCtrl.text.trim(),
                    customLabel: _labelCtrl.text.trim().isEmpty
                        ? null
                        : _labelCtrl.text.trim(),
                    isVisible: initial?.isVisible ?? true,
                    sortOrder: initial?.sortOrder ?? 0,
                  ),
                );
                if (!widget.isDialog) Navigator.pop(context);
                if (widget.isDialog && context.mounted) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Formularios Tab ─────────────────────────────────────────────────────────

extension _SmartFormFieldTypeUi on SmartFormFieldType {
  String get label => switch (this) {
    SmartFormFieldType.text => 'Texto',
    SmartFormFieldType.email => 'Email',
    SmartFormFieldType.phone => 'Teléfono',
    SmartFormFieldType.textarea => 'Área de texto',
    SmartFormFieldType.number => 'Numérico',
  };
}

class _FormulariosTab extends StatefulWidget {
  final String cardId;
  final ValueChanged<bool> onCompletionChanged;
  const _FormulariosTab({
    required this.cardId,
    required this.onCompletionChanged,
  });

  @override
  State<_FormulariosTab> createState() => _FormulariosTabState();
}

class _FormulariosTabState extends State<_FormulariosTab> {
  List<SmartFormModel> _forms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForms();
  }

  Future<void> _loadForms() async {
    try {
      final forms = await CardRepository.fetchSmartForms(widget.cardId);
      final hasCompletedForm = forms.any(
        (form) => form.isActive && form.fields.isNotEmpty,
      );
      if (mounted) {
        setState(() {
          _forms = forms;
          _loading = false;
        });
      }
      widget.onCompletionChanged(hasCompletedForm);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      widget.onCompletionChanged(false);
    }
  }

  Future<void> _createForm() async {
    final nameCtrl = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Nuevo formulario',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: _corporateInputDecoration(ctx, 'Nombre del formulario'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (created == null || created.isEmpty) return;
    try {
      await CardRepository.createSmartForm(widget.cardId, created);
      await _loadForms();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Formulario creado correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo crear el formulario. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
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
                          'Formularios dinámicos',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_forms.length} formularios en base de datos',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TapLoopButton(
                    label: 'Crear formulario',
                    width: 170,
                    height: 40,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: _createForm,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_forms.isEmpty)
                _EmptyState(
                  message: 'No hay formularios creados',
                  hint: 'Crea uno para empezar a capturar leads dinámicamente.',
                )
              else
                ..._forms.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DbSmartFormCard(form: f, onChanged: _loadForms),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DbSmartFormCard extends StatefulWidget {
  final SmartFormModel form;
  final VoidCallback onChanged;

  const _DbSmartFormCard({required this.form, required this.onChanged});

  @override
  State<_DbSmartFormCard> createState() => _DbSmartFormCardState();
}

class _DbSmartFormCardState extends State<_DbSmartFormCard> {
  bool _open = false;

  Future<void> _toggleActive(bool v) async {
    await CardRepository.updateSmartForm(widget.form.copyWith(isActive: v));
    widget.onChanged();
  }

  Future<void> _renameForm() async {
    final ctrl = TextEditingController(text: widget.form.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Editar formulario'),
        content: TextField(
          controller: ctrl,
          decoration: _corporateInputDecoration(ctx, 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await CardRepository.updateSmartForm(widget.form.copyWith(name: name));
      widget.onChanged();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Formulario actualizado correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar el formulario. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _deleteForm() async {
    try {
      await CardRepository.deleteSmartForm(widget.form.id);
      widget.onChanged();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Formulario eliminado.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo eliminar el formulario. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _addField() async {
    final labelCtrl = TextEditingController();
    SmartFormFieldType type = SmartFormFieldType.text;
    bool required = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: ctx.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Nuevo campo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: _corporateInputDecoration(ctx, 'Label del campo'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SmartFormFieldType>(
                initialValue: type,
                items: SmartFormFieldType.values
                    .map(
                      (t) => DropdownMenuItem(value: t, child: Text(t.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialog(() => type = v);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Obligatorio'),
                value: required,
                onChanged: (v) => setDialog(() => required = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );

    if (created != true || labelCtrl.text.trim().isEmpty) return;
    await CardRepository.addSmartFormField(
      widget.form.id,
      SmartFormFieldModel(
        id: '',
        formId: widget.form.id,
        fieldType: type,
        label: labelCtrl.text.trim(),
        isRequired: required,
      ),
    );
    widget.onChanged();
  }

  Future<void> _editField(SmartFormFieldModel field) async {
    final labelCtrl = TextEditingController(text: field.label);
    SmartFormFieldType type = field.fieldType;
    bool required = field.isRequired;
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: ctx.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Editar campo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: _corporateInputDecoration(ctx, 'Label del campo'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SmartFormFieldType>(
                initialValue: type,
                items: SmartFormFieldType.values
                    .map(
                      (t) => DropdownMenuItem(value: t, child: Text(t.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialog(() => type = v);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Obligatorio'),
                value: required,
                onChanged: (v) => setDialog(() => required = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (updated != true || labelCtrl.text.trim().isEmpty) return;
    await CardRepository.updateSmartFormField(
      field.copyWith(
        label: labelCtrl.text.trim(),
        fieldType: type,
        isRequired: required,
      ),
    );
    widget.onChanged();
  }

  Future<void> _deleteField(String fieldId) async {
    await CardRepository.deleteSmartFormField(fieldId);
    widget.onChanged();
  }

  Future<void> _reorderFields(int oldIndex, int newIndex) async {
    final items = [...widget.form.fields];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final normalized = items
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    await CardRepository.reorderSmartFormFields(normalized);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.form.name,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Switch.adaptive(
                value: widget.form.isActive,
                onChanged: _toggleActive,
              ),
              IconButton(
                onPressed: _renameForm,
                icon: Icon(Icons.edit_outlined, color: context.textSecondary),
              ),
              IconButton(
                onPressed: _deleteForm,
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
              ),
              IconButton(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addField,
                icon: const Icon(Icons.add),
                label: const Text('Agregar campo'),
              ),
            ),
            if (widget.form.fields.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Este formulario no tiene campos.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: widget.form.fields.length,
                onReorder: _reorderFields,
                itemBuilder: (_, i) {
                  final field = widget.form.fields[i];
                  return ListTile(
                    key: ValueKey(field.id),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Icon(
                        Icons.drag_indicator,
                        color: context.textMuted,
                      ),
                    ),
                    title: Text(field.label),
                    subtitle: Text(
                      '${field.fieldType.label}${field.isRequired ? ' · Obligatorio' : ''}',
                      style: GoogleFonts.dmSans(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _editField(field),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: context.textSecondary,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _deleteField(field.id),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Calendario Tab ───────────────────────────────────────────────────────────

class _CalendarioTab extends StatefulWidget {
  final bool calendarEnabled;
  final String? calendarUrl;
  final void Function(bool enabled, String url) onChanged;

  const _CalendarioTab({
    required this.calendarEnabled,
    required this.calendarUrl,
    required this.onChanged,
  });

  @override
  State<_CalendarioTab> createState() => _CalendarioTabState();
}

class _CalendarioTabState extends State<_CalendarioTab> {
  late bool _enabled;
  late final Map<CalendarProviderType, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _enabled = widget.calendarEnabled;
    final parsed = parseCalendarLinks(widget.calendarUrl);
    _controllers = {
      for (final provider in CalendarProviderType.values)
        provider: TextEditingController(text: parsed[provider] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _emitChanges() {
    final payload = encodeCalendarLinks({
      for (final entry in _controllers.entries)
        if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text,
    });
    widget.onChanged(_enabled, payload);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agendar reunión',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Muestra un botón en tu tarjeta para reservar una reunión',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _enabled,
                    onChanged: (v) {
                      setState(() => _enabled = v);
                      _emitChanges();
                    },
                    activeTrackColor: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // ── Preview button ───────────────────────────────────────
              AnimatedOpacity(
                opacity: _enabled ? 1.0 : 0.35,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: context.textPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: context.isDark ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Agendar reunión',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.isDark ? Colors.black : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Así se verá en tu tarjeta',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: context.textMuted,
                ),
              ),
              const SizedBox(height: 28),
              Divider(color: context.borderColor, height: 1),
              const SizedBox(height: 28),
              // ── Provider selection ───────────────────────────────────
              Text(
                'Integración',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configura uno o más proveedores. El cliente podrá elegir con cuál agendar.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              ...CalendarProviderType.values.map((provider) {
                final ctrl = _controllers[provider]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.label,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _EditInputField(
                        label: '${provider.label} URL',
                        controller: ctrl,
                        hint: provider.hint,
                        keyboardType: TextInputType.url,
                        enabled: _enabled,
                        onChanged: (_) {
                          setState(() {});
                          _emitChanges();
                        },
                      ),
                      const SizedBox(height: 12),
                      Divider(color: context.borderColor, height: 1),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tip B2B: El botón "Agendar reunión" reduce el ciclo de ventas al eliminar el intercambio de emails para coordinar horarios.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                        height: 1.5,
                      ),
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

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String hint;
  const _EmptyState({required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Text(
              message,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditInputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const _EditInputField({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
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
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled,
          maxLines: maxLines,
          onChanged: onChanged,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textMuted,
            ),
            filled: true,
            fillColor: context.isDark ? const Color(0xFF171717) : Colors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 12 : 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.85),
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _corporateInputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
    filled: true,
    fillColor: context.isDark ? const Color(0xFF171717) : Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
    ),
  );
}
