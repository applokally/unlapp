// VERSÃO: v31
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../screens/student_assessment_screen.dart';
import '../screens/student_lesson_screen.dart';
import '../widgets/student_app_shell.dart';

const Color _courseDetailBackground = Color(0xFF050609);

// Tela de apresentação do curso: capa full bleed, progresso compacto e módulos expansíveis.

class StudentCourseDetailScreen extends StatefulWidget {
  const StudentCourseDetailScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<StudentCourseDetailScreen> createState() =>
      _StudentCourseDetailScreenState();
}

class _StudentCourseDetailScreenState extends State<StudentCourseDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  _StudentCourseDetail? _course;
  bool _isLoading = true;
  String? _loadError;
  String? _expandedModuleId;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCourse() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final course = await _fetchCourse();

      if (!mounted) {
        return;
      }

      setState(() {
        _course = course;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _course = null;
        _isLoading = false;
        _loadError = 'Não foi possível carregar este curso agora.';
      });
    }
  }

  Future<_StudentCourseDetail> _fetchCourse() async {
    final dynamic courseResponse = await _supabase
        .from('courses')
        .select(
          'id,title,short_description,description,cover_path,'
          'cover_vertical_path,cover_horizontal_path,cover_featured_path,'
          'status',
        )
        .eq('id', widget.courseId)
        .eq('status', 'published')
        .maybeSingle();

    if (courseResponse is! Map) {
      throw StateError('course_not_found');
    }

    final courseRow = Map<String, dynamic>.from(courseResponse);

    final dynamic modulesResponse = await _supabase
        .from('course_modules')
        .select('id,course_id,title,description,sort_order,status')
        .eq('course_id', widget.courseId)
        .eq('status', 'published')
        .order('sort_order', ascending: true);

    final moduleRows = _rows(modulesResponse);
    final moduleIds = moduleRows
        .map((module) => _text(module['id']))
        .whereType<String>()
        .toList(growable: false);

    final lessonRows = moduleIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('lessons')
                .select(
                  'id,module_id,title,description,sort_order,status,'
                  'content_type,duration_sec',
                )
                .inFilter('module_id', moduleIds)
                .eq('status', 'published')
                .order('sort_order', ascending: true),
          );

    final lessonIds = lessonRows
        .map((lesson) => _text(lesson['id']))
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

    final lessonsByModuleId = <String, List<_StudentCourseLesson>>{};

    for (final row in lessonRows) {
      final lessonId = _text(row['id']);
      final moduleId = _text(row['module_id']);

      if (lessonId == null || moduleId == null) {
        continue;
      }

      final progress = progressByLessonId[lessonId];
      final completedAt = _text(progress?['completed_at']);
      final progressSeconds = _asInt(progress?['progress_seconds']);

      (lessonsByModuleId[moduleId] ??= []).add(
        _StudentCourseLesson(
          id: lessonId,
          title: _text(row['title']) ?? 'Aula',
          description: _text(row['description']),
          contentType: _text(row['content_type']),
          durationSeconds: _asInt(row['duration_sec']),
          progressSeconds: progressSeconds,
          lastWatchedAt:
              _parseDate(progress?['last_watched_at']) ??
              _parseDate(progress?['updated_at']),
          isCompleted: completedAt != null,
          hasStarted:
              completedAt != null ||
              progressSeconds > 0 ||
              _text(progress?['last_watched_at']) != null,
        ),
      );
    }

    final modules = <_StudentCourseModule>[
      for (final row in moduleRows)
        if (_text(row['id']) != null)
          _StudentCourseModule(
            id: _text(row['id'])!,
            title: _text(row['title']) ?? 'Módulo',
            description: _text(row['description']),
            lessons: List<_StudentCourseLesson>.unmodifiable(
              lessonsByModuleId[_text(row['id'])!] ??
                  const <_StudentCourseLesson>[],
            ),
          ),
    ];

    final completedLessonIds = progressByLessonId.entries
        .where((entry) => _text(entry.value['completed_at']) != null)
        .map((entry) => entry.key)
        .toSet();

    final courseAssessment = await _fetchCourseAssessment(
      courseId: _text(courseRow['id']) ?? widget.courseId,
      userId: userId,
      allLessonsCompleted:
          lessonIds.isNotEmpty && completedLessonIds.length == lessonIds.length,
      completedLessonIds: completedLessonIds,
    );

    return _StudentCourseDetail(
      id: _text(courseRow['id']) ?? widget.courseId,
      title: _text(courseRow['title']) ?? 'Curso',
      shortDescription: _text(courseRow['short_description']),
      description: _text(courseRow['description']),
      coverUrl: _resolveCoverUrl(_selectCoverPath(courseRow)),
      modules: List<_StudentCourseModule>.unmodifiable(modules),
      assessment: courseAssessment,
    );
  }

  Future<_StudentCourseAssessment?> _fetchCourseAssessment({
    required String courseId,
    required String? userId,
    required bool allLessonsCompleted,
    required Set<String> completedLessonIds,
  }) async {
    try {
      final assessmentRows = _rows(
        await _supabase
            .from('assessments')
            .select(
              'id,scope_type,course_id,lesson_id,access_condition,'
              'status,is_active,created_at',
            )
            .eq('course_id', courseId)
            .eq('scope_type', 'course')
            .eq('status', 'published')
            .eq('is_active', true)
            .order('created_at', ascending: true),
      );

      if (assessmentRows.isEmpty) {
        return null;
      }

      final assessment = assessmentRows.first;
      final assessmentId = _text(assessment['id']);

      if (assessmentId == null) {
        return null;
      }

      final accessCondition =
          _text(assessment['access_condition']) ?? 'after_all_lessons';

      final available = switch (accessCondition) {
        'after_all_lessons' || 'after_course_completion' => allLessonsCompleted,
        'after_lesson_completion' => () {
          final lessonId = _text(assessment['lesson_id']);
          return lessonId == null || completedLessonIds.contains(lessonId);
        }(),
        'manual_release' => await _hasAssessmentManualRelease(
          assessmentId: assessmentId,
          userId: userId,
        ),
        _ => false,
      };

      return _StudentCourseAssessment(id: assessmentId, isAvailable: available);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasAssessmentManualRelease({
    required String assessmentId,
    required String? userId,
  }) async {
    if (userId == null) {
      return false;
    }

    try {
      final dynamic response = await _supabase
          .from('assessment_manual_releases')
          .select('id')
          .eq('assessment_id', assessmentId)
          .eq('user_id', userId)
          .maybeSingle();

      return response is Map && _text(response['id']) != null;
    } catch (_) {
      return false;
    }
  }

  String? _selectCoverPath(Map<String, dynamic> course) {
    return _text(course['cover_vertical_path']) ??
        _text(course['cover_horizontal_path']) ??
        _text(course['cover_featured_path']) ??
        _text(course['cover_path']);
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.courses,
      scrollController: _scrollController,
      backgroundColor: _courseDetailBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadCourse,
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
            else if (_course != null)
              SliverToBoxAdapter(child: _buildCourseContent(_course!)),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseContent(_StudentCourseDetail course) {
    final allLessons = course.modules
        .expand((module) => module.lessons)
        .toList(growable: false);
    final completedLessons = allLessons
        .where((lesson) => lesson.isCompleted)
        .length;
    final startedLessons = allLessons
        .where((lesson) => lesson.hasStarted)
        .length;
    final totalLessons = allLessons.length;
    final progress = totalLessons == 0
        ? 0.0
        : (completedLessons / totalLessons).clamp(0.0, 1.0).toDouble();
    final courseCompleted =
        totalLessons > 0 && completedLessons == totalLessons;
    final assessment = course.assessment;
    final actionLabel = totalLessons == 0
        ? 'Conteúdo em preparação'
        : courseCompleted
        ? assessment == null
              ? 'Curso concluído'
              : assessment.isAvailable
              ? 'Fazer avaliação'
              : 'Avaliação bloqueada'
        : startedLessons > 0
        ? 'Continuar curso'
        : 'Iniciar curso';
    final isActionEnabled =
        totalLessons > 0 &&
        (!courseCompleted || (assessment != null && assessment.isAvailable));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCourseHero(course),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_descriptionFor(course).isNotEmpty) ...[
                Text(
                  _descriptionFor(course),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.60),
                    fontSize: 14,
                    height: 1.48,
                    fontWeight: FontWeight.w400,
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
              _buildCourseAction(
                label: actionLabel,
                isEnabled: isActionEnabled,
                onPressed: courseCompleted
                    ? assessment == null || !assessment.isAvailable
                          ? null
                          : () => _openCourseAssessment(assessment)
                    : _openCourseLesson,
              ),
              const SizedBox(height: 34),
              const Text(
                'Conteúdo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                course.modules.isEmpty
                    ? 'Nenhum módulo publicado'
                    : '${course.modules.length} ${course.modules.length == 1 ? 'módulo disponível' : 'módulos disponíveis'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.50),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              if (course.modules.isEmpty)
                _buildEmptyContentState()
              else
                for (var index = 0; index < course.modules.length; index++) ...[
                  _buildModule(course.modules[index], index + 1),
                  if (index < course.modules.length - 1)
                    const Divider(height: 1, color: Colors.white10),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCourseHero(_StudentCourseDetail course) {
    return SizedBox(
      height: 438,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (course.coverUrl != null)
            Image.network(
              course.coverUrl!,
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
                          fontWeight: FontWeight.w600,
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
            bottom: 32,
            child: Text(
              course.title,
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
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
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
                fontSize: 28,
                height: 1.0,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.55,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  totalLessons == 0
                      ? 'Este curso ainda não possui aulas publicadas.'
                      : '$completedLessons de $totalLessons aulas concluídas',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
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

  Widget _buildCourseAction({
    required String label,
    required bool isEnabled,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isEnabled ? onPressed : null,
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
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _openCourseAssessment(
    _StudentCourseAssessment assessment,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentAssessmentScreen(assessmentId: assessment.id),
      ),
    );

    if (mounted) {
      await _loadCourse();
    }
  }

  Future<void> _openCourseLesson() async {
    final course = _course;
    if (course == null) {
      return;
    }

    final allLessons = course.modules
        .expand((module) => module.lessons)
        .toList(growable: false);

    if (allLessons.isEmpty) {
      return;
    }

    final lessonsInProgress =
        allLessons
            .where((lesson) => lesson.hasStarted && !lesson.isCompleted)
            .toList()
          ..sort((first, second) {
            final firstDate = first.lastWatchedAt;
            final secondDate = second.lastWatchedAt;

            if (firstDate == null && secondDate == null) {
              return second.progressSeconds.compareTo(first.progressSeconds);
            }

            if (firstDate == null) {
              return 1;
            }

            if (secondDate == null) {
              return -1;
            }

            return secondDate.compareTo(firstDate);
          });

    final targetLesson = lessonsInProgress.isNotEmpty
        ? lessonsInProgress.first
        : allLessons.firstWhere(
            (lesson) => !lesson.isCompleted,
            orElse: () => allLessons.first,
          );

    await _openLesson(targetLesson);
  }

  Future<void> _openLesson(_StudentCourseLesson lesson) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentLessonScreen(lessonId: lesson.id),
      ),
    );

    if (mounted) {
      await _loadCourse();
    }
  }

  Widget _buildModule(_StudentCourseModule module, int index) {
    final isExpanded = _expandedModuleId == module.id;
    final lessonCount = module.lessons.length;

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedModuleId = isExpanded ? null : module.id;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Row(
                children: [
                  Text(
                    '${index.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: UnlColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lessonCount == 0
                              ? 'Nenhuma aula publicada'
                              : '$lessonCount ${lessonCount == 1 ? 'aula' : 'aulas'}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.46),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withOpacity(0.62),
                      size: 25,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (module.description != null &&
                    module.description!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      module.description!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.48),
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                if (module.lessons.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'As aulas deste módulo aparecerão aqui assim que forem publicadas.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.44),
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  )
                else
                  for (
                    var lessonIndex = 0;
                    lessonIndex < module.lessons.length;
                    lessonIndex++
                  ) ...[
                    _buildLessonRow(
                      module.lessons[lessonIndex],
                      lessonIndex + 1,
                    ),
                    if (lessonIndex < module.lessons.length - 1)
                      const Divider(height: 1, color: Colors.white10),
                  ],
                const SizedBox(height: 6),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 190),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonRow(_StudentCourseLesson lesson, int index) {
    final color = lesson.isCompleted
        ? UnlColors.gold
        : lesson.hasStarted
        ? Colors.white
        : Colors.white.withOpacity(0.68);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openLesson(lesson),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 35,
                height: 35,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lesson.isCompleted
                      ? UnlColors.gold.withOpacity(0.13)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  lesson.isCompleted
                      ? Icons.check_rounded
                      : _contentIcon(lesson.contentType),
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aula $index',
                      style: TextStyle(
                        color: UnlColors.gold.withOpacity(0.80),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lesson.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.32,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (lesson.description != null &&
                        lesson.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lesson.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.44),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDuration(lesson.durationSeconds),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.42),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (lesson.isCompleted) ...[
                    const SizedBox(height: 5),
                    const Text(
                      'Concluída',
                      style: TextStyle(
                        color: UnlColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
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
        child: Icon(Icons.menu_book_outlined, color: UnlColors.gold, size: 46),
      ),
    );
  }

  Widget _buildEmptyContentState() {
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
              'As aulas deste curso aparecerão aqui assim que forem publicadas.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.50),
                fontSize: 14,
                height: 1.48,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
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
          const Icon(Icons.menu_book_outlined, color: UnlColors.gold, size: 46),
          const SizedBox(height: 18),
          const Text(
            'Não foi possível abrir o curso',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.12,
              fontWeight: FontWeight.w600,
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
            onPressed: _loadCourse,
            style: OutlinedButton.styleFrom(
              foregroundColor: UnlColors.gold,
              side: const BorderSide(color: Color(0x44DBC094)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Tentar novamente',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _descriptionFor(_StudentCourseDetail course) {
    final shortDescription = course.shortDescription?.trim() ?? '';
    if (shortDescription.isNotEmpty) {
      return shortDescription;
    }

    return course.description?.trim() ?? '';
  }

  IconData _contentIcon(String? contentType) {
    final normalized = (contentType ?? '').toLowerCase();

    if (normalized.contains('video')) {
      return Icons.play_circle_outline_rounded;
    }

    if (normalized.contains('audio')) {
      return Icons.headphones_rounded;
    }

    if (normalized.contains('power') || normalized.contains('ppt')) {
      return Icons.slideshow_outlined;
    }

    if (normalized.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }

    if (normalized.contains('image') || normalized.contains('imagem')) {
      return Icons.image_outlined;
    }

    if (normalized.contains('live') || normalized.contains('ao_vivo')) {
      return Icons.live_tv_outlined;
    }

    return Icons.article_outlined;
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) {
      return 'Aula';
    }

    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}min';
  }

  String? _resolveCoverUrl(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }

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

    if (normalized.isEmpty) {
      return null;
    }

    return _supabase.storage.from('covers').getPublicUrl(normalized);
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }

  int _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _parseDate(dynamic value) {
    final text = _text(value);
    return text == null ? null : DateTime.tryParse(text);
  }
}

class _StudentCourseDetail {
  const _StudentCourseDetail({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.description,
    required this.coverUrl,
    required this.modules,
    required this.assessment,
  });

  final String id;
  final String title;
  final String? shortDescription;
  final String? description;
  final String? coverUrl;
  final List<_StudentCourseModule> modules;
  final _StudentCourseAssessment? assessment;
}

class _StudentCourseAssessment {
  const _StudentCourseAssessment({required this.id, required this.isAvailable});

  final String id;
  final bool isAvailable;
}

class _StudentCourseModule {
  const _StudentCourseModule({
    required this.id,
    required this.title,
    required this.description,
    required this.lessons,
  });

  final String id;
  final String title;
  final String? description;
  final List<_StudentCourseLesson> lessons;
}

class _StudentCourseLesson {
  const _StudentCourseLesson({
    required this.id,
    required this.title,
    required this.description,
    required this.contentType,
    required this.durationSeconds,
    required this.progressSeconds,
    required this.lastWatchedAt,
    required this.isCompleted,
    required this.hasStarted,
  });

  final String id;
  final String title;
  final String? description;
  final String? contentType;
  final int durationSeconds;
  final int progressSeconds;
  final DateTime? lastWatchedAt;
  final bool isCompleted;
  final bool hasStarted;
}
