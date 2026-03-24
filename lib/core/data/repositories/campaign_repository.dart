import '../../services/supabase_service.dart';
import '../../../features/analytics/models/visit_event_model.dart';
import '../../../features/campaigns/models/campaign_model.dart';

class CampaignMemberAnalytics {
  final String userId;
  final String name;
  final String? jobTitle;
  final int interactions;
  final int clicks;
  final int profileViews;
  final int forms;
  final int leads;
  final int conversions;
  final List<String> sources;
  final String? cardId;
  final List<VisitEventModel> recentEvents;

  const CampaignMemberAnalytics({
    required this.userId,
    required this.name,
    required this.interactions,
    required this.clicks,
    required this.profileViews,
    required this.forms,
    required this.leads,
    required this.conversions,
    this.jobTitle,
    this.sources = const [],
    this.cardId,
    this.recentEvents = const [],
  });
}

class CampaignRepository {
  CampaignRepository._();

  static final _db = SupabaseService.client;

  static Future<List<CampaignModel>> fetchCampaigns(String orgId) async {
    final rows = await _db
        .from('campaigns')
        .select()
        .eq('org_id', orgId)
        .order('starts_at', ascending: false);
    final campaigns = (rows as List)
        .map((e) => CampaignModel.fromJson(e as Map<String, dynamic>))
        .toList();
    if (campaigns.isEmpty) return campaigns;

    try {
      final campaignIds = campaigns.map((campaign) => campaign.id).toList();
      final memberRows = await _db
          .from('campaign_members')
          .select('campaign_id, user_id')
          .inFilter('campaign_id', campaignIds);

      final campaignMembers = (memberRows as List)
          .map((row) => row as Map<String, dynamic>)
          .toList();
      final userIds = campaignMembers
          .map((row) => row['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final usersById = <String, String>{};
      if (userIds.isNotEmpty) {
        final userRows = await _db
            .from('users')
            .select('id, name')
            .inFilter('id', userIds);
        for (final row in (userRows as List).cast<Map<String, dynamic>>()) {
          usersById[row['id'] as String] = row['name'] as String? ?? '';
        }
      }

      final namesByCampaign = <String, List<String>>{};
      for (final row in campaignMembers) {
        final campaignId = row['campaign_id'] as String?;
        final userId = row['user_id'] as String?;
        if (campaignId == null || userId == null) continue;
        final name = usersById[userId];
        if (name == null || name.isEmpty) continue;
        namesByCampaign.putIfAbsent(campaignId, () => []).add(name);
      }

      final eventRows = await _db
          .from('visit_events')
          .select('campaign_id, source')
          .inFilter('campaign_id', campaignIds);
      final interactionCountByCampaign = <String, int>{};
      final sourceChannelsByCampaign = <String, Set<String>>{};
      for (final row in (eventRows as List).cast<Map<String, dynamic>>()) {
        final campaignId = row['campaign_id'] as String?;
        if (campaignId == null || campaignId.isEmpty) continue;
        interactionCountByCampaign[campaignId] =
            (interactionCountByCampaign[campaignId] ?? 0) + 1;
        final source = (row['source'] as String?)?.trim();
        if (source != null && source.isNotEmpty) {
          sourceChannelsByCampaign
              .putIfAbsent(campaignId, () => <String>{})
              .add(source);
        }
      }

      final leadRows = await _db
          .from('leads')
          .select('campaign_id, is_converted')
          .inFilter('campaign_id', campaignIds);
      final leadsByCampaign = <String, int>{};
      final conversionsByCampaign = <String, int>{};
      for (final row in (leadRows as List).cast<Map<String, dynamic>>()) {
        final campaignId = row['campaign_id'] as String?;
        if (campaignId == null || campaignId.isEmpty) continue;
        leadsByCampaign[campaignId] = (leadsByCampaign[campaignId] ?? 0) + 1;
        if (row['is_converted'] == true) {
          conversionsByCampaign[campaignId] =
              (conversionsByCampaign[campaignId] ?? 0) + 1;
        }
      }

      return campaigns
          .map(
            (campaign) => campaign.copyWith(
              assignedMemberNames: namesByCampaign[campaign.id] ?? const [],
              taps: interactionCountByCampaign[campaign.id] ?? 0,
              leads: leadsByCampaign[campaign.id] ?? 0,
              conversions: conversionsByCampaign[campaign.id] ?? 0,
              interactionCount: interactionCountByCampaign[campaign.id] ?? 0,
              sourceChannels:
                  sourceChannelsByCampaign[campaign.id]?.toList() ?? const [],
            ),
          )
          .toList();
    } catch (_) {
      return campaigns;
    }
  }

  /// Also fetch campaigns owned by user (no org) using user_id indirectly
  /// via digital_cards. For simplicity we filter by all campaigns where
  /// org_id matches or where user's card is referenced.
  static Future<List<CampaignModel>> fetchCampaignsForUser({
    String? orgId,
  }) async {
    if (orgId == null) return [];
    return fetchCampaigns(orgId);
  }

  static Future<CampaignModel> createCampaign(
    CampaignModel campaign,
    String? orgId,
  ) async {
    final data = await _db
        .from('campaigns')
        .insert(campaign.toJson(orgId: orgId))
        .select()
        .single();
    return CampaignModel.fromJson(data);
  }

  static Future<CampaignModel> updateCampaign(CampaignModel campaign) async {
    final data = await _db
        .from('campaigns')
        .update(campaign.toJson())
        .eq('id', campaign.id)
        .select()
        .single();
    return CampaignModel.fromJson(data);
  }

  static Future<void> deleteCampaign(String id) async {
    await _db.from('campaigns').delete().eq('id', id);
  }

  static Future<List<Map<String, String>>> fetchCampaignMembers(
    String campaignId,
  ) async {
    try {
      final rows = await _db
          .from('campaign_members')
          .select('user_id')
          .eq('campaign_id', campaignId);
      final ids = (rows as List)
          .map((r) => (r as Map)['user_id'] as String)
          .toList();
      if (ids.isEmpty) return [];
      final users = await _db
          .from('users')
          .select('id, name, role, job_title')
          .inFilter('id', ids);
      return (users as List)
          .map(
            (u) => {
              'id': (u as Map)['id'] as String,
              'name': u['name'] as String? ?? '',
              'role': u['role'] as String? ?? '',
              'job_title': u['job_title'] as String? ?? '',
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addCampaignMember(
    String campaignId,
    String userId,
  ) async {
    await _db.from('campaign_members').insert({
      'campaign_id': campaignId,
      'user_id': userId,
    });
  }

  static Future<void> addCampaignMembers(
    String campaignId,
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return;
    await _db
        .from('campaign_members')
        .insert(
          userIds
              .map((userId) => {'campaign_id': campaignId, 'user_id': userId})
              .toList(),
        );
  }

  static Future<void> removeCampaignMember(
    String campaignId,
    String userId,
  ) async {
    await _db
        .from('campaign_members')
        .delete()
        .eq('campaign_id', campaignId)
        .eq('user_id', userId);
  }

  static Future<void> replaceCampaignMembers(
    String campaignId,
    List<String> userIds,
  ) async {
    await _db.from('campaign_members').delete().eq('campaign_id', campaignId);
    await addCampaignMembers(campaignId, userIds);
  }

  static Future<List<Map<String, String>>> fetchOrgUsers(String orgId) async {
    try {
      final rows = await _db
          .from('users')
          .select('id, name, role, job_title')
          .eq('org_id', orgId)
          .eq('is_active', true);
      return (rows as List)
          .map(
            (u) => {
              'id': (u as Map)['id'] as String,
              'name': u['name'] as String? ?? '',
              'role': u['role'] as String? ?? '',
              'job_title': u['job_title'] as String? ?? '',
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<CampaignMemberAnalytics?> fetchMemberAnalyticsForCampaign({
    required String campaignId,
    required String userId,
  }) async {
    try {
      final users = await _db
          .from('users')
          .select('id, name, job_title')
          .eq('id', userId)
          .limit(1);
      if ((users as List).isEmpty) return null;
      final user = users.first;

      final cardRows = await _db
          .from('digital_cards')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      final cardId = (cardRows as List).isNotEmpty
          ? cardRows.first['id'] as String?
          : null;

      if (cardId == null || cardId.isEmpty) {
        return CampaignMemberAnalytics(
          userId: userId,
          name: user['name'] as String? ?? '',
          jobTitle: user['job_title'] as String?,
          interactions: 0,
          clicks: 0,
          profileViews: 0,
          forms: 0,
          leads: 0,
          conversions: 0,
        );
      }

      final eventRows = await _db
          .from('visit_events')
          .select()
          .eq('campaign_id', campaignId)
          .eq('card_id', cardId)
          .order('timestamp', ascending: false);
      final events = (eventRows as List)
          .cast<Map<String, dynamic>>()
          .map(VisitEventModel.fromJson)
          .toList();
      final interactions = events.length;
      final sourceSet = <String>{};
      var clicks = 0;
      var profileViews = 0;
      var forms = 0;
      for (final event in events) {
        final source = event.source?.trim();
        if (source != null && source.isNotEmpty) sourceSet.add(source);
        if (source == 'nfc' || source == 'qr') profileViews += 1;
        if (source == 'form') forms += 1;
        if (source == 'link' || source == 'contact' || source == 'social') {
          clicks += 1;
        }
      }

      final leadRows = await _db
          .from('leads')
          .select('is_converted')
          .eq('campaign_id', campaignId)
          .eq('card_id', cardId);
      final leads = (leadRows as List).length;
      var conversions = 0;
      for (final row in leadRows.cast<Map<String, dynamic>>()) {
        if (row['is_converted'] == true) conversions += 1;
      }

      return CampaignMemberAnalytics(
        userId: userId,
        name: user['name'] as String? ?? '',
        jobTitle: user['job_title'] as String?,
        interactions: interactions,
        clicks: clicks,
        profileViews: profileViews,
        forms: forms,
        leads: leads,
        conversions: conversions,
        sources: sourceSet.toList()..sort(),
        cardId: cardId,
        recentEvents: events.take(8).toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
