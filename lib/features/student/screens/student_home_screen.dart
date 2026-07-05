// VERSÃO: v30
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/unl_colors.dart';
import '../live/screens/live_screen.dart';
import '../widgets/student_app_shell.dart';
import 'student_course_detail_screen.dart';
import 'student_lesson_screen.dart';
import 'student_trail_detail_screen.dart';

const Color _homeBackground = Color(0xFF050609);
const String _websiteBaseUrl = 'https://www.universidadedelideres.com.br';

/// Uma reunião deixa de ser exibida quatro horas após o seu término.
/// Quando o ADM não informar o término, o horário de início é usado
/// como referência, preservando a regra de quatro horas do agendamento.
const Duration _liveVisibilityGracePeriod = Duration(hours: 4);

enum _CardVariant { vertical, featured, horizontal }

class _StudentBanner {
  const _StudentBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.category,
    required this.duration,
    required this.level,
    required this.buttonLabel,
    required this.imageUrl,
    required this.mobileImageUrl,
    required this.targetUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String category;
  final String duration;
  final String level;
  final String buttonLabel;
  final String? imageUrl;
  final String? mobileImageUrl;
  final String? targetUrl;
}

class _StudentHomeSection {
  const _StudentHomeSection({
    required this.id,
    required this.title,
    required this.variant,
    required this.items,
  });

  final String id;
  final String title;
  final _CardVariant variant;
  final List<_StudentHomeItem> items;
}

class _StudentHomeItem {
  const _StudentHomeItem({
    required this.id,
    required this.contentId,
    required this.contentType,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.duration,
    required this.level,
    required this.badge,
    required this.imageUrl,
    required this.targetUrl,
  });

  final String id;
  final String contentId;
  final String contentType;
  final String title;
  final String subtitle;
  final String category;
  final String duration;
  final String level;
  final String? badge;
  final String? imageUrl;
  final String targetUrl;
}

class _ContinueWatchingItem {
  const _ContinueWatchingItem({
    required this.id,
    required this.lessonId,
    required this.courseId,
    required this.title,
    required this.lessonLabel,
    required this.progress,
    required this.imageUrl,
  });

  final String id;
  final String lessonId;
  final String courseId;
  final String title;
  final String lessonLabel;
  final double progress;
  final String? imageUrl;
}

class _CardSize {
  const _CardSize({required this.width, required this.height});

  final double width;
  final double height;
}

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  static const String routeName = '/student-home';

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final PageController _heroController = PageController();
  final ScrollController _scrollController = ScrollController();

  Timer? _heroTimer;

  bool _isLoading = true;
  String? _loadError;
  int _activeHeroIndex = 0;

  List<_StudentBanner> _banners = const [];
  List<_ContinueWatchingItem> _continueWatching = const [];
  List<_StudentHomeSection> _sections = const [];

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHome();
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final banners = await _loadBanners();
      final sections = await _loadSections();
      final continueWatching = await _loadContinueWatching();

      if (!mounted) return;

      setState(() {
        _banners = banners;
        _continueWatching = continueWatching;
        _sections = sections;
        _activeHeroIndex = 0;
        _isLoading = false;
      });

      if (_heroController.hasClients) {
        _heroController.jumpToPage(0);
      }

      _startHeroTimer();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar os conteúdos da área do aluno.';
      });
    }
  }

  Future<List<_StudentBanner>> _loadBanners() async {
    final dynamic response = await _supabase
        .from('student_banners')
        .select(
          'id,title,subtitle,badge,category,duration,level_name,'
          'button_label,image_url,mobile_image_url,target_url,'
          'sort_order,is_active',
        )
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);

    return _rows(response)
        .map(
          (row) => _StudentBanner(
            id: _text(row['id']) ?? '',
            title: _text(row['title']) ?? 'Conteúdo em destaque',
            subtitle: _text(row['subtitle']) ?? '',
            badge: _text(row['badge']) ?? 'Em destaque',
            category: _text(row['category']) ?? 'Conteúdo',
            duration: _text(row['duration']) ?? '',
            level: _text(row['level_name']) ?? 'Disponível',
            buttonLabel: _text(row['button_label']) ?? 'Assistir agora',
            imageUrl: _resolveAssetUrl(_text(row['image_url'])),
            mobileImageUrl: _resolveAssetUrl(_text(row['mobile_image_url'])),
            targetUrl: _text(row['target_url']),
          ),
        )
        .where((banner) => banner.id.isNotEmpty)
        .toList();
  }

  Future<List<_StudentHomeSection>> _loadSections() async {
    final dynamic sectionsResponse = await _supabase
        .from('student_home_sections')
        .select('id,title,slug,description,layout_variant,sort_order,is_active')
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    final sectionRows = _rows(sectionsResponse);

    if (sectionRows.isEmpty) return const [];

    final sectionIds = sectionRows
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toList();

    if (sectionIds.isEmpty) return const [];

    final dynamic itemsResponse = await _supabase
        .from('student_home_section_items')
        .select(
          'id,section_id,content_type,content_id,title_override,'
          'subtitle_override,badge_override,image_url_override,'
          'target_url_override,sort_order,is_active',
        )
        .inFilter('section_id', sectionIds)
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    final sectionItemRows = _rows(itemsResponse);

    if (sectionItemRows.isEmpty) return const [];

    final trailIds = _collectContentIds(sectionItemRows, 'trail');
    final courseIds = _collectContentIds(sectionItemRows, 'course');
    final lessonIds = _collectContentIds(sectionItemRows, 'lesson');
    final liveIds = _collectContentIds(sectionItemRows, 'live');

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _fetchRowsByIds(
        table: 'course_categories',
        ids: trailIds,
        columns:
            'id,title,slug,description,cover_path,cover_vertical_path,'
            'cover_horizontal_path,cover_featured_path,is_featured',
      ),
      _fetchRowsByIds(
        table: 'courses',
        ids: courseIds,
        columns:
            'id,slug,title,short_description,description,cover_path,'
            'cover_vertical_path,cover_horizontal_path,cover_featured_path,'
            'is_featured',
      ),
      _fetchRowsByIds(
        table: 'lessons',
        ids: lessonIds,
        columns:
            'id,module_id,title,description,status,content_type,'
            'duration_sec,primary_asset_path,scheduled_start_at',
      ),
      _fetchRowsByIds(
        table: 'lives',
        ids: liveIds,
        columns:
            'id,slug,title,short_description,description,cover_path,'
            'starts_at,ends_at,presenter_name,status,is_featured,is_active',
      ),
    ]);

    final trailsById = _rowsById(results[0]);
    final coursesById = _rowsById(results[1]);
    final lessonsById = _rowsById(results[2]);
    final livesById = _rowsById(results[3]);

    final builtSections = <_StudentHomeSection>[];

    for (final sectionRow in sectionRows) {
      final sectionId = _text(sectionRow['id']);

      if (sectionId == null) continue;

      final variant = _parseVariant(_text(sectionRow['layout_variant']));
      final items = <_StudentHomeItem>[];

      final currentSectionItems = sectionItemRows.where(
        (item) => _text(item['section_id']) == sectionId,
      );

      for (final linkRow in currentSectionItems) {
        final item = _mapHomeItem(
          linkRow: linkRow,
          variant: variant,
          trailsById: trailsById,
          coursesById: coursesById,
          lessonsById: lessonsById,
          livesById: livesById,
        );

        if (item != null) {
          items.add(item);
        }
      }

      if (items.isNotEmpty) {
        builtSections.add(
          _StudentHomeSection(
            id: sectionId,
            title: _text(sectionRow['title']) ?? 'Conteúdos',
            variant: variant,
            items: items,
          ),
        );
      }
    }

    return builtSections;
  }

  Future<List<_ContinueWatchingItem>> _loadContinueWatching() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return const [];

    try {
      final dynamic progressResponse = await _supabase
          .from('lesson_progress')
          .select(
            'id,lesson_id,student_id,progress_seconds,completed_at,'
            'last_watched_at,updated_at',
          )
          .eq('student_id', user.id)
          .not('last_watched_at', 'is', null)
          .order('last_watched_at', ascending: false)
          .limit(80);

      final progressRows = _rows(progressResponse)
        ..sort((first, second) {
          final firstDate = _continueWatchingDate(first);
          final secondDate = _continueWatchingDate(second);

          return secondDate.compareTo(firstDate);
        });

      final lessonIds = progressRows
          .map((row) => _text(row['lesson_id']))
          .whereType<String>()
          .toSet()
          .toList();

      if (lessonIds.isEmpty) return const [];

      final dynamic lessonsResponse = await _supabase
          .from('lessons')
          .select(
            'id,module_id,title,description,duration_sec,sort_order,status',
          )
          .inFilter('id', lessonIds)
          .eq('status', 'published');

      final lessonsById = _rowsById(_rows(lessonsResponse));

      final moduleIds = lessonsById.values
          .map((lesson) => _text(lesson['module_id']))
          .whereType<String>()
          .toSet()
          .toList();

      if (moduleIds.isEmpty) return const [];

      final dynamic modulesResponse = await _supabase
          .from('course_modules')
          .select('id,course_id,title,sort_order')
          .inFilter('id', moduleIds);

      final modulesById = _rowsById(_rows(modulesResponse));

      final courseIds = modulesById.values
          .map((module) => _text(module['course_id']))
          .whereType<String>()
          .toSet()
          .toList();

      if (courseIds.isEmpty) return const [];

      final dynamic coursesResponse = await _supabase
          .from('courses')
          .select(
            'id,slug,title,short_description,description,cover_path,'
            'cover_vertical_path,cover_horizontal_path,cover_featured_path,'
            'preferred_card_format',
          )
          .inFilter('id', courseIds);

      final coursesById = _rowsById(_rows(coursesResponse));
      final seenCourseIds = <String>{};
      final items = <_ContinueWatchingItem>[];

      for (final progressRow in progressRows) {
        final lessonId = _text(progressRow['lesson_id']);
        if (lessonId == null) continue;

        final lesson = lessonsById[lessonId];
        if (lesson == null) continue;

        final moduleId = _text(lesson['module_id']);
        if (moduleId == null) continue;

        final module = modulesById[moduleId];
        if (module == null) continue;

        final courseId = _text(module['course_id']);
        if (courseId == null) continue;

        final course = coursesById[courseId];
        if (course == null || seenCourseIds.contains(courseId)) continue;

        seenCourseIds.add(courseId);

        final coverPath =
            _text(course['cover_featured_path']) ??
            _text(course['cover_vertical_path']) ??
            _text(course['cover_horizontal_path']) ??
            _text(course['cover_path']);

        items.add(
          _ContinueWatchingItem(
            id: '$courseId-$lessonId',
            lessonId: lessonId,
            courseId: courseId,
            title: _text(course['title']) ?? 'Curso sem título',
            lessonLabel: _continueWatchingLessonLabel(lesson),
            progress: _continueWatchingProgress(
              progressRow: progressRow,
              lesson: lesson,
            ),
            imageUrl: _resolveAssetUrl(coverPath),
          ),
        );

        if (items.length >= 12) break;
      }

      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRowsByIds({
    required String table,
    required List<String> ids,
    required String columns,
  }) async {
    if (ids.isEmpty) return const [];

    final dynamic response = await _supabase
        .from(table)
        .select(columns)
        .inFilter('id', ids);

    return _rows(response);
  }

  _StudentHomeItem? _mapHomeItem({
    required Map<String, dynamic> linkRow,
    required _CardVariant variant,
    required Map<String, Map<String, dynamic>> trailsById,
    required Map<String, Map<String, dynamic>> coursesById,
    required Map<String, Map<String, dynamic>> lessonsById,
    required Map<String, Map<String, dynamic>> livesById,
  }) {
    final contentType = (_text(linkRow['content_type']) ?? '').toLowerCase();
    final contentId = _text(linkRow['content_id']);

    if (contentType.isEmpty || contentId == null) return null;

    final titleOverride = _text(linkRow['title_override']);
    final subtitleOverride = _text(linkRow['subtitle_override']);
    final badgeOverride = _text(linkRow['badge_override']);
    final imageOverride = _text(linkRow['image_url_override']);
    final targetOverride = _text(linkRow['target_url_override']);

    if (contentType == 'trail') {
      final trail = trailsById[contentId];

      if (trail == null) return null;

      final slug = _text(trail['slug']);

      return _StudentHomeItem(
        id: _text(linkRow['id']) ?? contentId,
        contentId: contentId,
        contentType: contentType,
        title: titleOverride ?? _text(trail['title']) ?? 'Trilha',
        subtitle:
            subtitleOverride ??
            _text(trail['description']) ??
            'Acesse os conteúdos desta trilha e continue sua jornada.',
        category: 'Trilha',
        duration: _isTrue(trail['is_featured'])
            ? 'Em destaque'
            : 'Conteúdo liberado',
        level: 'Disponível para você',
        badge:
            badgeOverride ??
            (_isTrue(trail['is_featured']) ? 'Destaque' : null),
        imageUrl: _resolveAssetUrl(
          imageOverride ?? _selectCover(trail, variant),
        ),
        targetUrl: targetOverride ?? '/aluno/trilhas/${slug ?? contentId}',
      );
    }

    if (contentType == 'course') {
      final course = coursesById[contentId];

      if (course == null) return null;

      final slug = _text(course['slug']);

      return _StudentHomeItem(
        id: _text(linkRow['id']) ?? contentId,
        contentId: contentId,
        contentType: contentType,
        title: titleOverride ?? _text(course['title']) ?? 'Curso',
        subtitle:
            subtitleOverride ??
            _text(course['short_description']) ??
            _text(course['description']) ??
            'Acesse este conteúdo e continue sua evolução.',
        category: 'Curso',
        duration: _isTrue(course['is_featured'])
            ? 'Em destaque'
            : 'Conteúdo liberado',
        level: 'Disponível para você',
        badge:
            badgeOverride ??
            (_isTrue(course['is_featured']) ? 'Destaque' : null),
        imageUrl: _resolveAssetUrl(
          imageOverride ?? _selectCover(course, variant),
        ),
        targetUrl: targetOverride ?? '/aluno/cursos/${slug ?? contentId}',
      );
    }

    if (contentType == 'live') {
      final live = livesById[contentId];

      if (live == null || !_isLiveAvailableForDisplay(live)) return null;

      final isLive = (_text(live['status']) ?? '').toLowerCase() == 'live';

      return _StudentHomeItem(
        id: _text(linkRow['id']) ?? contentId,
        contentId: contentId,
        contentType: contentType,
        title: titleOverride ?? _text(live['title']) ?? 'Live',
        subtitle:
            subtitleOverride ??
            _text(live['short_description']) ??
            _text(live['description']) ??
            'Acompanhe esta transmissão ao vivo.',
        category: 'Live',
        duration: isLive ? 'Ao vivo' : 'Agendada',
        level: _text(live['presenter_name']) != null
            ? 'Com ${_text(live['presenter_name'])}'
            : 'Transmissão',
        badge:
            badgeOverride ??
            (isLive
                ? 'Ao vivo'
                : _isTrue(live['is_featured'])
                ? 'Destaque'
                : 'Live'),
        imageUrl: _resolveAssetUrl(imageOverride ?? _text(live['cover_path'])),
        targetUrl: targetOverride ?? '/aluno/ao-vivo?live=$contentId',
      );
    }

    if (contentType == 'lesson') {
      final lesson = lessonsById[contentId];

      if (lesson == null) return null;

      return _StudentHomeItem(
        id: _text(linkRow['id']) ?? contentId,
        contentId: contentId,
        contentType: contentType,
        title: titleOverride ?? _text(lesson['title']) ?? 'Aula',
        subtitle:
            subtitleOverride ??
            _text(lesson['description']) ??
            'Conteúdo disponível para você.',
        category: 'Aula',
        duration: _formatDuration(lesson['duration_sec']),
        level: 'Aula liberada',
        badge: badgeOverride,
        imageUrl: _resolveAssetUrl(
          imageOverride ?? _text(lesson['primary_asset_path']),
        ),
        targetUrl: targetOverride ?? '/aluno/aulas/$contentId',
      );
    }

    return null;
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();

    if (_banners.length <= 1) return;

    _heroTimer = Timer.periodic(const Duration(milliseconds: 6500), (_) {
      if (!mounted || !_heroController.hasClients || _banners.isEmpty) return;

      final nextIndex = (_activeHeroIndex + 1) % _banners.length;

      _heroController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openBanner(_StudentBanner banner) async {
    final targetUrl = banner.targetUrl;

    if (targetUrl == null || targetUrl.trim().isEmpty) {
      _showNavigationMessage(
        'Este destaque ainda não possui um destino configurado no ADM.',
      );
      return;
    }

    // O ADM de banners seleciona um curso, mas as versões já cadastradas
    // gravam esse destino no formato legado /aluno/trilhas/{slug-ou-id}.
    // Resolve o curso antes do roteador geral para que todos os banners
    // existentes e os novos abram o conteúdo correto no app.
    final openedLegacyCourseTarget = await _openLegacyBannerCourseTarget(
      targetUrl,
    );

    if (openedLegacyCourseTarget) {
      return;
    }

    await _openConfiguredTarget(targetUrl);
  }

  Future<bool> _openLegacyBannerCourseTarget(String rawTarget) async {
    final uri = _parseConfiguredTarget(rawTarget);

    if (uri == null || !_isInternalStudentUri(uri)) {
      return false;
    }

    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .map((segment) => segment.trim())
        .toList(growable: false);

    final alunoIndex = segments.indexWhere(
      (segment) => segment.toLowerCase() == 'aluno',
    );
    final destinationIndex = alunoIndex >= 0 ? alunoIndex + 1 : 0;

    if (destinationIndex >= segments.length) {
      return false;
    }

    final destination = segments[destinationIndex].toLowerCase();

    final isLegacyTrailPath =
        destination == 'trilhas' ||
        destination == 'trilha' ||
        destination == 'trails' ||
        destination == 'trail';

    if (!isLegacyTrailPath) {
      return false;
    }

    final reference =
        _queryValue(uri, const [
          'course',
          'courseId',
          'course_id',
          'id',
          'slug',
        ]) ??
        (segments.length > destinationIndex + 1
            ? segments[destinationIndex + 1]
            : '');

    if (reference.isEmpty) {
      return false;
    }

    return _openContentReference(contentType: 'course', reference: reference);
  }

  Future<void> _openHomeItem(_StudentHomeItem item) async {
    await _openConfiguredTarget(
      item.targetUrl,
      fallbackContentType: item.contentType,
      fallbackContentId: item.contentId,
    );
  }

  Future<void> _openContinueWatchingItem(_ContinueWatchingItem item) async {
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentLessonScreen(lessonId: item.lessonId),
      ),
    );
  }

  Future<void> _openSectionDestination(_StudentHomeSection section) async {
    final contentTypes = section.items
        .map((item) => _normalizeContentType(item.contentType))
        .where((type) => type.isNotEmpty)
        .toSet();

    if (contentTypes.length != 1) {
      _showNavigationMessage(
        'Esta seção reúne conteúdos de áreas diferentes. Escolha um conteúdo para abrir.',
      );
      return;
    }

    final contentType = contentTypes.single;

    switch (contentType) {
      case 'trail':
        _navigateToGlobalArea(StudentAppRoutes.trails);
        return;
      case 'course':
      case 'lesson':
        _navigateToGlobalArea(StudentAppRoutes.courses);
        return;
      case 'live':
        _navigateToGlobalArea(StudentAppRoutes.live);
        return;
      case 'community':
        _navigateToGlobalArea(StudentAppRoutes.community);
        return;
      case 'gamification':
        _navigateToGlobalArea(StudentAppRoutes.gamification);
        return;
      default:
        _showNavigationMessage(
          'Esta seção ainda não possui uma área de destino disponível no aplicativo.',
        );
    }
  }

  Future<void> _openConfiguredTarget(
    String? rawTarget, {
    String? fallbackContentType,
    String? fallbackContentId,
  }) async {
    final target = rawTarget?.trim() ?? '';

    if (target.isNotEmpty) {
      final uri = _parseConfiguredTarget(target);

      if (uri != null && _isInternalStudentUri(uri)) {
        final opened = await _openInternalStudentUri(uri);
        if (opened) return;

        final recovered = await _openInternalReferenceFallback(uri);
        if (recovered) return;
      } else if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http')) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched) {
          _showNavigationMessage('Não foi possível abrir este destino agora.');
        }
        return;
      }
    }

    final contentType = _normalizeContentType(fallbackContentType ?? '');
    final contentId = fallbackContentId?.trim() ?? '';

    if (contentType.isNotEmpty && contentId.isNotEmpty) {
      final opened = await _openContentByType(
        contentType: contentType,
        contentId: contentId,
      );

      if (opened) return;
    }

    _showNavigationMessage(
      'Este conteúdo ainda não possui um destino válido configurado no ADM.',
    );
  }

  Uri? _parseConfiguredTarget(String rawTarget) {
    final target = rawTarget.trim();

    if (target.isEmpty) return null;

    final directUri = Uri.tryParse(target);

    if (directUri != null &&
        directUri.fragment.isNotEmpty &&
        directUri.fragment.toLowerCase().contains('aluno')) {
      final fragment = directUri.fragment.startsWith('/')
          ? directUri.fragment
          : '/${directUri.fragment}';

      final fragmentUri = Uri.tryParse(fragment);
      if (fragmentUri != null) {
        return fragmentUri;
      }
    }

    if (directUri != null && directUri.scheme.isNotEmpty) {
      return directUri;
    }

    if (target.startsWith('www.universidadedelideres.com.br/') ||
        target.startsWith('universidadedelideres.com.br/')) {
      return Uri.tryParse('https://$target');
    }

    return directUri;
  }

  bool _isInternalStudentUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase().replaceFirst(RegExp(r'^/+'), '');

    final isWebsiteHost =
        host.isEmpty ||
        host == 'universidadedelideres.com.br' ||
        host == 'www.universidadedelideres.com.br';

    if (!isWebsiteHost) return false;

    final root = path
        .split('/')
        .firstWhere((segment) => segment.trim().isNotEmpty, orElse: () => '');

    return root == 'aluno' ||
        _normalizeContentType(root).isNotEmpty ||
        root == 'conteudo' ||
        root == 'conteudos' ||
        root == 'content';
  }

  Future<bool> _openInternalStudentUri(Uri uri) async {
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .map((segment) => segment.trim())
        .toList(growable: false);

    final alunoIndex = segments.indexWhere(
      (segment) => segment.toLowerCase() == 'aluno',
    );
    final destinationIndex = alunoIndex >= 0 ? alunoIndex + 1 : 0;

    if (destinationIndex >= segments.length) {
      final queryType = _normalizeContentType(
        _queryValue(uri, const [
              'contentType',
              'content_type',
              'type',
              'destination',
            ]) ??
            '',
      );
      final queryReference = _queryValue(uri, const [
        'contentId',
        'content_id',
        'id',
        'slug',
        'reference',
      ]);

      if (queryType.isNotEmpty && queryReference != null) {
        return _openContentReference(
          contentType: queryType,
          reference: queryReference,
        );
      }

      return false;
    }

    final destination = segments[destinationIndex].toLowerCase();
    final pathReference = segments.length > destinationIndex + 1
        ? segments[destinationIndex + 1]
        : '';

    switch (destination) {
      case 'trilhas':
      case 'trilha':
      case 'trails':
      case 'trail':
        final reference =
            _queryValue(uri, const [
              'trail',
              'trailId',
              'trail_id',
              'id',
              'slug',
            ]) ??
            pathReference;

        if (reference.isEmpty) {
          _navigateToGlobalArea(StudentAppRoutes.trails);
          return true;
        }

        return _openContentReference(
          contentType: 'trail',
          reference: reference,
        );
      case 'cursos':
      case 'curso':
      case 'courses':
      case 'course':
        final reference =
            _queryValue(uri, const [
              'course',
              'courseId',
              'course_id',
              'id',
              'slug',
            ]) ??
            pathReference;

        if (reference.isEmpty) {
          _navigateToGlobalArea(StudentAppRoutes.courses);
          return true;
        }

        return _openContentReference(
          contentType: 'course',
          reference: reference,
        );
      case 'aulas':
      case 'aula':
      case 'lessons':
      case 'lesson':
        final reference =
            _queryValue(uri, const ['lesson', 'lessonId', 'lesson_id', 'id']) ??
            pathReference;

        if (reference.isEmpty) {
          _navigateToGlobalArea(StudentAppRoutes.courses);
          return true;
        }

        return _openContentByType(contentType: 'lesson', contentId: reference);
      case 'ao-vivo':
      case 'ao_vivo':
      case 'aovivo':
      case 'lives':
      case 'live':
        final reference =
            _queryValue(uri, const [
              'live',
              'liveId',
              'live_id',
              'id',
              'slug',
            ]) ??
            pathReference;

        if (reference.isEmpty) {
          _navigateToGlobalArea(StudentAppRoutes.live);
          return true;
        }

        return _openContentReference(contentType: 'live', reference: reference);
      case 'comunidade':
      case 'community':
        _navigateToGlobalArea(StudentAppRoutes.community);
        return true;
      case 'gamificacao':
      case 'gamification':
        _navigateToGlobalArea(StudentAppRoutes.gamification);
        return true;
      case 'conteudo':
      case 'conteudos':
      case 'content':
        final contentType = _normalizeContentType(
          _queryValue(uri, const ['contentType', 'content_type', 'type']) ?? '',
        );
        final contentReference = _queryValue(uri, const [
          'contentId',
          'content_id',
          'id',
          'slug',
          'reference',
        ]);

        if (contentType.isEmpty || contentReference == null) {
          return false;
        }

        return _openContentReference(
          contentType: contentType,
          reference: contentReference,
        );
      default:
        return false;
    }
  }

  String? _queryValue(Uri uri, List<String> keys) {
    for (final key in keys) {
      final value = uri.queryParameters[key]?.trim();

      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  Future<bool> _openInternalReferenceFallback(Uri uri) async {
    final candidates = <String>{
      ...uri.queryParameters.values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
      ...uri.pathSegments.map((value) => value.trim()).where((value) {
        final normalized = value.toLowerCase();
        return value.isNotEmpty &&
            normalized != 'aluno' &&
            _normalizeContentType(normalized).isEmpty &&
            normalized != 'conteudo' &&
            normalized != 'conteudos' &&
            normalized != 'content';
      }),
    };

    for (final candidate in candidates) {
      final opened = await _openAnyContentReference(candidate);
      if (opened) return true;
    }

    return false;
  }

  Future<bool> _openAnyContentReference(String reference) async {
    final cleanReference = reference.trim();

    if (cleanReference.isEmpty) return false;

    if (_isUuid(cleanReference)) {
      const candidates = <({String table, String contentType})>[
        (table: 'lessons', contentType: 'lesson'),
        (table: 'courses', contentType: 'course'),
        (table: 'course_categories', contentType: 'trail'),
        (table: 'lives', contentType: 'live'),
      ];

      for (final candidate in candidates) {
        try {
          final dynamic response = await _supabase
              .from(candidate.table)
              .select('id')
              .eq('id', cleanReference)
              .maybeSingle();

          if (response is Map && _text(response['id']) != null) {
            return _openContentByType(
              contentType: candidate.contentType,
              contentId: cleanReference,
            );
          }
        } catch (_) {
          // Tenta o próximo tipo de conteúdo.
        }
      }

      return false;
    }

    const candidates = <({String table, String contentType})>[
      (table: 'courses', contentType: 'course'),
      (table: 'course_categories', contentType: 'trail'),
      (table: 'lives', contentType: 'live'),
    ];

    for (final candidate in candidates) {
      try {
        final dynamic response = await _supabase
            .from(candidate.table)
            .select('id')
            .eq('slug', cleanReference)
            .maybeSingle();

        final id = response is Map ? _text(response['id']) : null;

        if (id != null) {
          return _openContentByType(
            contentType: candidate.contentType,
            contentId: id,
          );
        }
      } catch (_) {
        // Tenta o próximo tipo de conteúdo.
      }
    }

    return false;
  }

  Future<bool> _openContentReference({
    required String contentType,
    required String reference,
  }) async {
    final normalizedType = _normalizeContentType(contentType);
    final cleanReference = reference.trim();

    if (normalizedType.isEmpty || cleanReference.isEmpty) {
      return false;
    }

    if (normalizedType == 'lesson' || _isUuid(cleanReference)) {
      return _openContentByType(
        contentType: normalizedType,
        contentId: cleanReference,
      );
    }

    final table = switch (normalizedType) {
      'trail' => 'course_categories',
      'course' => 'courses',
      'live' => 'lives',
      _ => '',
    };

    if (table.isEmpty) {
      return false;
    }

    try {
      final dynamic response = await _supabase
          .from(table)
          .select('id')
          .eq('slug', cleanReference)
          .maybeSingle();

      if (response is! Map) {
        return false;
      }

      final resolvedId = _text(response['id']);

      if (resolvedId == null) {
        return false;
      }

      return _openContentByType(
        contentType: normalizedType,
        contentId: resolvedId,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openContentByType({
    required String contentType,
    required String contentId,
  }) async {
    if (!mounted) return false;

    switch (_normalizeContentType(contentType)) {
      case 'trail':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StudentTrailDetailScreen(trailId: contentId),
          ),
        );
        return true;
      case 'course':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StudentCourseDetailScreen(courseId: contentId),
          ),
        );
        return true;
      case 'lesson':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StudentLessonScreen(lessonId: contentId),
          ),
        );
        return true;
      case 'live':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LiveScreen(initialLiveId: contentId),
          ),
        );
        return true;
      case 'community':
        _navigateToGlobalArea(StudentAppRoutes.community);
        return true;
      case 'gamification':
        _navigateToGlobalArea(StudentAppRoutes.gamification);
        return true;
      default:
        return false;
    }
  }

  void _navigateToGlobalArea(String routeName) {
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(routeName, (route) => false);
  }

  String _normalizeContentType(String value) {
    switch (value.trim().toLowerCase()) {
      case 'trail':
      case 'trilha':
      case 'trails':
      case 'trilhas':
        return 'trail';
      case 'course':
      case 'curso':
      case 'courses':
      case 'cursos':
        return 'course';
      case 'lesson':
      case 'aula':
      case 'lessons':
      case 'aulas':
        return 'lesson';
      case 'live':
      case 'lives':
      case 'ao-vivo':
      case 'ao_vivo':
      case 'aovivo':
        return 'live';
      case 'community':
      case 'comunidade':
        return 'community';
      case 'gamification':
      case 'gamificacao':
        return 'gamification';
      default:
        return '';
    }
  }

  bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  void _showNavigationMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF181A20),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.home,
      scrollController: _scrollController,
      backgroundColor: _homeBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: const Color(0xFF191A20),
        onRefresh: _loadHome,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildHero()),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingContent())
            else ...[
              if (_loadError != null)
                SliverToBoxAdapter(child: _buildErrorCard()),
              if (_continueWatching.isNotEmpty)
                SliverToBoxAdapter(child: _buildContinueWatchingSection()),
              for (final section in _sections)
                SliverToBoxAdapter(child: _buildContentSection(section)),
              if (_sections.isEmpty && _loadError == null)
                SliverToBoxAdapter(child: _buildEmptyContent()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    if (_isLoading) {
      return _buildHeroSkeleton();
    }

    if (_banners.isEmpty) {
      return _buildHeroEmptyState();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;

    // A arte mobile é cadastrada em 1080 × 1350 (proporção 4:5).
    // Mantemos a mesma proporção no contêiner para evitar zoom, corte
    // e qualquer deformação do criativo mobile.
    final heroHeight = screenWidth * (1350 / 1080);

    return SizedBox(
      height: heroHeight,
      child: Stack(
        children: [
          PageView.builder(
            controller: _heroController,
            itemCount: _banners.length,
            onPageChanged: (index) {
              if (!mounted) return;

              setState(() {
                _activeHeroIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildHeroSlide(
                banner: _banners[index],
                heroHeight: heroHeight,
              );
            },
          ),
          if (_banners.length > 1)
            Positioned(
              right: 22,
              bottom: 24,
              child: Row(
                children: List.generate(_banners.length, (index) {
                  final active = index == _activeHeroIndex;

                  return GestureDetector(
                    onTap: () {
                      _heroController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: active ? 22 : 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.40),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSlide({
    required _StudentBanner banner,
    required double heroHeight,
  }) {
    // No aplicativo, a arte mobile é prioritária. A imagem desktop só é
    // usada como contingência quando o banner ainda não possuir uma arte mobile.
    final mobileImageUrl = banner.mobileImageUrl;
    final imageUrl = mobileImageUrl != null && mobileImageUrl.trim().isNotEmpty
        ? mobileImageUrl
        : banner.imageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null)
          Image.network(
            imageUrl,
            // Como o Hero usa exatamente 4:5, o cover mantém a arte 1080 × 1350
            // inteira, sem esticar e sem ampliar além da proporção original.
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildHeroBackgroundFallback(),
          )
        else
          _buildHeroBackgroundFallback(),

        // Degradê duplo igual ao Hero da live:
        // topo preto sólido até 10%, centro transparente e base preta suave.
        const Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF050609),
                    Color(0xFF050609),
                    Color(0x00050609),
                  ],
                  stops: [0.0, 0.10, 0.46],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00050609),
                    Color(0x00050609),
                    Color(0xFF050609),
                  ],
                  stops: [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ],
        ),

        Positioned(
          left: 22,
          right: 54,
          // Desloca todo o bloco de informações para baixo, preservando
          // uma área maior da imagem livre de texto no centro do Hero.
          bottom: 30,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 345),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.65,
                  ),
                ),
                if (banner.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    banner.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.74),
                      fontSize: 14,
                      height: 1.48,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                const SizedBox(height: 15),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _buildHeroInfoChip(banner.category),
                    if (banner.duration.isNotEmpty)
                      _buildHeroInfoChip(banner.duration),
                    if (banner.level.isNotEmpty)
                      _buildHeroInfoChip(banner.level, gold: true),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openBanner(banner),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 23),
                      label: Text(
                        banner.buttonLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xD2211D18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: UnlColors.gold.withOpacity(0.34),
                        ),
                      ),
                      child: Text(
                        banner.badge.toUpperCase(),
                        style: const TextStyle(
                          color: UnlColors.gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroInfoChip(String text, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: gold
            ? UnlColors.gold.withOpacity(0.12)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
        border: gold
            ? Border.all(color: UnlColors.gold.withOpacity(0.32))
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: gold ? UnlColors.gold : Colors.white.withOpacity(0.84),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildHeroBackgroundFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF453719), Color(0xFF18150E), Color(0xFF050609)],
        ),
      ),
    );
  }

  Widget _buildHeroSkeleton() {
    return Container(
      height: 560,
      padding: const EdgeInsets.fromLTRB(22, 340, 54, 58),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17181E), Color(0xFF0A0B10), Color(0xFF050609)],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeleton(width: 102, height: 25, radius: 99),
            const SizedBox(height: 17),
            _skeleton(width: 285, height: 34),
            const SizedBox(height: 10),
            _skeleton(width: 240, height: 17),
            const SizedBox(height: 20),
            _skeleton(width: 150, height: 50, radius: 13),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroEmptyState() {
    return Container(
      height: 530,
      padding: const EdgeInsets.fromLTRB(22, 0, 24, 72),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D2413), Color(0xFF12130F), _homeBackground],
        ),
      ),
      child: const Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          'Os conteúdos em destaque aparecerão aqui.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            height: 1.12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildContinueWatchingSection() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * 0.72).clamp(270.0, 350.0).toDouble();
    final thumbnailHeight = cardWidth * (9 / 16);

    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Continuar assistindo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                height: 1.12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: thumbnailHeight + 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _continueWatching.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _buildContinueWatchingCard(
                  item: _continueWatching[index],
                  width: cardWidth,
                  thumbnailHeight: thumbnailHeight,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingCard({
    required _ContinueWatchingItem item,
    required double width,
    required double thumbnailHeight,
  }) {
    final progress = item.progress.clamp(0.0, 100.0).toDouble();

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: thumbnailHeight,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openContinueWatchingItem(item),
                splashColor: Colors.white.withOpacity(0.08),
                highlightColor: Colors.white.withOpacity(0.04),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl != null)
                      Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            _buildContinueWatchingBackgroundFallback(),
                      )
                    else
                      _buildContinueWatchingBackgroundFallback(),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00050609),
                            Color(0x00050609),
                            Color(0x87050609),
                          ],
                          stops: [0.0, 0.48, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 4,
                        color: Colors.black.withOpacity(0.42),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress / 100,
                          child: Container(color: UnlColors.gold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.lessonLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.60),
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingBackgroundFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5C4825), Color(0xFF2B210F), Color(0xFF0A0B10)],
        ),
      ),
    );
  }

  Widget _buildContentSection(_StudentHomeSection section) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _openSectionDestination(section),
                  style: TextButton.styleFrom(
                    foregroundColor: UnlColors.gold,
                    padding: const EdgeInsets.only(left: 12),
                    minimumSize: const Size(0, 38),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver mais',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(Icons.chevron_right_rounded, size: 19),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _cardSize(section.variant).height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _buildContentCard(
                  item: section.items[index],
                  variant: section.variant,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard({
    required _StudentHomeItem item,
    required _CardVariant variant,
  }) {
    final size = _cardSize(variant);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openHomeItem(item),
          splashColor: Colors.white.withOpacity(0.08),
          highlightColor: Colors.white.withOpacity(0.04),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.imageUrl != null)
                Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _buildCardBackgroundFallback(),
                )
              else
                _buildCardBackgroundFallback(),

              // Degradê contínuo e suave para separar imagem e informações.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00050609),
                      Color(0x12050609),
                      Color(0x8F050609),
                      Color(0xFA050609),
                    ],
                    stops: [0, 0.33, 0.62, 1],
                  ),
                ),
              ),

              if (item.badge != null)
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.62),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Text(
                      item.badge!.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),

              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _buildCardInformation(item: item, variant: variant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardInformation({
    required _StudentHomeItem item,
    required _CardVariant variant,
  }) {
    final titleSize = variant == _CardVariant.featured ? 18.5 : 16.0;
    final playSize = variant == _CardVariant.horizontal ? 36.0 : 40.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: playSize,
          height: playSize,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.black,
            size: playSize * 0.63,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          item.category.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: UnlColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleSize,
            height: 1.1,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${item.level} • ${item.duration}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.63),
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildCardBackgroundFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5C4825), Color(0xFF2B210F), Color(0xFF0A0B10)],
        ),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Carregando conteúdos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 255,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, __) {
                return _skeleton(width: 180, height: 255, radius: 18);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: UnlColors.errorBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: UnlColors.error.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Não foi possível atualizar a Home.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.68),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadHome,
              style: TextButton.styleFrom(
                foregroundColor: UnlColors.gold,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: UnlColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: UnlColors.border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_stories_outlined, color: UnlColors.gold, size: 30),
            SizedBox(height: 12),
            Text(
              'Os conteúdos aparecerão aqui.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Quando o ADM publicar trilhas, cursos ou aulas, eles serão exibidos nesta Home.',
              style: TextStyle(
                color: UnlColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton({
    required double width,
    required double height,
    double radius = 10,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  _CardSize _cardSize(_CardVariant variant) {
    switch (variant) {
      case _CardVariant.vertical:
        return const _CardSize(width: 184, height: 272);
      // Na Home web, o formato featured é uma vitrine vertical grande
      // (360 × 650). Mantemos essa proporção no app para a capa não ser
      // achatada nem recortada pelo contêiner horizontal.
      case _CardVariant.featured:
        return const _CardSize(width: 252, height: 455);
      case _CardVariant.horizontal:
        return const _CardSize(width: 304, height: 202);
    }
  }

  List<String> _collectContentIds(
    List<Map<String, dynamic>> rows,
    String contentType,
  ) {
    return rows
        .where(
          (row) =>
              (_text(row['content_type']) ?? '').toLowerCase() == contentType,
        )
        .map((row) => _text(row['content_id']))
        .whereType<String>()
        .toSet()
        .toList();
  }

  Map<String, Map<String, dynamic>> _rowsById(List<Map<String, dynamic>> rows) {
    final result = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final id = _text(row['id']);

      if (id != null) {
        result[id] = row;
      }
    }

    return result;
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];

    return value.whereType<Map>().map((row) {
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  _CardVariant _parseVariant(String? value) {
    switch (value?.toLowerCase()) {
      case 'featured':
        return _CardVariant.featured;
      case 'horizontal':
        return _CardVariant.horizontal;
      default:
        return _CardVariant.vertical;
    }
  }

  bool _isLiveAvailableForDisplay(Map<String, dynamic> live) {
    final startsAt = _parseLiveDateTime(_text(live['starts_at']));
    final endsAt = _parseLiveDateTime(_text(live['ends_at']));

    // A data de término é a referência principal. Nas reuniões legadas,
    // sem término cadastrado, o próprio horário marcado é a referência.
    final referenceTime = endsAt ?? startsAt;

    if (referenceTime == null) {
      return true;
    }

    final expiresAt = referenceTime.add(_liveVisibilityGracePeriod);

    // No instante exato do vencimento, a reunião já deve sair da Home.
    return DateTime.now().isBefore(expiresAt);
  }

  DateTime? _parseLiveDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value)?.toLocal();
  }

  String? _selectCover(Map<String, dynamic> row, _CardVariant variant) {
    final featured = _text(row['cover_featured_path']);
    final vertical = _text(row['cover_vertical_path']);
    final horizontal = _text(row['cover_horizontal_path']);
    final defaultCover = _text(row['cover_path']);

    if (variant == _CardVariant.featured) {
      return featured ?? defaultCover ?? vertical ?? horizontal;
    }

    if (variant == _CardVariant.horizontal) {
      return horizontal ?? defaultCover ?? vertical ?? featured;
    }

    return vertical ?? defaultCover ?? featured ?? horizontal;
  }

  DateTime _continueWatchingDate(Map<String, dynamic> row) {
    final date =
        DateTime.tryParse(
          _text(row['last_watched_at']) ?? _text(row['updated_at']) ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return date.toUtc();
  }

  String _continueWatchingLessonLabel(Map<String, dynamic> lesson) {
    final order = _asInt(lesson['sort_order']);
    final title = _text(lesson['title']) ?? 'Aula sem título';
    final label = order > 0
        ? 'Aula ${order.toString().padLeft(2, '0')}'
        : 'Aula';

    return '$label • $title';
  }

  double _continueWatchingProgress({
    required Map<String, dynamic> progressRow,
    required Map<String, dynamic> lesson,
  }) {
    if (_text(progressRow['completed_at']) != null) return 100;

    final duration = _asDouble(lesson['duration_sec']);
    final watched = _asDouble(progressRow['progress_seconds']);

    if (duration > 0 && watched > 0) {
      return ((watched / duration) * 100).round().clamp(1, 99).toDouble();
    }

    return watched > 0 ? 5 : 1;
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDuration(dynamic rawSeconds) {
    final seconds = rawSeconds is int
        ? rawSeconds
        : int.tryParse(rawSeconds?.toString() ?? '') ?? 0;

    if (seconds <= 0) return 'Aula';

    final minutes = (seconds / 60).round();

    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) return '${hours}h';

    return '${hours}h ${remainingMinutes}min';
  }

  String? _resolveAssetUrl(String? path) {
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

    if (normalized.startsWith('student-banners/')) {
      final storagePath = normalized.replaceFirst('student-banners/', '');

      return _supabase.storage
          .from('student-banners')
          .getPublicUrl(storagePath);
    }

    if (normalized.startsWith('materials/')) {
      final storagePath = normalized.replaceFirst('materials/', '');

      return _supabase.storage.from('materials').getPublicUrl(storagePath);
    }

    normalized = normalized
        .replaceFirst('covers/', '')
        .replaceFirst('course-covers/', '');

    return _supabase.storage.from('covers').getPublicUrl(normalized);
  }

  bool _isTrue(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }

  String? _text(dynamic value) {
    final raw = value?.toString();
    final text = raw?.trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }
}
