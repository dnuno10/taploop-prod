import 'package:flutter/material.dart';
import 'social_link_model.dart';
import 'contact_item_model.dart';

enum CardThemeStyle {
  white,
  dark,
  gradient,
  frosted,
  neon,
  premium,
  retro,
  custom,
}

CardThemeStyle _themeStyleFromString(String s) {
  switch (s) {
    case 'dark':
      return CardThemeStyle.dark;
    case 'gradient':
      return CardThemeStyle.gradient;
    case 'frosted':
      return CardThemeStyle.frosted;
    case 'neon':
      return CardThemeStyle.neon;
    case 'premium':
      return CardThemeStyle.premium;
    case 'retro':
      return CardThemeStyle.retro;
    case 'custom':
      return CardThemeStyle.custom;
    default:
      return CardThemeStyle.white;
  }
}

enum CardLayoutStyle { centered, leftAligned, compact, banner, minimal }

CardLayoutStyle _layoutStyleFromString(String s) {
  switch (s) {
    case 'leftAligned':
      return CardLayoutStyle.leftAligned;
    case 'compact':
      return CardLayoutStyle.compact;
    case 'banner':
      return CardLayoutStyle.banner;
    case 'minimal':
      return CardLayoutStyle.minimal;
    default:
      return CardLayoutStyle.centered;
  }
}

enum CardBgStyle { plain, gradient, mesh, stripes }

CardBgStyle _bgStyleFromString(String s) {
  switch (s) {
    case 'gradient':
      return CardBgStyle.gradient;
    case 'mesh':
      return CardBgStyle.mesh;
    case 'stripes':
      return CardBgStyle.stripes;
    default:
      return CardBgStyle.plain;
  }
}

class DigitalCardModel {
  final String id;
  final String? userId;
  final String? orgId;
  // Profile
  final String name;
  final String jobTitle;
  final String company;
  final String? profilePhotoUrl;
  final String? companyLogoUrl;
  final String? bio;
  // Design
  final CardThemeStyle themeStyle;
  final Color primaryColor;
  final Color? backgroundColorStart;
  final Color? backgroundColorEnd;
  final CardLayoutStyle layoutStyle;
  // Background
  final CardBgStyle bgStyle;
  final Color? bgColor;
  final Color? bgColorEnd;
  // Forms & Calendar
  final List<String> enabledForms;
  final bool calendarEnabled;
  final String? calendarUrl;
  // Contact
  final List<ContactItemModel> contactItems;
  // Social
  final List<SocialLinkModel> socialLinks;
  // Meta
  final String publicSlug;
  final bool isActive;
  final DateTime? deactivatedAt;
  final String? deactivationReason;
  final String? deactivatedBy;
  final DateTime? updatedAt;

  const DigitalCardModel({
    required this.id,
    this.userId,
    this.orgId,
    required this.name,
    required this.jobTitle,
    required this.company,
    this.profilePhotoUrl,
    this.companyLogoUrl,
    this.bio,
    this.themeStyle = CardThemeStyle.white,
    this.primaryColor = const Color(0xFFEF6820),
    this.backgroundColorStart,
    this.backgroundColorEnd,
    this.layoutStyle = CardLayoutStyle.centered,
    this.bgStyle = CardBgStyle.plain,
    this.bgColor,
    this.bgColorEnd,
    this.enabledForms = const [],
    this.calendarEnabled = false,
    this.calendarUrl,
    required this.contactItems,
    required this.socialLinks,
    required this.publicSlug,
    this.isActive = true,
    this.deactivatedAt,
    this.deactivationReason,
    this.deactivatedBy,
    this.updatedAt,
  });

  factory DigitalCardModel.fromJson(
    Map<String, dynamic> json, {
    List<ContactItemModel> contactItems = const [],
    List<SocialLinkModel> socialLinks = const [],
  }) {
    final primaryColorVal = (json['primary_color'] as num?)?.toInt();
    final bgColorVal = (json['bg_color'] as num?)?.toInt();
    final bgColorEndVal = (json['bg_color_end'] as num?)?.toInt();
    final bgColorStartVal = (json['background_color_start'] as num?)?.toInt();
    final bgColorEndDbVal = (json['background_color_end'] as num?)?.toInt();

    return DigitalCardModel(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      orgId: json['org_id'] as String?,
      name: json['name'] as String? ?? '',
      jobTitle: json['job_title'] as String? ?? '',
      company: json['company'] as String? ?? '',
      bio: json['bio'] as String?,
      publicSlug: json['public_slug'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      deactivatedAt: json['deactivated_at'] != null
          ? DateTime.tryParse(json['deactivated_at'] as String)
          : null,
      deactivationReason: json['deactivation_reason'] as String?,
      deactivatedBy: json['deactivated_by'] as String?,
      themeStyle: _themeStyleFromString(
        json['theme_style'] as String? ?? 'white',
      ),
      layoutStyle: _layoutStyleFromString(
        json['layout_style'] as String? ?? 'centered',
      ),
      primaryColor: Color(primaryColorVal ?? 0xFFEF6820),
      backgroundColorStart: bgColorStartVal != null
          ? Color(bgColorStartVal)
          : null,
      backgroundColorEnd: bgColorEndDbVal != null
          ? Color(bgColorEndDbVal)
          : null,
      bgStyle: _bgStyleFromString(json['bg_style'] as String? ?? 'plain'),
      bgColor: bgColorVal != null ? Color(bgColorVal) : null,
      bgColorEnd: bgColorEndVal != null ? Color(bgColorEndVal) : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      companyLogoUrl: json['company_logo_url'] as String?,
      enabledForms: (json['enabled_forms'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      calendarEnabled: json['calendar_enabled'] as bool? ?? false,
      calendarUrl: json['calendar_url'] as String?,
      contactItems: contactItems,
      socialLinks: socialLinks,
    );
  }

  /// Fields to upsert (excludes id, user_id, org_id — set those separately)
  Map<String, dynamic> toJson() => {
    'name': name,
    'job_title': jobTitle,
    'company': company,
    if (bio != null) 'bio': bio,
    'public_slug': publicSlug,
    'is_active': isActive,
    'deactivated_at': deactivatedAt?.toIso8601String(),
    'deactivation_reason': deactivationReason,
    'deactivated_by': deactivatedBy,
    'theme_style': themeStyle.name,
    'layout_style': layoutStyle.name,
    'primary_color': primaryColor.value,
    if (backgroundColorStart != null)
      'background_color_start': backgroundColorStart!.value,
    if (backgroundColorEnd != null)
      'background_color_end': backgroundColorEnd!.value,
    'bg_style': bgStyle.name,
    if (bgColor != null) 'bg_color': bgColor!.value,
    if (bgColorEnd != null) 'bg_color_end': bgColorEnd!.value,
    'enabled_forms': enabledForms,
    'calendar_enabled': calendarEnabled,
    if (calendarUrl != null) 'calendar_url': calendarUrl,
    if (profilePhotoUrl != null) 'profile_photo_url': profilePhotoUrl,
    if (companyLogoUrl != null) 'company_logo_url': companyLogoUrl,
  };

  String get publicUrl => 'https://taploop-software.vercel.app/$publicSlug';

  DigitalCardModel copyWith({
    String? id,
    String? userId,
    String? orgId,
    String? name,
    String? jobTitle,
    String? company,
    String? profilePhotoUrl,
    String? companyLogoUrl,
    String? bio,
    CardThemeStyle? themeStyle,
    Color? primaryColor,
    Color? backgroundColorStart,
    Color? backgroundColorEnd,
    CardLayoutStyle? layoutStyle,
    CardBgStyle? bgStyle,
    Color? bgColor,
    Color? bgColorEnd,
    List<String>? enabledForms,
    bool? calendarEnabled,
    String? calendarUrl,
    List<ContactItemModel>? contactItems,
    List<SocialLinkModel>? socialLinks,
    String? publicSlug,
    bool? isActive,
    DateTime? deactivatedAt,
    String? deactivationReason,
    String? deactivatedBy,
    DateTime? updatedAt,
  }) {
    return DigitalCardModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      companyLogoUrl: companyLogoUrl ?? this.companyLogoUrl,
      bio: bio ?? this.bio,
      themeStyle: themeStyle ?? this.themeStyle,
      primaryColor: primaryColor ?? this.primaryColor,
      backgroundColorStart: backgroundColorStart ?? this.backgroundColorStart,
      backgroundColorEnd: backgroundColorEnd ?? this.backgroundColorEnd,
      layoutStyle: layoutStyle ?? this.layoutStyle,
      bgStyle: bgStyle ?? this.bgStyle,
      bgColor: bgColor ?? this.bgColor,
      bgColorEnd: bgColorEnd ?? this.bgColorEnd,
      enabledForms: enabledForms ?? this.enabledForms,
      calendarEnabled: calendarEnabled ?? this.calendarEnabled,
      calendarUrl: calendarUrl ?? this.calendarUrl,
      contactItems: contactItems ?? this.contactItems,
      socialLinks: socialLinks ?? this.socialLinks,
      publicSlug: publicSlug ?? this.publicSlug,
      isActive: isActive ?? this.isActive,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      deactivationReason: deactivationReason ?? this.deactivationReason,
      deactivatedBy: deactivatedBy ?? this.deactivatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
