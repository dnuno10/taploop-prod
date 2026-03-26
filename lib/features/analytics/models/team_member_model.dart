class TeamMemberLinkStat {
  final String label;
  final String platform;
  final int clicks;

  const TeamMemberLinkStat({
    required this.label,
    required this.platform,
    required this.clicks,
  });
}

class TeamMemberModel {
  final String id;
  final List<String> cardIds;
  final String name;
  final String jobTitle;
  final String role;
  final String? avatarUrl;
  final int taps;
  final int leads;
  final int profileViews;
  final int contactsSaved;
  final int conversions;
  final int totalClicks;
  final List<int> viewsByDay;
  final List<int> tapsByDay;
  final List<int> clicksByDay;
  final List<TeamMemberLinkStat> linkStats;

  const TeamMemberModel({
    required this.id,
    this.cardIds = const [],
    required this.name,
    required this.jobTitle,
    this.role = 'default',
    this.avatarUrl,
    required this.taps,
    this.leads = 0,
    required this.profileViews,
    required this.contactsSaved,
    this.conversions = 0,
    this.totalClicks = 0,
    this.viewsByDay = const [],
    this.tapsByDay = const [],
    this.clicksByDay = const [],
    this.linkStats = const [],
  });

  factory TeamMemberModel.fromJson(Map<String, dynamic> json) {
    return TeamMemberModel(
      id: json['id'] as String,
      cardIds: const [],
      name: json['name'] as String? ?? '',
      jobTitle: json['job_title'] as String? ?? '',
      role: json['role'] as String? ?? 'default',
      avatarUrl: json['photo_url'] as String?,
      taps: (json['taps'] as num?)?.toInt() ?? 0,
      leads: (json['leads'] as num?)?.toInt() ?? 0,
      profileViews: (json['profile_views'] as num?)?.toInt() ?? 0,
      contactsSaved: (json['contacts_saved'] as num?)?.toInt() ?? 0,
      conversions: (json['conversions'] as num?)?.toInt() ?? 0,
      totalClicks: (json['total_clicks'] as num?)?.toInt() ?? 0,
    );
  }

  double get conversionRate =>
      taps == 0 ? 0 : (conversions / taps).clamp(0.0, 1.0);

  double get leadRate => profileViews == 0 ? 0 : (leads / profileViews);

  bool get isAdmin => role == 'admin';

  /// AI-generated insight for this member.
  String get aiInsight {
    if (conversionRate >= 0.15) {
      return 'Tiene la mejor tasa de conversión del equipo.';
    }
    if (taps >= 60) {
      return 'Alto volumen de taps. Enfocarse en conversión.';
    }
    if (contactsSaved >= 20) {
      return 'Muchos contactos guardados — buen cierre presencial.';
    }
    return 'Potencial de mejora activando más redes en la tarjeta.';
  }

  String get behaviorSummary {
    if (totalClicks >= leads && leads > 0) {
      return 'Genera intención alta: sus clicks ya están empujando leads reales.';
    }
    if (profileViews > 0 && totalClicks == 0) {
      return 'Tiene visibilidad, pero falta convertir visitas en interacción.';
    }
    if (taps > profileViews / 2 && profileViews > 0) {
      return 'Sobresale en contacto presencial y activación directa.';
    }
    return aiInsight;
  }
}
