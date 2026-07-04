import 'package:supabase_flutter/supabase_flutter.dart';

const String _websiteBaseUrl = 'https://www.universidadedelideres.com.br';
const Duration _liveAfterEndGracePeriod = Duration(minutes: 30);
const Duration _defaultLiveDuration = Duration(hours: 1);

enum StudentLivePhase { scheduled, live, ended, cancelled }

class StudentLive {
  const StudentLive({
    required this.id,
    required this.title,
    required this.slug,
    required this.shortDescription,
    required this.description,
    required this.coverUrl,
    required this.startsAt,
    required this.endsAt,
    required this.presenterName,
    required this.requiredRank,
    required this.broadcastType,
    required this.liveUrl,
    required this.embedCode,
    required this.ctaLabel,
    required this.ctaUrl,
    required this.hasRecording,
    required this.recordingUrl,
    required this.sortOrder,
    required this.isFeatured,
    required this.isActive,
    required this.status,
    required this.zoomSdkEnabled,
    required this.zoomMeetingNumber,
    required this.zoomPasscode,
    required this.zoomRole,
    required this.zoomJoinMode,
  });

  final String id;
  final String title;
  final String slug;
  final String? shortDescription;
  final String? description;
  final String? coverUrl;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? presenterName;
  final int requiredRank;
  final String broadcastType;
  final String? liveUrl;
  final String? embedCode;
  final String? ctaLabel;
  final String? ctaUrl;
  final bool hasRecording;
  final String? recordingUrl;
  final int sortOrder;
  final bool isFeatured;
  final bool isActive;
  final String status;
  final bool zoomSdkEnabled;
  final String? zoomMeetingNumber;
  final String? zoomPasscode;
  final int zoomRole;
  final String? zoomJoinMode;

  DateTime? get automaticEndAt {
    final start = startsAt;

    if (start == null) return null;

    return endsAt ?? start.add(_defaultLiveDuration);
  }

  DateTime? get accessUntil {
    final end = automaticEndAt;

    if (end == null) return null;

    return end.add(_liveAfterEndGracePeriod);
  }

  StudentLivePhase phaseAt(DateTime moment) {
    final now = moment.toUtc();

    if (status.toLowerCase() == 'cancelled') {
      return StudentLivePhase.cancelled;
    }

    final start = startsAt;
    final end = automaticEndAt;

    if (start != null && now.isBefore(start.toUtc())) {
      return StudentLivePhase.scheduled;
    }

    if (end != null && now.isAfter(end.toUtc())) {
      return StudentLivePhase.ended;
    }

    return StudentLivePhase.live;
  }

  bool isVisibleAt(DateTime moment) {
    if (!isActive) return false;

    const visibleStatuses = {'scheduled', 'live', 'ended'};

    if (!visibleStatuses.contains(status.toLowerCase())) {
      return false;
    }

    final limit = accessUntil;

    return limit == null || !moment.toUtc().isAfter(limit.toUtc());
  }

  bool get isZoomSdkLive {
    return status.toLowerCase() == 'live' &&
        broadcastType.toLowerCase() == 'zoom' &&
        zoomSdkEnabled &&
        (zoomMeetingNumber?.replaceAll(RegExp(r'\s+'), '').isNotEmpty ?? false);
  }

  bool hasPlayableSourceAt(DateTime moment) {
    final phase = phaseAt(moment);

    if (phase == StudentLivePhase.live) {
      if (isZoomSdkLive) return true;
      if (broadcastType.toLowerCase() == 'zoom') return false;

      return (embedCode?.trim().isNotEmpty ?? false) ||
          (liveUrl?.trim().isNotEmpty ?? false);
    }

    if (phase == StudentLivePhase.ended) {
      return hasRecording && (recordingUrl?.trim().isNotEmpty ?? false);
    }

    return false;
  }

  String get displayDescription {
    return description ??
        shortDescription ??
        'Transmissão disponível na área do aluno.';
  }

  factory StudentLive.fromMap(
    Map<String, dynamic> row, {
    required String? Function(String? path) resolveCoverUrl,
  }) {
    return StudentLive(
      id: _text(row['id']) ?? '',
      title: _text(row['title']) ?? 'Live',
      slug: _text(row['slug']) ?? '',
      shortDescription: _text(row['short_description']),
      description: _text(row['description']),
      coverUrl: resolveCoverUrl(_text(row['cover_path'])),
      startsAt: _date(row['starts_at']),
      endsAt: _date(row['ends_at']),
      presenterName: _text(row['presenter_name']),
      requiredRank: _int(row['required_rank']),
      broadcastType: _text(row['broadcast_type']) ?? 'external_link',
      liveUrl: _text(row['live_url']),
      embedCode: _text(row['embed_code']),
      ctaLabel: _text(row['cta_label']),
      ctaUrl: _text(row['cta_url']),
      hasRecording: _bool(row['has_recording']),
      recordingUrl: _text(row['recording_url']),
      sortOrder: _int(row['sort_order']),
      isFeatured: _bool(row['is_featured']),
      isActive: _bool(row['is_active']),
      status: _text(row['status']) ?? 'scheduled',
      zoomSdkEnabled: _bool(row['zoom_sdk_enabled']),
      zoomMeetingNumber: _text(row['zoom_meeting_number']),
      zoomPasscode: _text(row['zoom_passcode']),
      zoomRole: _int(row['zoom_role']),
      zoomJoinMode: _text(row['zoom_join_mode']),
    );
  }
}

class StudentLiveRepository {
  StudentLiveRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _selectColumns =
      'id,title,slug,short_description,description,cover_path,starts_at,'
      'ends_at,presenter_name,required_rank,broadcast_type,live_url,'
      'embed_code,cta_label,cta_url,has_recording,recording_url,sort_order,'
      'is_featured,is_active,status,zoom_sdk_enabled,zoom_meeting_number,'
      'zoom_passcode,zoom_role,zoom_join_mode';

  Future<List<StudentLive>> loadVisibleLives() async {
    final dynamic response = await _client
        .from('lives')
        .select(_selectColumns)
        .eq('is_active', true)
        .inFilter('status', const ['scheduled', 'live', 'ended'])
        .order('sort_order', ascending: true)
        .order('starts_at', ascending: true);

    final now = DateTime.now().toUtc();

    return _rows(response)
        .map(
          (row) => StudentLive.fromMap(row, resolveCoverUrl: _resolveCoverUrl),
        )
        .where((live) => live.id.isNotEmpty && live.isVisibleAt(now))
        .toList()
      ..sort(_compareLives);
  }

  Future<StudentLive?> loadLiveById(String liveId) async {
    final cleanId = liveId.trim();

    if (cleanId.isEmpty) return null;

    final dynamic response = await _client
        .from('lives')
        .select(_selectColumns)
        .eq('id', cleanId)
        .eq('is_active', true)
        .maybeSingle();

    if (response is! Map) return null;

    final live = StudentLive.fromMap(
      Map<String, dynamic>.from(response),
      resolveCoverUrl: _resolveCoverUrl,
    );

    if (live.id.isEmpty || !live.isVisibleAt(DateTime.now().toUtc())) {
      return null;
    }

    return live;
  }

  static int _compareLives(StudentLive first, StudentLive second) {
    const statusWeight = {'live': 0, 'scheduled': 1, 'ended': 2};

    final firstWeight = statusWeight[first.status.toLowerCase()] ?? 9;
    final secondWeight = statusWeight[second.status.toLowerCase()] ?? 9;

    if (firstWeight != secondWeight) {
      return firstWeight.compareTo(secondWeight);
    }

    if (first.sortOrder != second.sortOrder) {
      return first.sortOrder.compareTo(second.sortOrder);
    }

    final firstStart = first.startsAt?.millisecondsSinceEpoch ?? 0;
    final secondStart = second.startsAt?.millisecondsSinceEpoch ?? 0;

    return firstStart.compareTo(secondStart);
  }

  String? _resolveCoverUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;

    final cleanPath = path.trim();

    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }

    var normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');

    if (normalized.startsWith('public/')) {
      normalized = normalized.replaceFirst('public/', '');
      return '$_websiteBaseUrl/$normalized';
    }

    if (normalized.startsWith('_next/')) {
      return '$_websiteBaseUrl/$normalized';
    }

    // Mantém o caminho exatamente como foi salvo pelo ADM no bucket `covers`.
    // Exemplo: `lives/capa-da-live.jpg` precisa continuar com o prefixo
    // `lives/`; removê-lo gera uma URL pública inexistente.
    if (normalized.startsWith('lives/') || normalized.startsWith('covers/')) {
      return _client.storage.from('covers').getPublicUrl(normalized);
    }

    normalized = normalized.replaceFirst('course-covers/', '');

    if (normalized.isEmpty) return null;

    return _client.storage.from('covers').getPublicUrl(normalized);
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}

String? _text(dynamic value) {
  final text = value?.toString().trim();

  if (text == null || text.isEmpty || text == 'null') return null;

  return text;
}

int _int(dynamic value) {
  if (value is int) return value;

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _bool(dynamic value) {
  return value == true || value?.toString().toLowerCase() == 'true';
}

DateTime? _date(dynamic value) {
  final text = _text(value);

  if (text == null) return null;

  return DateTime.tryParse(text)?.toUtc();
}
