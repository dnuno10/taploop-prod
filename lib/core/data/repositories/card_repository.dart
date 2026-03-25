import '../../services/supabase_service.dart';
import '../../../features/card/models/digital_card_model.dart';
import '../../../features/card/models/contact_item_model.dart';
import '../../../features/card/models/social_link_model.dart';
import '../../../features/card/models/smart_form_model.dart';

class CardRepository {
  CardRepository._();

  static final _db = SupabaseService.client;

  // ─── Fetch card with contacts & social links ─────────────────────────────

  static Future<DigitalCardModel?> fetchCard(String cardId) async {
    final cardData = await _db
        .from('digital_cards')
        .select()
        .eq('id', cardId)
        .single();

    final contacts = await _db
        .from('contact_items')
        .select()
        .eq('card_id', cardId)
        .order('sort_order');

    final socials = await _db
        .from('social_links')
        .select()
        .eq('card_id', cardId)
        .order('sort_order');

    return buildCardModel(
      cardData,
      contactItems: (contacts as List)
          .map((e) => ContactItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      socialLinks: (socials as List)
          .map((e) => SocialLinkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ─── Fetch public card by slug (no auth required) ────────────────────────

  static Future<DigitalCardModel?> fetchBySlug(String slug) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('public_slug', slug)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return _fetchWithItems(rows.first);
  }

  // ─── Fetch public card by user_id (permanent NFC URL) ────────────────────
  // This never breaks even if the user changes their slug.

  static Future<DigitalCardModel?> fetchByUserId(String userId) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return _fetchWithItems(rows.first);
  }

  // ─── Check NFC serial status ─────────────────────────────────────────────
  // Returns: 'assigned' | 'unassigned' | 'not_found'

  static Future<String> checkNfcSerial(String serial) async {
    final rows = await _db
        .from('nfc_cards')
        .select('is_assigned')
        .eq('serial', serial)
        .limit(1);
    if ((rows as List).isEmpty) return 'not_found';
    final assigned = rows.first['is_assigned'] as bool? ?? false;
    return assigned ? 'assigned' : 'unassigned';
  }

  // ─── Fetch public card by NFC serial (pre-manufactured cards) ────────────

  static Future<DigitalCardModel?> fetchByNfcSerial(String serial) async {
    final result = await _db.rpc(
      'get_user_id_by_nfc_serial',
      params: {'p_serial': serial},
    );
    final userId = result as String?;
    if (userId == null || userId.isEmpty) return null;
    return fetchByUserId(userId);
  }

  // ─── Activate NFC card (link serial → current user) ──────────────────────

  static Future<bool> activateNfcCard(String serial) async {
    final currentUser = _db.auth.currentUser;
    if (currentUser == null) return false;

    final res = await _db
        .from('nfc_cards')
        .update({
          'user_id': currentUser.id,
          'is_assigned': true,
          'assigned_at': DateTime.now().toIso8601String(),
        })
        .eq('serial', serial)
        .eq('is_assigned', false)
        .select();

    final activated = (res as List).isNotEmpty;
    if (!activated) return false;

    await _ensureDigitalCardForUser(currentUser.id);
    return true;
  }

  static Future<DigitalCardModel?> _ensureDigitalCardForUser(
    String userId,
  ) async {
    final existing = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .order('created_at')
        .limit(1);

    if (existing.isNotEmpty) {
      return _fetchWithItems(existing.first);
    }

    final userRows = await _db
        .from('users')
        .select('name, org_id')
        .eq('id', userId)
        .limit(1);

    final userJson = userRows.isNotEmpty
        ? userRows.first
        : const <String, dynamic>{};
    final resolvedName = (userJson['name'] as String?)?.trim();
    final orgId = userJson['org_id'] as String?;
    String companyName = '';
    if (orgId != null && orgId.isNotEmpty) {
      final orgRows = await _db
          .from('organizations')
          .select('name')
          .eq('id', orgId)
          .limit(1);
      if ((orgRows as List).isNotEmpty) {
        companyName = (orgRows.first['name'] as String?)?.trim() ?? '';
      }
    }
    final slug = _generateSlug(
      resolvedName == null || resolvedName.isEmpty ? 'usuario' : resolvedName,
      userId,
    );

    final created = await _db
        .from('digital_cards')
        .insert({
          'user_id': userId,
          'org_id': orgId,
          'name': resolvedName ?? '',
          'job_title': '',
          'company': companyName,
          'bio': '',
          'public_slug': slug,
          'is_active': true,
          'theme_style': 'white',
          'layout_style': 'centered',
          'primary_color': 0xFFEF6820,
          'bg_style': 'plain',
        })
        .select()
        .single();

    return _fetchWithItems(created);
  }

  static Future<void> syncCardOrganizationCompany({
    required String cardId,
    required String company,
    String? orgId,
  }) async {
    await _db
        .from('digital_cards')
        .update({
          'company': company,
          if (orgId != null && orgId.isNotEmpty) 'org_id': orgId,
        })
        .eq('id', cardId);
  }

  static String _generateSlug(String name, String uid) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final normalized = base.isEmpty ? 'usuario' : base;
    final suffix = uid.substring(0, 6);
    return '$normalized-$suffix';
  }

  // ─── Shared helper ────────────────────────────────────────────────────────

  static Future<DigitalCardModel> _fetchWithItems(
    Map<String, dynamic> cardJson,
  ) async {
    final cardId = cardJson['id'] as String;

    final contacts = await _db
        .from('contact_items')
        .select()
        .eq('card_id', cardId)
        .eq('is_visible', true)
        .order('sort_order');

    final socials = await _db
        .from('social_links')
        .select()
        .eq('card_id', cardId)
        .eq('is_visible', true)
        .order('sort_order');

    return buildCardModel(
      cardJson,
      contactItems: (contacts as List)
          .map((e) => ContactItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      socialLinks: (socials as List)
          .map((e) => SocialLinkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<DigitalCardModel> buildCardModel(
    Map<String, dynamic> cardJson, {
    List<ContactItemModel> contactItems = const [],
    List<SocialLinkModel> socialLinks = const [],
  }) async {
    final hydratedJson = Map<String, dynamic>.from(cardJson);
    final orgLogoUrl = await fetchOrganizationLogoUrl(
      hydratedJson['org_id'] as String?,
    );
    if (orgLogoUrl != null && orgLogoUrl.isNotEmpty) {
      hydratedJson['company_logo_url'] = orgLogoUrl;
    }

    return DigitalCardModel.fromJson(
      hydratedJson,
      contactItems: contactItems,
      socialLinks: socialLinks,
    );
  }

  static Future<String?> fetchOrganizationLogoUrl(String? orgId) async {
    if (orgId == null || orgId.isEmpty) return null;
    final rows = await _db
        .from('organizations')
        .select('company_logo')
        .eq('id', orgId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return resolveCompanyLogoUrl(rows.first['company_logo'] as String?);
  }

  static String? resolveCompanyLogoUrl(String? storedValue) {
    final value = storedValue?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return _db.storage.from('company-logos').getPublicUrl(value);
  }

  // ─── Save card fields ─────────────────────────────────────────────────────

  static Future<void> saveCard(DigitalCardModel card) async {
    await _db.from('digital_cards').update(card.toJson()).eq('id', card.id);
  }

  static Future<void> setCardActiveState({
    required String cardId,
    required bool isActive,
    String? reason,
  }) async {
    final currentUser = _db.auth.currentUser;
    await _db
        .from('digital_cards')
        .update({
          'is_active': isActive,
          'deactivated_at': isActive ? null : DateTime.now().toIso8601String(),
          'deactivation_reason': isActive ? null : reason,
          'deactivated_by': isActive ? null : currentUser?.id,
        })
        .eq('id', cardId);
  }

  // ─── Contact items ────────────────────────────────────────────────────────

  static Future<ContactItemModel> addContactItem(
    String cardId,
    ContactItemModel item,
  ) async {
    final last = await _db
        .from('contact_items')
        .select('sort_order')
        .eq('card_id', cardId)
        .order('sort_order', ascending: false)
        .limit(1);
    final nextOrder = (last as List).isEmpty
        ? 0
        : ((last.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    final data = await _db
        .from('contact_items')
        .insert(item.copyWith(sortOrder: nextOrder).toJson(cardId: cardId))
        .select()
        .single();
    return ContactItemModel.fromJson(data);
  }

  static Future<void> updateContactItem(ContactItemModel item) async {
    await _db.from('contact_items').update(item.toJson()).eq('id', item.id);
  }

  static Future<void> deleteContactItem(String itemId) async {
    await _db.from('contact_items').delete().eq('id', itemId);
  }

  static Future<void> reorderContactItems(List<ContactItemModel> items) async {
    for (var i = 0; i < items.length; i++) {
      await _db
          .from('contact_items')
          .update({'sort_order': i})
          .eq('id', items[i].id);
    }
  }

  // ─── Social links ─────────────────────────────────────────────────────────

  static Future<SocialLinkModel> addSocialLink(
    String cardId,
    SocialLinkModel link,
  ) async {
    final last = await _db
        .from('social_links')
        .select('sort_order')
        .eq('card_id', cardId)
        .order('sort_order', ascending: false)
        .limit(1);
    final nextOrder = (last as List).isEmpty
        ? 0
        : ((last.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    final data = await _db
        .from('social_links')
        .insert(link.copyWith(sortOrder: nextOrder).toJson(cardId: cardId))
        .select()
        .single();
    return SocialLinkModel.fromJson(data);
  }

  static Future<void> updateSocialLink(SocialLinkModel link) async {
    await _db.from('social_links').update(link.toJson()).eq('id', link.id);
  }

  static Future<void> deleteSocialLink(String linkId) async {
    await _db.from('social_links').delete().eq('id', linkId);
  }

  static Future<void> reorderSocialLinks(List<SocialLinkModel> links) async {
    for (var i = 0; i < links.length; i++) {
      await _db
          .from('social_links')
          .update({'sort_order': i})
          .eq('id', links[i].id);
    }
  }

  // ─── Smart forms ──────────────────────────────────────────────────────────

  static Future<List<SmartFormModel>> fetchSmartForms(String cardId) async {
    final formsRows = await _db
        .from('smart_forms')
        .select()
        .eq('card_id', cardId)
        .order('created_at');

    final forms = <SmartFormModel>[];
    for (final row in (formsRows as List)) {
      final formId = row['id'] as String;
      final fieldsRows = await _db
          .from('smart_form_fields')
          .select()
          .eq('form_id', formId)
          .order('sort_order');
      final fields = (fieldsRows as List)
          .map((e) => SmartFormFieldModel.fromJson(e as Map<String, dynamic>))
          .toList();
      forms.add(
        SmartFormModel.fromJson(row as Map<String, dynamic>, fields: fields),
      );
    }
    return forms;
  }

  static Future<SmartFormModel> createSmartForm(
    String cardId,
    String name,
  ) async {
    final data = await _db
        .from('smart_forms')
        .insert({'card_id': cardId, 'name': name, 'is_active': true})
        .select()
        .single();
    return SmartFormModel.fromJson(data, fields: const []);
  }

  static Future<void> updateSmartForm(SmartFormModel form) async {
    await _db.from('smart_forms').update(form.toJson()).eq('id', form.id);
  }

  static Future<void> deleteSmartForm(String formId) async {
    await _db.from('smart_form_fields').delete().eq('form_id', formId);
    await _db.from('smart_forms').delete().eq('id', formId);
  }

  static Future<SmartFormFieldModel> addSmartFormField(
    String formId,
    SmartFormFieldModel field,
  ) async {
    final last = await _db
        .from('smart_form_fields')
        .select('sort_order')
        .eq('form_id', formId)
        .order('sort_order', ascending: false)
        .limit(1);
    final nextOrder = (last as List).isEmpty
        ? 0
        : ((last.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    final data = await _db
        .from('smart_form_fields')
        .insert(field.copyWith(sortOrder: nextOrder).toJson(formId: formId))
        .select()
        .single();
    return SmartFormFieldModel.fromJson(data);
  }

  static Future<void> updateSmartFormField(SmartFormFieldModel field) async {
    await _db
        .from('smart_form_fields')
        .update(field.toJson())
        .eq('id', field.id);
  }

  static Future<void> deleteSmartFormField(String fieldId) async {
    await _db.from('smart_form_fields').delete().eq('id', fieldId);
  }

  static Future<void> reorderSmartFormFields(
    List<SmartFormFieldModel> fields,
  ) async {
    for (var i = 0; i < fields.length; i++) {
      await _db
          .from('smart_form_fields')
          .update({'sort_order': i})
          .eq('id', fields[i].id);
    }
  }
}
