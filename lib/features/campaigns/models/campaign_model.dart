import 'dart:convert';

enum CampaignStatus { active, upcoming, finished }

extension CampaignStatusExt on CampaignStatus {
  String get label {
    switch (this) {
      case CampaignStatus.active:
        return 'Activa';
      case CampaignStatus.upcoming:
        return 'Próxima';
      case CampaignStatus.finished:
        return 'Terminada';
    }
  }
}

enum CampaignObjective {
  awareness,
  leadGeneration,
  productLaunch,
  appointments,
  loyalty,
}

extension CampaignObjectiveExt on CampaignObjective {
  String get label {
    switch (this) {
      case CampaignObjective.awareness:
        return 'Brand awareness';
      case CampaignObjective.leadGeneration:
        return 'Generación de leads';
      case CampaignObjective.productLaunch:
        return 'Lanzamiento';
      case CampaignObjective.appointments:
        return 'Citas / demos';
      case CampaignObjective.loyalty:
        return 'Fidelización';
    }
  }
}

enum CampaignMemberRole { supervisor, executive, promoter }

extension CampaignMemberRoleExt on CampaignMemberRole {
  String get label {
    switch (this) {
      case CampaignMemberRole.supervisor:
        return 'Supervisor';
      case CampaignMemberRole.executive:
        return 'Ejecutivo';
      case CampaignMemberRole.promoter:
        return 'Promotor';
    }
  }
}

enum CampaignFieldType { text, email, phone, number, multiline }

extension CampaignFieldTypeExt on CampaignFieldType {
  String get label {
    switch (this) {
      case CampaignFieldType.text:
        return 'Texto';
      case CampaignFieldType.email:
        return 'Email';
      case CampaignFieldType.phone:
        return 'Teléfono';
      case CampaignFieldType.number:
        return 'Numérico';
      case CampaignFieldType.multiline:
        return 'Área de texto';
    }
  }
}

CampaignObjective? _objectiveFromString(String? value) {
  for (final objective in CampaignObjective.values) {
    if (objective.name == value) return objective;
  }
  return null;
}

CampaignFieldType _fieldTypeFromString(String? value) {
  for (final type in CampaignFieldType.values) {
    if (type.name == value) return type;
  }
  return CampaignFieldType.text;
}

class CampaignCaptureField {
  final String id;
  final String label;
  final CampaignFieldType type;
  final bool required;

  const CampaignCaptureField({
    required this.id,
    required this.label,
    this.type = CampaignFieldType.text,
    this.required = false,
  });

  factory CampaignCaptureField.fromJson(Map<String, dynamic> json) {
    return CampaignCaptureField(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: _fieldTypeFromString(json['type'] as String?),
      required: json['required'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'required': required,
  };

  CampaignCaptureField copyWith({
    String? id,
    String? label,
    CampaignFieldType? type,
    bool? required,
  }) {
    return CampaignCaptureField(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      required: required ?? this.required,
    );
  }
}

class CampaignMemberAssignment {
  final String userId;
  final String name;
  final String? jobTitle;
  final CampaignMemberRole? role;

  const CampaignMemberAssignment({
    required this.userId,
    required this.name,
    this.jobTitle,
    this.role,
  });

  CampaignMemberAssignment copyWith({
    String? userId,
    String? name,
    String? jobTitle,
    CampaignMemberRole? role,
  }) {
    return CampaignMemberAssignment(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      jobTitle: jobTitle ?? this.jobTitle,
      role: role ?? this.role,
    );
  }
}

class CampaignModel {
  final String id;
  final String? orgId;
  final String name;
  final String? eventType;
  final DateTime eventDate;
  final String location;
  final String? description;
  final CampaignStatus status;
  final int taps;
  final int leads;
  final int conversions;
  final List<String> assignedMemberNames;
  final String? zone;
  final String? startTime;
  final String? endTime;
  final int? durationMinutes;
  final String? shiftNotes;
  final CampaignObjective? objective;
  final int? leadGoal;
  final List<String> sourceChannels;
  final int interactionCount;
  final List<CampaignCaptureField> captureFields;
  final Map<String, String> memberRoles;

  const CampaignModel({
    required this.id,
    this.orgId,
    required this.name,
    this.eventType,
    required this.eventDate,
    required this.location,
    this.description,
    required this.status,
    required this.taps,
    required this.leads,
    required this.conversions,
    this.assignedMemberNames = const [],
    this.zone,
    this.startTime,
    this.endTime,
    this.durationMinutes,
    this.shiftNotes,
    this.objective,
    this.leadGoal,
    this.sourceChannels = const [],
    this.interactionCount = 0,
    this.captureFields = const [],
    this.memberRoles = const {},
  });

  factory CampaignModel.fromJson(Map<String, dynamic> json) {
    final parsedDescription = _parseDescriptionPayload(
      json['description'] as String?,
    );
    final startsAt = _parseTimestamp(json['starts_at']);
    final endsAt = _parseTimestamp(json['ends_at']);
    final derivedEventDate =
        startsAt ??
        (json['event_date'] != null
            ? DateTime.tryParse(json['event_date'] as String)
            : null) ??
        DateTime.now();
    return CampaignModel(
      id: json['id'] as String,
      orgId: json['org_id'] as String?,
      name: json['name'] as String? ?? '',
      eventType: json['event_type'] as String?,
      eventDate: DateTime(
        derivedEventDate.year,
        derivedEventDate.month,
        derivedEventDate.day,
      ),
      location: json['location'] as String? ?? 'Por definir',
      description: parsedDescription.description,
      status: _deriveCampaignStatus(startsAt, endsAt),
      taps: (json['taps'] as num?)?.toInt() ?? 0,
      leads: (json['leads'] as num?)?.toInt() ?? 0,
      conversions: (json['conversions'] as num?)?.toInt() ?? 0,
      zone: parsedDescription.zone,
      startTime: startsAt != null
          ? _formatTimeValue(startsAt)
          : parsedDescription.startTime,
      endTime: endsAt != null
          ? _formatTimeValue(endsAt)
          : parsedDescription.endTime,
      durationMinutes: parsedDescription.durationMinutes,
      shiftNotes: parsedDescription.shiftNotes,
      objective: parsedDescription.objective,
      leadGoal: parsedDescription.leadGoal,
      sourceChannels: parsedDescription.sourceChannels,
      interactionCount: parsedDescription.interactionCount,
      captureFields: parsedDescription.captureFields,
      memberRoles: parsedDescription.memberRoles,
    );
  }

  Map<String, dynamic> toJson({String? orgId}) => {
    if (orgId != null) 'org_id': orgId,
    'name': name,
    if (eventType != null) 'event_type': eventType,
    'event_date': eventDate.toIso8601String().substring(0, 10),
    'starts_at': _buildCampaignDateTime(
      eventDate,
      startTime,
    )?.toUtc().toIso8601String(),
    'ends_at': _buildCampaignDateTime(
      eventDate,
      endTime,
    )?.toUtc().toIso8601String(),
    'location': location,
    'description': _encodeDescriptionPayload(),
  };

  CampaignModel copyWith({
    String? id,
    String? orgId,
    String? name,
    String? eventType,
    DateTime? eventDate,
    String? location,
    String? description,
    CampaignStatus? status,
    int? taps,
    int? leads,
    int? conversions,
    List<String>? assignedMemberNames,
    String? zone,
    String? startTime,
    String? endTime,
    int? durationMinutes,
    String? shiftNotes,
    CampaignObjective? objective,
    int? leadGoal,
    List<String>? sourceChannels,
    int? interactionCount,
    List<CampaignCaptureField>? captureFields,
    Map<String, String>? memberRoles,
  }) {
    return CampaignModel(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      eventType: eventType ?? this.eventType,
      eventDate: eventDate ?? this.eventDate,
      location: location ?? this.location,
      description: description ?? this.description,
      status: status ?? this.status,
      taps: taps ?? this.taps,
      leads: leads ?? this.leads,
      conversions: conversions ?? this.conversions,
      assignedMemberNames: assignedMemberNames ?? this.assignedMemberNames,
      zone: zone ?? this.zone,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      shiftNotes: shiftNotes ?? this.shiftNotes,
      objective: objective ?? this.objective,
      leadGoal: leadGoal ?? this.leadGoal,
      sourceChannels: sourceChannels ?? this.sourceChannels,
      interactionCount: interactionCount ?? this.interactionCount,
      captureFields: captureFields ?? this.captureFields,
      memberRoles: memberRoles ?? this.memberRoles,
    );
  }

  double get conversionRate =>
      leads == 0 ? 0 : (conversions / leads).clamp(0.0, 1.0);

  String _encodeDescriptionPayload() {
    final hasExtendedData =
        zone != null ||
        startTime != null ||
        endTime != null ||
        durationMinutes != null ||
        shiftNotes != null ||
        objective != null ||
        leadGoal != null ||
        sourceChannels.isNotEmpty ||
        interactionCount > 0 ||
        captureFields.isNotEmpty ||
        memberRoles.isNotEmpty;

    if (!hasExtendedData) {
      return description ?? '';
    }

    return jsonEncode({
      'strategic_description': description,
      'zone': zone,
      'start_time': startTime,
      'end_time': endTime,
      'duration_minutes': durationMinutes,
      'shift_notes': shiftNotes,
      'objective': objective?.name,
      'lead_goal': leadGoal,
      'source_channels': sourceChannels,
      'interaction_count': interactionCount,
      'capture_fields': captureFields.map((field) => field.toJson()).toList(),
      'member_roles': memberRoles,
    });
  }
}

class _CampaignDescriptionPayload {
  final String? description;
  final String? zone;
  final String? startTime;
  final String? endTime;
  final int? durationMinutes;
  final String? shiftNotes;
  final CampaignObjective? objective;
  final int? leadGoal;
  final List<String> sourceChannels;
  final int interactionCount;
  final List<CampaignCaptureField> captureFields;
  final Map<String, String> memberRoles;

  const _CampaignDescriptionPayload({
    this.description,
    this.zone,
    this.startTime,
    this.endTime,
    this.durationMinutes,
    this.shiftNotes,
    this.objective,
    this.leadGoal,
    this.sourceChannels = const [],
    this.interactionCount = 0,
    this.captureFields = const [],
    this.memberRoles = const {},
  });
}

_CampaignDescriptionPayload _parseDescriptionPayload(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const _CampaignDescriptionPayload();
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return _CampaignDescriptionPayload(description: raw);
    }
    return _CampaignDescriptionPayload(
      description: decoded['strategic_description'] as String?,
      zone: decoded['zone'] as String?,
      startTime: decoded['start_time'] as String?,
      endTime: decoded['end_time'] as String?,
      durationMinutes: (decoded['duration_minutes'] as num?)?.toInt(),
      shiftNotes: decoded['shift_notes'] as String?,
      objective: _objectiveFromString(decoded['objective'] as String?),
      leadGoal: (decoded['lead_goal'] as num?)?.toInt(),
      sourceChannels: (decoded['source_channels'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      interactionCount: (decoded['interaction_count'] as num?)?.toInt() ?? 0,
      captureFields: (decoded['capture_fields'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CampaignCaptureField.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      memberRoles:
          (decoded['member_roles'] as Map<dynamic, dynamic>? ?? const {}).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
    );
  } catch (_) {
    return _CampaignDescriptionPayload(description: raw);
  }
}

DateTime? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

String _formatTimeValue(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

DateTime? _buildCampaignDateTime(DateTime date, String? time) {
  if (time == null || time.trim().isEmpty) return null;
  final parts = time.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

CampaignStatus _deriveCampaignStatus(DateTime? startsAt, DateTime? endsAt) {
  final now = DateTime.now();
  if (startsAt == null || endsAt == null) return CampaignStatus.upcoming;
  if (now.isBefore(startsAt)) return CampaignStatus.upcoming;
  if (now.isAfter(endsAt)) return CampaignStatus.finished;
  return CampaignStatus.active;
}
