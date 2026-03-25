import 'package:flutter/foundation.dart';

import '../../services/supabase_service.dart';
import '../../utils/visitor_info.dart';
import '../../../features/analytics/models/analytics_summary_model.dart';
import '../../../features/analytics/models/visit_event_model.dart';
import '../../../features/analytics/models/link_stat_model.dart';

class AnalyticsRepository {
  AnalyticsRepository._();

  static final _db = SupabaseService.client;

  // ─── Analytics summary for a card ────────────────────────────────────────

  static Future<AnalyticsSummaryModel> fetchSummary(
    String cardId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final rangeEnd = to ?? now;
    final rangeStart = from ?? now.subtract(const Duration(days: 6));
    final rangeDuration = rangeEnd.difference(rangeStart);
    final prevStart = rangeStart.subtract(rangeDuration);

    // All visit events
    final allEvents = await _db
        .from('visit_events')
        .select()
        .eq('card_id', cardId)
        .order('timestamp', ascending: false);

    final events = (allEvents as List)
        .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // Filter to selected range
    final rangeEvents = events
        .where(
          (e) =>
              !e.timestamp.isBefore(rangeStart) &&
              !e.timestamp.isAfter(rangeEnd),
        )
        .toList();

    final totalVisits = rangeEvents.length;
    final totalTaps = rangeEvents.where((e) => e.source == 'nfc').length;
    final totalQrScans = rangeEvents.where((e) => e.source == 'qr').length;
    final clickEvents = rangeEvents
        .where((e) => e.source == 'contact' || e.source == 'social')
        .toList();

    final visitsThisWeek = rangeEvents.length;
    final visitsLastWeek = events
        .where(
          (e) =>
              !e.timestamp.isBefore(prevStart) &&
              e.timestamp.isBefore(rangeStart),
        )
        .length;

    // Visits by day (7 days ending at rangeEnd)
    final visitsByDay = List.generate(7, (i) {
      final day = rangeEnd.subtract(Duration(days: 6 - i));
      return rangeEvents
          .where(
            (e) =>
                e.timestamp.year == day.year &&
                e.timestamp.month == day.month &&
                e.timestamp.day == day.day,
          )
          .length;
    });

    final totalClicks = clickEvents.length;
    final groupedClicks = <String, int>{};
    final groupedPlatforms = <String, String>{};

    for (final event in clickEvents) {
      final label = (event.label?.trim().isNotEmpty ?? false)
          ? event.label!.trim()
          : (event.source == 'contact' ? 'Contacto' : 'Red social');
      groupedClicks[label] = (groupedClicks[label] ?? 0) + 1;
      groupedPlatforms[label] = event.source ?? '';
    }

    final linkStats =
        groupedClicks.entries
            .map(
              (entry) => LinkStatModel(
                linkId: entry.key,
                label: entry.key,
                platform: groupedPlatforms[entry.key] ?? '',
                clicks: entry.value,
                percentage: totalClicks > 0 ? entry.value / totalClicks : 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.clicks.compareTo(a.clicks));

    // Recent 10 events within range
    final recentEvents = rangeEvents.take(10).toList();

    return AnalyticsSummaryModel(
      totalVisits: totalVisits,
      totalTaps: totalTaps,
      totalQrScans: totalQrScans,
      totalClicks: totalClicks,
      visitsThisWeek: visitsThisWeek,
      visitsLastWeek: visitsLastWeek,
      linkStats: linkStats,
      recentEvents: recentEvents,
      visitsByDay: visitsByDay,
    );
  }

  // ─── Record a visit (fire-and-forget) ────────────────────────────────────

  /// source: 'nfc' | 'qr' | 'link'
  static Future<void> recordVisit(String cardId, String source) async {
    try {
      final info = await collectVisitorInfo();
      await _recordCardVisit(
        cardId: cardId,
        source: source,
        label: null,
        info: info,
      );
    } catch (e) {
      debugPrint('[Analytics] recordVisit error: $e');
    }
  }

  // ─── Record / increment a link click (fire-and-forget) ───────────────────

  static Future<void> recordLinkClick({
    required String cardId,
    required String linkId,
    required String label,
    required String platform,
  }) async {
    try {
      await _db.rpc(
        'record_link_click',
        params: {
          'p_id': linkId,
          'p_card_id': cardId,
          'p_label': label,
          'p_platform': platform,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] recordLinkClick error: $e');
    }
  }

  // ─── Record an interaction (contact tap / social tap / form fill) ─────────

  /// source: 'contact' | 'social' | 'form'
  /// label: displayLabel / platform name / form title
  static Future<void> recordInteraction({
    required String cardId,
    required String source,
    required String label,
  }) async {
    try {
      final info = await collectVisitorInfo();
      await _recordCardVisit(
        cardId: cardId,
        source: source,
        label: label,
        info: info,
      );
    } catch (e) {
      debugPrint('[Analytics] recordInteraction error: $e');
    }
  }

  static Future<void> _recordCardVisit({
    required String cardId,
    required String source,
    required String? label,
    required Map<String, String?> info,
  }) async {
    final attempts = <Map<String, dynamic>>[
      {
        'p_card_id': cardId,
        'p_source': source,
        'p_label': label,
        'p_device': info['device'],
        'p_ip': info['ip'],
        'p_city': info['city'],
        'p_country': info['country'],
      },
      {
        'p_card_id': cardId,
        'p_source': source,
        'p_device': info['device'],
        'p_ip': info['ip'],
        'p_city': info['city'],
        'p_country': info['country'],
      },
      {'p_card_id': cardId, 'p_source': source, 'p_label': label},
      {'p_card_id': cardId, 'p_source': source},
    ];

    for (final params in attempts) {
      try {
        final clean = <String, dynamic>{};
        params.forEach((key, value) {
          if (value != null) clean[key] = value;
        });
        await _db.rpc('record_card_visit', params: clean);
        return;
      } catch (_) {}
    }

    throw Exception('record_card_visit failed with all parameter variants');
  }

  // ─── Recent visit events (last N) ────────────────────────────────────────

  static Future<List<VisitEventModel>> fetchRecentEvents(
    String cardId, {
    int limit = 20,
  }) async {
    final rows = await _db
        .from('visit_events')
        .select()
        .eq('card_id', cardId)
        .order('timestamp', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
