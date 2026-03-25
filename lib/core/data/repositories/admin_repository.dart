import '../../services/supabase_service.dart';
import 'card_repository.dart';
import '../../../features/analytics/models/team_member_model.dart';
import '../../../features/auth/models/user_model.dart';
import '../../../features/card/models/digital_card_model.dart';
import '../../../features/card/models/contact_item_model.dart';
import '../../../features/card/models/social_link_model.dart';

class AdminRepository {
  AdminRepository._();

  static final _db = SupabaseService.client;

  // ─── Fetch org members ────────────────────────────────────────────────────

  static Future<List<TeamMemberModel>> fetchTeamMembers(String orgId) async {
    final now = DateTime.now();
    final rangeStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final users = await _db
        .from('users')
        .select('id, name, job_title, photo_url')
        .eq('org_id', orgId)
        .eq('is_active', true);

    final usersList = (users as List).cast<Map<String, dynamic>>();
    if (usersList.isEmpty) return const [];

    final userIds = usersList
        .map((u) => u['id'] as String?)
        .whereType<String>()
        .toList();

    if (userIds.isEmpty) return const [];

    final cards = await _db
        .from('digital_cards')
        .select('id, user_id')
        .inFilter('user_id', userIds);

    final cardRows = (cards as List).cast<Map<String, dynamic>>();
    final cardsByUser = <String, List<String>>{};
    final allCardIds = <String>[];

    for (final row in cardRows) {
      final cardId = row['id'] as String?;
      final userId = row['user_id'] as String?;
      if (cardId == null || userId == null) continue;
      cardsByUser.putIfAbsent(userId, () => []).add(cardId);
      allCardIds.add(cardId);
    }

    final profileViewsByCard = <String, int>{};
    final tapsByCard = <String, int>{};
    final leadsByCard = <String, int>{};
    final conversionsByCard = <String, int>{};
    final contactsSavedByCard = <String, int>{};
    final totalClicksByCard = <String, int>{};
    final viewsSeriesByCard = <String, List<int>>{};
    final tapsSeriesByCard = <String, List<int>>{};
    final clicksSeriesByCard = <String, List<int>>{};
    final linkStatsByCard = <String, List<TeamMemberLinkStat>>{};

    if (allCardIds.isNotEmpty) {
      final visitRows = await _db
          .from('visit_events')
          .select('card_id, source, timestamp')
          .inFilter('card_id', allCardIds);
      for (final row in (visitRows as List).cast<Map<String, dynamic>>()) {
        final cardId = row['card_id'] as String?;
        if (cardId == null) continue;
        final source = row['source'] as String? ?? '';
        final timestamp = DateTime.tryParse(row['timestamp'] as String? ?? '');
        if (source == 'nfc' || source == 'qr' || source == 'link') {
          profileViewsByCard[cardId] = (profileViewsByCard[cardId] ?? 0) + 1;
        }
        if (source == 'nfc') {
          tapsByCard[cardId] = (tapsByCard[cardId] ?? 0) + 1;
        }
        if (source == 'contact') {
          contactsSavedByCard[cardId] = (contactsSavedByCard[cardId] ?? 0) + 1;
        }
        if (source == 'contact' || source == 'social') {
          totalClicksByCard[cardId] = (totalClicksByCard[cardId] ?? 0) + 1;
        }
        if (timestamp != null && !timestamp.isBefore(rangeStart)) {
          final bucket = timestamp.difference(rangeStart).inDays;
          if (bucket >= 0 && bucket < 7) {
            final viewsSeries = viewsSeriesByCard.putIfAbsent(
              cardId,
              () => List.filled(7, 0),
            );
            final tapsSeries = tapsSeriesByCard.putIfAbsent(
              cardId,
              () => List.filled(7, 0),
            );
            final clicksSeries = clicksSeriesByCard.putIfAbsent(
              cardId,
              () => List.filled(7, 0),
            );
            if (source == 'nfc' || source == 'qr' || source == 'link') {
              viewsSeries[bucket] += 1;
            }
            if (source == 'nfc') {
              tapsSeries[bucket] += 1;
            }
            if (source == 'contact' || source == 'social') {
              clicksSeries[bucket] += 1;
            }
          }
        }
      }

      final linkRows = await _db
          .from('link_stats')
          .select('card_id, label, platform, clicks')
          .inFilter('card_id', allCardIds)
          .order('clicks', ascending: false);
      for (final row in (linkRows as List).cast<Map<String, dynamic>>()) {
        final cardId = row['card_id'] as String?;
        if (cardId == null) continue;
        linkStatsByCard
            .putIfAbsent(cardId, () => [])
            .add(
              TeamMemberLinkStat(
                label:
                    row['label'] as String? ??
                    row['platform'] as String? ??
                    'Enlace',
                platform: row['platform'] as String? ?? '',
                clicks: (row['clicks'] as num?)?.toInt() ?? 0,
              ),
            );
      }

      final leadRows = await _db
          .from('leads')
          .select('card_id, is_converted')
          .inFilter('card_id', allCardIds);
      for (final row in (leadRows as List).cast<Map<String, dynamic>>()) {
        final cardId = row['card_id'] as String?;
        if (cardId == null) continue;
        final converted = row['is_converted'] as bool? ?? false;
        if (converted) {
          conversionsByCard[cardId] = (conversionsByCard[cardId] ?? 0) + 1;
        } else {
          leadsByCard[cardId] = (leadsByCard[cardId] ?? 0) + 1;
        }
      }
    }

    return usersList.map((userJson) {
      final userId = userJson['id'] as String;
      final userCardIds = cardsByUser[userId] ?? const <String>[];

      int profileViews = 0;
      int taps = 0;
      int leads = 0;
      int conversions = 0;
      int contactsSaved = 0;
      int totalClicks = 0;
      final viewsByDay = List.filled(7, 0);
      final tapsByDay = List.filled(7, 0);
      final clicksByDay = List.filled(7, 0);
      final aggregatedLinks = <String, TeamMemberLinkStat>{};

      for (final cardId in userCardIds) {
        profileViews += profileViewsByCard[cardId] ?? 0;
        taps += tapsByCard[cardId] ?? 0;
        leads += leadsByCard[cardId] ?? 0;
        conversions += conversionsByCard[cardId] ?? 0;
        contactsSaved += contactsSavedByCard[cardId] ?? 0;
        totalClicks += totalClicksByCard[cardId] ?? 0;
        final cardViews = viewsSeriesByCard[cardId] ?? const <int>[];
        final cardTaps = tapsSeriesByCard[cardId] ?? const <int>[];
        final cardClicks = clicksSeriesByCard[cardId] ?? const <int>[];
        for (var i = 0; i < 7; i++) {
          if (i < cardViews.length) viewsByDay[i] += cardViews[i];
          if (i < cardTaps.length) tapsByDay[i] += cardTaps[i];
          if (i < cardClicks.length) clicksByDay[i] += cardClicks[i];
        }
        for (final stat
            in linkStatsByCard[cardId] ?? const <TeamMemberLinkStat>[]) {
          final key = '${stat.platform}:${stat.label}';
          final current = aggregatedLinks[key];
          aggregatedLinks[key] = TeamMemberLinkStat(
            label: stat.label,
            platform: stat.platform,
            clicks: (current?.clicks ?? 0) + stat.clicks,
          );
        }
      }

      return TeamMemberModel(
        id: userId,
        cardIds: userCardIds,
        name: userJson['name'] as String? ?? '',
        jobTitle: userJson['job_title'] as String? ?? '',
        avatarUrl: userJson['photo_url'] as String?,
        taps: taps,
        leads: leads,
        profileViews: profileViews,
        contactsSaved: contactsSaved,
        conversions: conversions,
        totalClicks: totalClicks,
        viewsByDay: viewsByDay,
        tapsByDay: tapsByDay,
        clicksByDay: clicksByDay,
        linkStats: aggregatedLinks.values.toList()
          ..sort((a, b) => b.clicks.compareTo(a.clicks)),
      );
    }).toList();
  }

  // ─── Fetch full user+card for member editing ──────────────────────────────

  static Future<UserModel> fetchUser(String userId) async {
    final data = await _db.from('users').select().eq('id', userId).single();
    return UserModel.fromJson(data);
  }

  static Future<DigitalCardModel?> fetchCardForUser(String userId) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    final cardJson = rows.first;
    final cardId = cardJson['id'] as String;

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

    return CardRepository.buildCardModel(
      cardJson,
      contactItems: (contacts as List)
          .map((e) => ContactItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      socialLinks: (socials as List)
          .map((e) => SocialLinkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ─── Update member ────────────────────────────────────────────────────────

  static Future<void> updateUser(UserModel user) async {
    final payload = user.toJson()..remove('id');
    await _db.from('users').update(payload).eq('id', user.id);
  }

  static Future<void> updateCard(DigitalCardModel card) async {
    await _db.from('digital_cards').update(card.toJson()).eq('id', card.id);
  }

  static Future<void> updateCardActivation({
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

  static Future<void> deactivateUser(String userId) async {
    await _db.from('users').update({'is_active': false}).eq('id', userId);
  }

  // ─── Org info ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchOrg(String orgId) async {
    final data = await _db
        .from('organizations')
        .select()
        .eq('id', orgId)
        .single();
    return data as Map<String, dynamic>?;
  }

  static Future<void> updateOrgLogo({
    required String orgId,
    required String companyLogo,
  }) async {
    await _db
        .from('organizations')
        .update({'company_logo': companyLogo})
        .eq('id', orgId);
  }
}
