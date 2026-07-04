import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../screens/student_course_detail_screen.dart';
import '../widgets/student_app_shell.dart';

const Color _trailDetailBackground = Color(0xFF050609);
const Color _trailCourseCardBackground = Color(0xFF050505);

// Página inicial da trilha: apresenta os cursos vinculados pelo ADM.
// Cada curso respeita o formato de card cadastrado (vertical ou horizontal).

class StudentTrailDetailScreen extends StatefulWidget {
  const StudentTrailDetailScreen({super.key, required this.trailId});

  final String trailId;

  @override
  State<StudentTrailDetailScreen> createState() =>
      _StudentTrailDetailScreenState();
}

class _StudentTrailDetailScreenState extends State<StudentTrailDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  _StudentTrailDetail? _trail;
  bool _isLoading = true;
  String? _loadError;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadTrail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTrail() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final trail = await _fetchTrail();

      if (!mounted) return;

      setState(() {
        _trail = trail;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _trail = null;
        _isLoading = false;
        _loadError = 'Não foi possível carregar esta trilha agora.';
      });
    }
  }

  Future<_StudentTrailDetail> _fetchTrail() async {
    final dynamic trailResponse = await _supabase
        .from('course_categories')
        .select(
          'id,title,slug,description,cover_path,cover_vertical_path,'
          'cover_horizontal_path,cover_featured_path,status',
        )
        .eq('id', widget.trailId)
        .eq('status', 'published')
        .maybeSingle();

    if (trailResponse is! Map) {
      throw StateError('trail_not_found');
    }

    final trailRow = Map<String, dynamic>.from(trailResponse);

    final dynamic mapsResponse = await _supabase
        .from('course_category_map')
        .select('course_id,category_id')
        .eq('category_id', widget.trailId);

    final orderedCourseIds = <String>[];
    final seenCourseIds = <String>{};

    for (final row in _rows(mapsResponse)) {
      final courseId = _text(row['course_id']);

      if (courseId != null && seenCourseIds.add(courseId)) {
        orderedCourseIds.add(courseId);
      }
    }

    final courseRows = orderedCourseIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('courses')
                .select(
                  'id,title,short_description,description,cover_path,'
                  'cover_vertical_path,cover_horizontal_path,'
                  'cover_featured_path,preferred_card_format,is_featured,'
                  'status',
                )
                .inFilter('id', orderedCourseIds)
                .eq('status', 'published'),
          );

    final courseRowsById = <String, Map<String, dynamic>>{
      for (final row in courseRows)
        if (_text(row['id']) != null) _text(row['id'])!: row,
    };

    final orderedCourseRows = <Map<String, dynamic>>[
      for (final courseId in orderedCourseIds)
        if (courseRowsById[courseId] != null) courseRowsById[courseId]!,
    ];

    final courseIds = orderedCourseRows
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toList(growable: false);

    final moduleRows = courseIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('course_modules')
                .select('id,course_id,sort_order,status')
                .inFilter('course_id', courseIds)
                .eq('status', 'published')
                .order('sort_order', ascending: true),
          );

    final moduleIds = moduleRows
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toList(growable: false);

    final lessonRows = moduleIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('lessons')
                .select('id,module_id,duration_sec,sort_order,status')
                .inFilter('module_id', moduleIds)
                .eq('status', 'published')
                .order('sort_order', ascending: true),
          );

    final lessonIds = lessonRows
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toList(growable: false);

    final userId = _supabase.auth.currentUser?.id;
    final progressRows = userId == null || lessonIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('lesson_progress')
                .select(
                  'lesson_id,progress_seconds,completed_at,last_watched_at,'
                  'updated_at',
                )
                .eq('student_id', userId)
                .inFilter('lesson_id', lessonIds),
          );

    final progressByLessonId = <String, Map<String, dynamic>>{
      for (final row in progressRows)
        if (_text(row['lesson_id']) != null) _text(row['lesson_id'])!: row,
    };

    final moduleCourseIds = <String, String>{};
    final modulesCountByCourse = <String, int>{};

    for (final row in moduleRows) {
      final moduleId = _text(row['id']);
      final courseId = _text(row['course_id']);

      if (moduleId == null || courseId == null) continue;

      moduleCourseIds[moduleId] = courseId;
      modulesCountByCourse[courseId] =
          (modulesCountByCourse[courseId] ?? 0) + 1;
    }

    final lessonCountByCourse = <String, int>{};
    final completedLessonsByCourse = <String, int>{};
    final durationByCourse = <String, int>{};
    final startedByCourse = <String, bool>{};
    final lastActivityByCourse = <String, DateTime?>{};

    for (final row in lessonRows) {
      final lessonId = _text(row['id']);
      final moduleId = _text(row['module_id']);
      final courseId = moduleId == null ? null : moduleCourseIds[moduleId];

      if (lessonId == null || courseId == null) continue;

      final progress = progressByLessonId[lessonId];
      final completed = _text(progress?['completed_at']) != null;
      final progressSeconds = _asInt(progress?['progress_seconds']);
      final activity =
          _parseDate(progress?['last_watched_at']) ??
          _parseDate(progress?['updated_at']);

      lessonCountByCourse[courseId] = (lessonCountByCourse[courseId] ?? 0) + 1;
      durationByCourse[courseId] =
          (durationByCourse[courseId] ?? 0) + _asInt(row['duration_sec']);

      if (completed) {
        completedLessonsByCourse[courseId] =
            (completedLessonsByCourse[courseId] ?? 0) + 1;
      }

      if (completed || progressSeconds > 0 || activity != null) {
        startedByCourse[courseId] = true;
      }

      final currentLatest = lastActivityByCourse[courseId];
      if (activity != null &&
          (currentLatest == null || activity.isAfter(currentLatest))) {
        lastActivityByCourse[courseId] = activity;
      }
    }

    final courses = <_StudentTrailCourse>[
      for (final row in orderedCourseRows)
        if (_text(row['id']) != null)
          _buildTrailCourse(
            row: row,
            modulesCount: modulesCountByCourse[_text(row['id'])!] ?? 0,
            lessonCount: lessonCountByCourse[_text(row['id'])!] ?? 0,
            completedLessons: completedLessonsByCourse[_text(row['id'])!] ?? 0,
            durationSeconds: durationByCourse[_text(row['id'])!] ?? 0,
            hasStarted: startedByCourse[_text(row['id'])!] ?? false,
            lastActivity: lastActivityByCourse[_text(row['id'])!],
          ),
    ];

    return _StudentTrailDetail(
      id: _text(trailRow['id']) ?? widget.trailId,
      title: _text(trailRow['title']) ?? 'Trilha',
      description: _text(trailRow['description']),
      coverUrl: _resolveCoverUrl(_selectTrailHeroCover(trailRow)),
      courses: List<_StudentTrailCourse>.unmodifiable(courses),
    );
  }

  _StudentTrailCourse _buildTrailCourse({
    required Map<String, dynamic> row,
    required int modulesCount,
    required int lessonCount,
    required int completedLessons,
    required int durationSeconds,
    required bool hasStarted,
    required DateTime? lastActivity,
  }) {
    final cover = _selectCourseCardCover(row);

    return _StudentTrailCourse(
      id: _text(row['id'])!,
      title: _text(row['title']) ?? 'Curso',
      shortDescription: _text(row['short_description']),
      description: _text(row['description']),
      coverUrl: _resolveCoverUrl(cover.path),
      cardLayout: cover.layout,
      isFeatured: _asBool(row['is_featured']),
      modulesCount: modulesCount,
      lessonCount: lessonCount,
      completedLessons: completedLessons,
      durationSeconds: durationSeconds,
      hasStarted: hasStarted,
      lastActivity: lastActivity,
    );
  }

  String? _selectTrailHeroCover(Map<String, dynamic> trail) {
    return _text(trail['cover_horizontal_path']) ??
        _text(trail['cover_featured_path']) ??
        _text(trail['cover_path']) ??
        _text(trail['cover_vertical_path']);
  }

  _CardCover _selectCourseCardCover(Map<String, dynamic> course) {
    final preferred = _text(course['preferred_card_format'])?.toLowerCase();
    final vertical = _text(course['cover_vertical_path']);
    final horizontal = _text(course['cover_horizontal_path']);
    final featured = _text(course['cover_featured_path']);
    final base = _text(course['cover_path']);

    if (preferred == 'horizontal') {
      return _CardCover(
        path: horizontal ?? featured ?? base ?? vertical,
        layout: _TrailCourseCardLayout.horizontal,
      );
    }

    if (preferred == 'vertical') {
      return _CardCover(
        path: vertical ?? featured ?? base ?? horizontal,
        layout: _TrailCourseCardLayout.vertical,
      );
    }

    if (preferred == 'featured') {
      return _CardCover(
        path: featured ?? horizontal ?? base ?? vertical,
        layout: _TrailCourseCardLayout.horizontal,
      );
    }

    if (vertical != null) {
      return _CardCover(
        path: vertical,
        layout: _TrailCourseCardLayout.vertical,
      );
    }

    return _CardCover(
      path: horizontal ?? featured ?? base,
      layout: _TrailCourseCardLayout.horizontal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.trails,
      scrollController: _scrollController,
      backgroundColor: _trailDetailBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadTrail,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (_trail != null)
              SliverToBoxAdapter(child: _buildTrailContent(_trail!)),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailContent(_StudentTrailDetail trail) {
    final coursesWithLessons = trail.courses
        .where((course) => course.lessonCountValue > 0)
        .toList(growable: false);
    final totalLessons = trail.courses.fold<int>(
      0,
      (total, course) => total + course.lessonCountValue,
    );
    final completedLessons = trail.courses.fold<int>(
      0,
      (total, course) => total + course.completedLessonsValue,
    );
    final progress = totalLessons == 0
        ? 0.0
        : (completedLessons / totalLessons).clamp(0.0, 1.0).toDouble();
    final targetCourse = _findActionCourse(coursesWithLessons);
    final actionLabel = targetCourse == null
        ? trail.courses.isEmpty
              ? 'Conteúdo em preparação'
              : 'Trilha concluída'
        : targetCourse.hasStartedValue
        ? 'Continuar trilha'
        : 'Começar trilha';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTrailHero(trail),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_descriptionFor(trail).isNotEmpty) ...[
                Text(
                  _descriptionFor(trail),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.60),
                    fontSize: 14,
                    height: 1.52,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              _buildProgressSection(
                progress: progress,
                completedLessons: completedLessons,
                totalLessons: totalLessons,
              ),
              const SizedBox(height: 22),
              _buildTrailAction(label: actionLabel, targetCourse: targetCourse),
              const SizedBox(height: 34),
              const Text(
                'Cursos da trilha',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.60,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                trail.courses.isEmpty
                    ? 'Nenhum curso publicado'
                    : '${trail.courses.length} ${trail.courses.length == 1 ? 'curso disponível' : 'cursos disponíveis'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.50),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (trail.courses.isEmpty)
                _buildEmptyCoursesState()
              else
                _buildCourseCards(trail.courses),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrailHero(_StudentTrailDetail trail) {
    final totalCourses = trail.courses.length;
    final totalLessons = trail.courses.fold<int>(
      0,
      (total, course) => total + course.lessonCountValue,
    );

    return SizedBox(
      height: 438,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (trail.coverUrl != null)
            Image.network(
              trail.coverUrl!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => _buildHeroFallback(),
            )
          else
            _buildHeroFallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xE6000000),
                  Color(0x58000000),
                  Color(0x5C000000),
                  Color(0xE1050609),
                  Color(0xFF050609),
                ],
                stops: [0.0, 0.20, 0.50, 0.78, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xA3050609),
                  Color(0x00050609),
                  Color(0x80050609),
                ],
                stops: [0.0, 0.50, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 102,
            left: 14,
            child: Material(
              color: Colors.black.withOpacity(0.30),
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(99),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Voltar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trail.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    height: 1.01,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 11),
                Text(
                  '$totalCourses ${totalCourses == 1 ? 'curso' : 'cursos'} • '
                  '$totalLessons ${totalLessons == 1 ? 'aula' : 'aulas'}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection({
    required double progress,
    required int completedLessons,
    required int totalLessons,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SEU PROGRESSO',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 31,
                height: 0.95,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  totalLessons == 0
                      ? 'Esta trilha ainda não possui aulas publicadas.'
                      : '$completedLessons de $totalLessons aulas concluídas',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.10),
            valueColor: const AlwaysStoppedAnimation<Color>(UnlColors.gold),
          ),
        ),
      ],
    );
  }

  Widget _buildTrailAction({
    required String label,
    required _StudentTrailCourse? targetCourse,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: targetCourse == null
            ? null
            : () => _openCourse(targetCourse),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(53),
          backgroundColor: UnlColors.gold,
          disabledBackgroundColor: Colors.white.withOpacity(0.10),
          foregroundColor: Colors.black,
          disabledForegroundColor: Colors.white38,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildCourseCards(List<_StudentTrailCourse> courses) {
    final rows = <Widget>[];
    final pendingVerticalCourses = <_StudentTrailCourse>[];

    void flushVerticalRow() {
      if (pendingVerticalCourses.isEmpty) return;

      rows.add(
        _buildVerticalCourseRow(
          first: pendingVerticalCourses.first,
          second: pendingVerticalCourses.length > 1
              ? pendingVerticalCourses[1]
              : null,
        ),
      );
      pendingVerticalCourses.clear();
    }

    for (final course in courses) {
      if (course.cardLayoutValue == _TrailCourseCardLayout.horizontal) {
        flushVerticalRow();
        rows.add(_buildHorizontalCourseCard(course));
        continue;
      }

      pendingVerticalCourses.add(course);
      if (pendingVerticalCourses.length == 2) {
        flushVerticalRow();
      }
    }

    flushVerticalRow();

    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index < rows.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildVerticalCourseRow({
    required _StudentTrailCourse first,
    required _StudentTrailCourse? second,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildVerticalCourseCard(first)),
        const SizedBox(width: 14),
        Expanded(
          child: second == null
              ? const SizedBox.shrink()
              : _buildVerticalCourseCard(second),
        ),
      ],
    );
  }

  Widget _buildVerticalCourseCard(_StudentTrailCourse course) {
    return AspectRatio(
      aspectRatio: 1 / 2.22,
      child: _buildCourseCardSurface(course: course, isVertical: true),
    );
  }

  Widget _buildHorizontalCourseCard(_StudentTrailCourse course) {
    return _buildCourseCardSurface(course: course, isVertical: false);
  }

  Widget _buildCourseCardSurface({
    required _StudentTrailCourse course,
    required bool isVertical,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openCourse(course),
        splashColor: Colors.white.withOpacity(0.06),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Container(
          decoration: BoxDecoration(
            color: _trailCourseCardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isVertical)
                Expanded(
                  flex: 17,
                  child: _buildCourseImage(course, aspectRatio: null),
                )
              else
                _buildCourseImage(course, aspectRatio: 16 / 9),
              if (isVertical)
                Expanded(
                  flex: 8,
                  child: _buildCourseDetails(course, compact: true),
                )
              else
                _buildCourseDetails(course, compact: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseImage(
    _StudentTrailCourse course, {
    required double? aspectRatio,
  }) {
    final image = Stack(
      fit: StackFit.expand,
      children: [
        if (course.coverUrl != null)
          Image.network(
            course.coverUrl!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildCourseCoverFallback(),
          )
        else
          _buildCourseCoverFallback(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x18000000), Color(0xE8050505)],
              stops: [0.0, 0.48, 1.0],
            ),
          ),
        ),
        if (course.isFeaturedValue)
          Positioned(
            top: 11,
            right: 11,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'DESTAQUE',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ),
      ],
    );

    if (aspectRatio == null) return image;

    return AspectRatio(aspectRatio: aspectRatio, child: image);
  }

  Widget _buildCourseDetails(
    _StudentTrailCourse course, {
    required bool compact,
  }) {
    final buttonLabel = course.hasStartedValue && !course.isCompleted
        ? 'Continuar'
        : course.isCompleted
        ? 'Revisar'
        : 'Assistir';

    return Container(
      width: double.infinity,
      color: _trailCourseCardBackground,
      padding: const EdgeInsets.all(14),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.06,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.45,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _compactCourseInfo(course),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.48),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      buttonLabel,
                      style: const TextStyle(
                        color: UnlColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: UnlColors.gold,
                      size: 16,
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.65,
                  ),
                ),
                if (_descriptionForCourse(course).isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    _descriptionForCourse(course),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.48),
                      fontSize: 13,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 7,
                  children: [
                    _CourseInfo(
                      icon: Icons.account_tree_outlined,
                      label:
                          '${course.modulesCountValue} ${course.modulesCountValue == 1 ? 'módulo' : 'módulos'}',
                    ),
                    _CourseInfo(
                      icon: Icons.play_circle_outline_rounded,
                      label:
                          '${course.lessonCountValue} ${course.lessonCountValue == 1 ? 'aula' : 'aulas'}',
                    ),
                    if (course.durationSecondsValue > 0)
                      _CourseInfo(
                        icon: Icons.schedule_outlined,
                        label: _formatDuration(course.durationSecondsValue),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      buttonLabel,
                      style: const TextStyle(
                        color: UnlColors.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: UnlColors.gold,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  _StudentTrailCourse? _findActionCourse(List<_StudentTrailCourse> courses) {
    if (courses.isEmpty) return null;

    final inProgress =
        courses
            .where((course) => course.hasStartedValue && !course.isCompleted)
            .toList()
          ..sort((first, second) {
            final firstDate = first.lastActivity;
            final secondDate = second.lastActivity;

            if (firstDate == null && secondDate == null) return 0;
            if (firstDate == null) return 1;
            if (secondDate == null) return -1;

            return secondDate.compareTo(firstDate);
          });

    if (inProgress.isNotEmpty) return inProgress.first;

    for (final course in courses) {
      if (!course.isCompleted) return course;
    }

    return null;
  }

  Future<void> _openCourse(_StudentTrailCourse course) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentCourseDetailScreen(courseId: course.id),
      ),
    );

    if (mounted) {
      await _loadTrail();
    }
  }

  Widget _buildEmptyCoursesState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.library_books_outlined,
            color: UnlColors.gold,
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Os cursos desta trilha aparecerão aqui assim que forem publicados no ADM.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.50),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A482A), Color(0xFF201A10), Color(0xFF050609)],
        ),
      ),
      child: Center(
        child: Icon(Icons.school_outlined, color: UnlColors.gold, size: 46),
      ),
    );
  }

  Widget _buildCourseCoverFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A482A), Color(0xFF201A10), Color(0xFF050505)],
        ),
      ),
      child: Center(
        child: Icon(Icons.menu_book_outlined, color: UnlColors.gold, size: 42),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 110),
      child: Center(
        child: CircularProgressIndicator(
          color: UnlColors.gold,
          strokeWidth: 2.2,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 0),
      child: Column(
        children: [
          const Icon(Icons.school_outlined, color: UnlColors.gold, size: 46),
          const SizedBox(height: 18),
          const Text(
            'Não foi possível abrir a trilha',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _loadError ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _loadTrail,
            style: OutlinedButton.styleFrom(
              foregroundColor: UnlColors.gold,
              side: const BorderSide(color: Color(0x44DBC094)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
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

  String _descriptionFor(_StudentTrailDetail trail) {
    return trail.description?.trim() ?? '';
  }

  String _descriptionForCourse(_StudentTrailCourse course) {
    final shortDescription = course.shortDescription?.trim() ?? '';
    if (shortDescription.isNotEmpty) return shortDescription;

    return course.description?.trim() ?? '';
  }

  String _compactCourseInfo(_StudentTrailCourse course) {
    final items = <String>[
      '${course.modulesCountValue} ${course.modulesCountValue == 1 ? 'módulo' : 'módulos'}',
      '${course.lessonCountValue} ${course.lessonCountValue == 1 ? 'aula' : 'aulas'}',
    ];

    if (course.durationSecondsValue > 0) {
      items.add(_formatDuration(course.durationSecondsValue));
    }

    return items.join(' • ');
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return 'Aula';

    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}min';
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
      return 'https://www.universidadedelideres.com.br/$normalized';
    }

    if (normalized.startsWith('_next/')) {
      return 'https://www.universidadedelideres.com.br/$normalized';
    }

    normalized = normalized
        .replaceFirst('covers/', '')
        .replaceFirst('course-covers/', '');

    if (normalized.isEmpty) return null;

    return _supabase.storage.from('covers').getPublicUrl(normalized);
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];

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

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }

  DateTime? _parseDate(dynamic value) {
    final text = _text(value);
    return text == null ? null : DateTime.tryParse(text);
  }
}

class _StudentTrailDetail {
  const _StudentTrailDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.courses,
  });

  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final List<_StudentTrailCourse> courses;
}

class _StudentTrailCourse {
  const _StudentTrailCourse({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.description,
    required this.coverUrl,
    required this.cardLayout,
    required this.isFeatured,
    required this.modulesCount,
    required this.lessonCount,
    required this.completedLessons,
    required this.durationSeconds,
    required this.hasStarted,
    required this.lastActivity,
  });

  final String id;
  final String title;
  final String? shortDescription;
  final String? description;
  final String? coverUrl;
  final _TrailCourseCardLayout? cardLayout;
  final bool? isFeatured;
  final int? modulesCount;
  final int? lessonCount;
  final int? completedLessons;
  final int? durationSeconds;
  final bool? hasStarted;
  final DateTime? lastActivity;

  _TrailCourseCardLayout get cardLayoutValue =>
      cardLayout ?? _TrailCourseCardLayout.vertical;

  bool get isFeaturedValue => isFeatured ?? false;

  bool get hasStartedValue => hasStarted ?? false;

  int get modulesCountValue => modulesCount ?? 0;

  int get lessonCountValue => lessonCount ?? 0;

  int get completedLessonsValue => completedLessons ?? 0;

  int get durationSecondsValue => durationSeconds ?? 0;

  bool get isCompleted =>
      lessonCountValue > 0 && completedLessonsValue >= lessonCountValue;
}

class _CardCover {
  const _CardCover({required this.path, required this.layout});

  final String? path;
  final _TrailCourseCardLayout layout;
}

enum _TrailCourseCardLayout { vertical, horizontal }

class _CourseInfo extends StatelessWidget {
  const _CourseInfo({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: UnlColors.gold.withOpacity(0.82), size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.57),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
