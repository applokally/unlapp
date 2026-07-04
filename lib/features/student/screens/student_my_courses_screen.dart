import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _myCoursesBackground = Color(0xFF050609);
const String _myCoursesWebsiteBaseUrl =
    'https://www.universidadedelideres.com.br';

enum _MyCoursesTab { inProgress, favorites }

class StudentMyCoursesScreen extends StatefulWidget {
  const StudentMyCoursesScreen({super.key});

  static const String routeName = '/student-my-courses';

  @override
  State<StudentMyCoursesScreen> createState() => _StudentMyCoursesScreenState();
}

class _StudentMyCoursesScreenState extends State<StudentMyCoursesScreen> {
  final ScrollController _scrollController = ScrollController();

  List<_StudentMyCourse> _startedCourses = const [];
  List<_StudentMyCourse> _favoriteCourses = const [];
  _MyCoursesTab _activeTab = _MyCoursesTab.inProgress;
  bool _isLoading = true;
  String? _loadError;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMyCourses();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMyCourses() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw StateError('student_not_authenticated');
      }

      final results = await Future.wait<List<_StudentMyCourse>>([
        _fetchStartedCourses(user.id),
        _fetchFavoriteCourses(user.id),
      ]);

      if (!mounted) return;

      setState(() {
        _startedCourses = results[0];
        _favoriteCourses = results[1];
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar seus cursos agora.';
      });
    }
  }

  Future<List<_StudentMyCourse>> _fetchStartedCourses(String studentId) async {
    final dynamic progressResponse = await _supabase
        .from('lesson_progress')
        .select(
          'lesson_id,progress_seconds,completed_at,last_watched_at,updated_at',
        )
        .eq('student_id', studentId)
        .order('updated_at', ascending: false)
        .limit(1000);

    final progressRows = _rows(progressResponse);
    final startedLessonIds = progressRows
        .map((row) => _text(row['lesson_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (startedLessonIds.isEmpty) return const [];

    final dynamic startedLessonsResponse = await _supabase
        .from('lessons')
        .select('id,module_id,title,status,sort_order,duration_sec')
        .inFilter('id', startedLessonIds)
        .eq('status', 'published');

    final startedLessonRows = _rows(startedLessonsResponse);
    final startedModuleIds = startedLessonRows
        .map((row) => _text(row['module_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (startedModuleIds.isEmpty) return const [];

    final dynamic startedModulesResponse = await _supabase
        .from('course_modules')
        .select('id,course_id,status,sort_order')
        .inFilter('id', startedModuleIds)
        .eq('status', 'published');

    final startedModuleRows = _rows(startedModulesResponse);
    final startedCourseIds = startedModuleRows
        .map((row) => _text(row['course_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (startedCourseIds.isEmpty) return const [];

    final results = await Future.wait<dynamic>([
      _supabase
          .from('courses')
          .select(
            'id,title,short_description,description,cover_path,'
            'cover_vertical_path,cover_horizontal_path,cover_featured_path,'
            'status',
          )
          .inFilter('id', startedCourseIds)
          .eq('status', 'published'),
      _supabase
          .from('course_modules')
          .select('id,course_id,status,sort_order')
          .inFilter('course_id', startedCourseIds)
          .eq('status', 'published')
          .order('sort_order', ascending: true),
    ]);

    final courseRows = _rows(results[0]);
    final allModuleRows = _rows(results[1]);
    final visibleCourseIds = courseRows
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toSet();

    if (visibleCourseIds.isEmpty) return const [];

    final allModuleIds = allModuleRows
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final allLessonRows = allModuleIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('lessons')
                .select('id,module_id,title,status,sort_order,duration_sec')
                .inFilter('module_id', allModuleIds)
                .eq('status', 'published')
                .order('sort_order', ascending: true),
          );

    final modulesById = <String, Map<String, dynamic>>{
      for (final row in allModuleRows)
        if (_text(row['id']) != null) _text(row['id'])!: row,
    };

    final lessonsById = <String, Map<String, dynamic>>{
      for (final row in allLessonRows)
        if (_text(row['id']) != null) _text(row['id'])!: row,
    };

    final lessonsByCourse = <String, List<Map<String, dynamic>>>{};

    for (final lesson in allLessonRows) {
      final moduleId = _text(lesson['module_id']);
      final module = moduleId == null ? null : modulesById[moduleId];
      final courseId = module == null ? null : _text(module['course_id']);

      if (courseId == null || !visibleCourseIds.contains(courseId)) continue;

      (lessonsByCourse[courseId] ??= []).add(lesson);
    }

    final progressByCourse = <String, List<Map<String, dynamic>>>{};

    for (final progress in progressRows) {
      final lessonId = _text(progress['lesson_id']);
      final lesson = lessonId == null ? null : lessonsById[lessonId];
      final moduleId = lesson == null ? null : _text(lesson['module_id']);
      final module = moduleId == null ? null : modulesById[moduleId];
      final courseId = module == null ? null : _text(module['course_id']);

      if (courseId == null || !visibleCourseIds.contains(courseId)) continue;

      (progressByCourse[courseId] ??= []).add(progress);
    }

    final courses = <_StudentMyCourse>[];

    for (final course in courseRows) {
      final courseId = _text(course['id']);
      if (courseId == null) continue;

      final courseProgress = progressByCourse[courseId] ?? const [];
      if (courseProgress.isEmpty) continue;

      courseProgress.sort((first, second) {
        return _progressDate(second).compareTo(_progressDate(first));
      });

      final courseLessons = lessonsByCourse[courseId] ?? const [];
      final courseLessonIds = courseLessons
          .map((lesson) => _text(lesson['id']))
          .whereType<String>()
          .toSet();

      final completedLessonIds = <String>{
        for (final progress in courseProgress)
          if (_text(progress['completed_at']) != null &&
              _text(progress['lesson_id']) != null)
            _text(progress['lesson_id'])!,
      };

      final completedCount = completedLessonIds
          .where(courseLessonIds.contains)
          .length;
      final totalCount = courseLessonIds.length;
      final recentProgress = courseProgress.first;
      final recentLessonId = _text(recentProgress['lesson_id']);
      final recentLesson = recentLessonId == null
          ? null
          : lessonsById[recentLessonId];

      final recentLessonIsCompleted =
          recentLessonId != null && completedLessonIds.contains(recentLessonId);

      final description =
          _text(course['short_description']) ??
          _text(course['description']) ??
          '';

      courses.add(
        _StudentMyCourse(
          id: courseId,
          title: _text(course['title']) ?? 'Curso',
          subtitle: _buildStartedSubtitle(
            courseDescription: description,
            recentLesson: recentLesson,
            recentLessonIsCompleted: recentLessonIsCompleted,
            completedCount: completedCount,
            totalCount: totalCount,
          ),
          imageUrl: _resolveAssetUrl(_selectCourseCover(course)),
          completedLessons: completedCount,
          totalLessons: totalCount,
          activityAt: _progressDate(recentProgress),
          isFavorite: false,
        ),
      );
    }

    courses.sort((first, second) {
      return (second.activityAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(
            first.activityAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
    });

    return courses;
  }

  Future<List<_StudentMyCourse>> _fetchFavoriteCourses(String studentId) async {
    final dynamic response = await _supabase
        .from('student_favorites')
        .select(
          'id,content_type,content_id,title,subtitle,category,duration,'
          'level,image_url,target_url,created_at',
        )
        .eq('student_id', studentId)
        .order('created_at', ascending: false);

    final seenCourseIds = <String>{};
    final favorites = <_StudentMyCourse>[];

    for (final row in _rows(response)) {
      final contentType = (_text(row['content_type']) ?? '').toLowerCase();
      if (contentType != 'course') continue;

      final courseId = _text(row['content_id']);
      final title = _text(row['title']);

      if (courseId == null || title == null || !seenCourseIds.add(courseId)) {
        continue;
      }

      final subtitle =
          _text(row['subtitle']) ??
          _text(row['category']) ??
          'Curso salvo na sua lista.';

      favorites.add(
        _StudentMyCourse(
          id: courseId,
          title: title,
          subtitle: subtitle,
          imageUrl: _resolveAssetUrl(_text(row['image_url'])),
          completedLessons: 0,
          totalLessons: 0,
          activityAt: _dateFromValue(_text(row['created_at'])),
          isFavorite: true,
        ),
      );
    }

    return favorites;
  }

  String _buildStartedSubtitle({
    required String courseDescription,
    required Map<String, dynamic>? recentLesson,
    required bool recentLessonIsCompleted,
    required int completedCount,
    required int totalCount,
  }) {
    final lessonTitle = recentLesson == null
        ? null
        : _text(recentLesson['title']);

    if (lessonTitle != null && !recentLessonIsCompleted) {
      return 'Continue na aula: $lessonTitle';
    }

    if (totalCount > 0) {
      return '$completedCount de $totalCount aulas concluídas';
    }

    return courseDescription.isNotEmpty
        ? courseDescription
        : 'Continue sua jornada neste curso.';
  }

  void _closePage() {
    Navigator.of(context).maybePop();
  }

  void _openCoursesLibrary() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(StudentAppRoutes.courses, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final courses = _activeTab == _MyCoursesTab.inProgress
        ? _startedCourses
        : _favoriteCourses;

    return StudentAppShell(
      activeDestination: StudentAppDestination.home,
      scrollController: _scrollController,
      backgroundColor: _myCoursesBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadMyCourses,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildTabs()),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else
              SliverToBoxAdapter(
                child: _buildCoursesContent(
                  courses,
                  isFavoriteTab: _activeTab == _MyCoursesTab.favorites,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PERFIL',
                  style: TextStyle(
                    color: UnlColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.1,
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Meus cursos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Acompanhe os cursos iniciados e seus conteúdos salvos.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.56),
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _closePage,
            tooltip: 'Fechar',
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _MyCoursesTabButton(
              label: 'Em andamento',
              count: _startedCourses.length,
              active: _activeTab == _MyCoursesTab.inProgress,
              onTap: () {
                if (_activeTab == _MyCoursesTab.inProgress) return;

                setState(() => _activeTab = _MyCoursesTab.inProgress);
              },
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _MyCoursesTabButton(
              label: 'Favoritos',
              count: _favoriteCourses.length,
              active: _activeTab == _MyCoursesTab.favorites,
              onTap: () {
                if (_activeTab == _MyCoursesTab.favorites) return;

                setState(() => _activeTab = _MyCoursesTab.favorites);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesContent(
    List<_StudentMyCourse> courses, {
    required bool isFavoriteTab,
  }) {
    if (courses.isEmpty) {
      return _buildEmptyState(isFavoriteTab: isFavoriteTab);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        children: [
          for (var index = 0; index < courses.length; index++) ...[
            _MyCourseRow(course: courses[index]),
            if (index < courses.length - 1)
              const Divider(height: 32, color: Colors.white10),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState({required bool isFavoriteTab}) {
    final title = isFavoriteTab
        ? 'Nenhum curso salvo ainda'
        : 'Você ainda não iniciou um curso';
    final description = isFavoriteTab
        ? 'Quando você salvar um curso, ele aparecerá aqui para acessar quando quiser.'
        : 'Escolha um conteúdo na biblioteca para começar sua jornada.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 78, 28, 36),
      child: Column(
        children: [
          Icon(
            isFavoriteTab
                ? Icons.bookmark_border_rounded
                : Icons.menu_book_outlined,
            color: UnlColors.gold,
            size: 48,
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _openCoursesLibrary,
            style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            label: const Text(
              'Ver cursos disponíveis',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        children: [
          _buildSkeletonRow(),
          const Divider(height: 32, color: Colors.white10),
          _buildSkeletonRow(),
        ],
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return Row(
      children: [
        Container(
          width: 118,
          height: 82,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 10,
                color: Colors.white.withOpacity(0.07),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 18,
                color: Colors.white.withOpacity(0.07),
              ),
              const SizedBox(height: 8),
              Container(
                width: 150,
                height: 12,
                color: Colors.white.withOpacity(0.07),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 46, 20, 0),
      child: Column(
        children: [
          const Icon(Icons.refresh_rounded, color: UnlColors.gold, size: 38),
          const SizedBox(height: 16),
          const Text(
            'Não foi possível atualizar seus cursos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _loadError ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadMyCourses,
            style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Tentar novamente',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  String? _selectCourseCover(Map<String, dynamic> course) {
    return _text(course['cover_vertical_path']) ??
        _text(course['cover_horizontal_path']) ??
        _text(course['cover_featured_path']) ??
        _text(course['cover_path']);
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
      return '$_myCoursesWebsiteBaseUrl/$normalized';
    }

    if (normalized.startsWith('_next/')) {
      return '$_myCoursesWebsiteBaseUrl/$normalized';
    }

    if (normalized.startsWith('student-banners/')) {
      return _supabase.storage
          .from('student-banners')
          .getPublicUrl(normalized.replaceFirst('student-banners/', ''));
    }

    if (normalized.startsWith('materials/')) {
      return _supabase.storage
          .from('materials')
          .getPublicUrl(normalized.replaceFirst('materials/', ''));
    }

    normalized = normalized
        .replaceFirst('covers/', '')
        .replaceFirst('course-covers/', '');

    if (normalized.isEmpty) return null;

    return _supabase.storage.from('covers').getPublicUrl(normalized);
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') return null;

    return text;
  }

  DateTime _progressDate(Map<String, dynamic> row) {
    return _dateFromValue(
          _text(row['last_watched_at']) ?? _text(row['updated_at']),
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _dateFromValue(String? value) {
    if (value == null || value.isEmpty) return null;

    return DateTime.tryParse(value)?.toLocal();
  }
}

class _StudentMyCourse {
  const _StudentMyCourse({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.completedLessons,
    required this.totalLessons,
    required this.activityAt,
    required this.isFavorite,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final int completedLessons;
  final int totalLessons;
  final DateTime? activityAt;
  final bool isFavorite;

  double get progress {
    if (totalLessons <= 0) return 0;

    return (completedLessons / totalLessons).clamp(0.0, 1.0).toDouble();
  }
}

class _MyCoursesTabButton extends StatelessWidget {
  const _MyCoursesTabButton({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Colors.white.withOpacity(0.46);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? UnlColors.gold : Colors.white.withOpacity(0.12),
                width: active ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: active ? UnlColors.gold : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyCourseRow extends StatelessWidget {
  const _MyCourseRow({required this.course});

  final _StudentMyCourse course;

  @override
  Widget build(BuildContext context) {
    final progressLabel = course.totalLessons > 0
        ? '${course.completedLessons} de ${course.totalLessons} aulas'
        : _relativeDate(course.activityAt);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CourseThumbnail(imageUrl: course.imageUrl),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      course.isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.play_circle_outline_rounded,
                      color: UnlColors.gold,
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      course.isFavorite ? 'FAVORITO' : 'EM ANDAMENTO',
                      style: const TextStyle(
                        color: UnlColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  course.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  course.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.54),
                    fontSize: 12.5,
                    height: 1.32,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                if (!course.isFavorite && course.totalLessons > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: course.progress,
                      minHeight: 4,
                      backgroundColor: Colors.white.withOpacity(0.10),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        UnlColors.gold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                Text(
                  course.isFavorite
                      ? 'Salvo ${_relativeDate(course.activityAt)}'
                      : progressLabel,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.44),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _relativeDate(DateTime? date) {
    if (date == null) return '';

    final difference = DateTime.now().difference(date);

    if (difference.isNegative || difference.inMinutes < 1) return 'agora';
    if (difference.inMinutes < 60) return 'há ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'há ${difference.inHours} h';
    if (difference.inDays == 1) return 'ontem';

    return 'há ${difference.inDays} dias';
  }
}

class _CourseThumbnail extends StatelessWidget {
  const _CourseThumbnail({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      height: 82,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: imageUrl == null
            ? _fallback()
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A482A), Color(0xFF201A10), Color(0xFF090909)],
        ),
      ),
      child: Center(
        child: Icon(Icons.menu_book_outlined, color: UnlColors.gold, size: 30),
      ),
    );
  }
}
