// VERSÃO: v31
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _dashboardBackground = Color(0xFF050609);
const Color _dashboardSurface = Color(0xFF0A0A0A);

class StudentProfileDashboardScreen extends StatefulWidget {
  const StudentProfileDashboardScreen({super.key});

  static const String routeName = '/student-profile-dashboard';

  @override
  State<StudentProfileDashboardScreen> createState() =>
      _StudentProfileDashboardScreenState();
}

class _StudentProfileDashboardScreenState
    extends State<StudentProfileDashboardScreen> {
  final ScrollController _scrollController = ScrollController();

  _StudentDashboardData? _dashboard;
  bool _isLoading = true;
  String? _loadError;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
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

      final data = await _fetchDashboard(user.id);

      if (!mounted) return;

      setState(() {
        _dashboard = data;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível atualizar seu dashboard agora.';
      });
    }
  }

  Future<_StudentDashboardData> _fetchDashboard(String studentId) async {
    final dynamic progressResponse = await _supabase
        .from('lesson_progress')
        .select(
          'id,lesson_id,student_id,progress_seconds,completed_at,'
          'last_watched_at,updated_at',
        )
        .eq('student_id', studentId)
        .order('updated_at', ascending: false)
        .limit(500);

    final progressRows = _rows(progressResponse);
    final progressLessonIds = progressRows
        .map((row) => _text(row['lesson_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (progressLessonIds.isEmpty) {
      final certificates = await _loadIssuedCertificates(studentId);

      return _StudentDashboardData.empty(issuedCertificateCount: certificates);
    }

    final dynamic startedLessonsResponse = await _supabase
        .from('lessons')
        .select('id,module_id,title,sort_order,status,duration_sec')
        .inFilter('id', progressLessonIds)
        .eq('status', 'published');

    final startedLessonRows = _rows(startedLessonsResponse);
    final startedModuleIds = startedLessonRows
        .map((row) => _text(row['module_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (startedModuleIds.isEmpty) {
      final certificates = await _loadIssuedCertificates(studentId);

      return _StudentDashboardData.empty(issuedCertificateCount: certificates);
    }

    final dynamic startedModulesResponse = await _supabase
        .from('course_modules')
        .select('id,course_id,title,sort_order,status')
        .inFilter('id', startedModuleIds)
        .eq('status', 'published');

    final startedModuleRows = _rows(startedModulesResponse);
    final startedCourseIds = startedModuleRows
        .map((row) => _text(row['course_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (startedCourseIds.isEmpty) {
      final certificates = await _loadIssuedCertificates(studentId);

      return _StudentDashboardData.empty(issuedCertificateCount: certificates);
    }

    final results = await Future.wait<dynamic>([
      _supabase
          .from('course_modules')
          .select('id,course_id,title,sort_order,status')
          .inFilter('course_id', startedCourseIds)
          .eq('status', 'published')
          .order('sort_order', ascending: true),
      _supabase
          .from('courses')
          .select('id,title,status')
          .inFilter('id', startedCourseIds)
          .eq('status', 'published'),
      _supabase
          .from('course_category_map')
          .select('course_id,category_id')
          .inFilter('course_id', startedCourseIds),
      _loadIssuedCertificates(studentId),
    ]);

    final allModuleRows = _rows(results[0]);
    final courseRows = _rows(results[1]);
    final courseCategoryRows = _rows(results[2]);
    final issuedCertificateCount = results[3] as int;

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
                .select('id,module_id,title,sort_order,status,duration_sec')
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
    final coursesById = <String, Map<String, dynamic>>{
      for (final row in courseRows)
        if (_text(row['id']) != null) _text(row['id'])!: row,
    };
    final visibleCourseIds = coursesById.keys.toSet();

    final relevantProgressRows = progressRows
        .where((row) {
          final lessonId = _text(row['lesson_id']);
          final lesson = lessonId == null ? null : lessonsById[lessonId];
          final moduleId = lesson == null ? null : _text(lesson['module_id']);
          final module = moduleId == null ? null : modulesById[moduleId];
          final courseId = module == null ? null : _text(module['course_id']);

          return courseId != null && visibleCourseIds.contains(courseId);
        })
        .toList(growable: false);

    final completedLessonIds = <String>{
      for (final row in relevantProgressRows)
        if (_text(row['completed_at']) != null) _text(row['lesson_id'])!,
    };

    final relevantLessonIds = <String>{
      for (final lesson in allLessonRows)
        if (_text(lesson['id']) != null) _text(lesson['id'])!,
    };

    final completedLessonCount = completedLessonIds
        .where(relevantLessonIds.contains)
        .length;
    final totalLessonCount = relevantLessonIds.length;
    final progressPercent = totalLessonCount == 0
        ? 0
        : ((completedLessonCount / totalLessonCount) * 100).round();

    final startedTrailIds = <String>{
      for (final row in courseCategoryRows)
        if (visibleCourseIds.contains(_text(row['course_id'])) &&
            _text(row['category_id']) != null)
          _text(row['category_id'])!,
    };

    final activities = _buildActivities(
      progressRows: relevantProgressRows,
      lessonsById: lessonsById,
      modulesById: modulesById,
      coursesById: coursesById,
    );

    final nextStep = _buildNextStep(
      progressRows: relevantProgressRows,
      lessonsById: lessonsById,
      modulesById: modulesById,
      coursesById: coursesById,
      completedLessonIds: completedLessonIds,
      totalLessonCount: totalLessonCount,
    );

    return _StudentDashboardData(
      startedCourseCount: visibleCourseIds.length,
      startedTrailCount: startedTrailIds.length,
      completedLessonCount: completedLessonCount,
      totalLessonCount: totalLessonCount,
      issuedCertificateCount: issuedCertificateCount,
      progressPercent: progressPercent,
      activities: activities,
      nextStep: nextStep,
    );
  }

  Future<int> _loadIssuedCertificates(String studentId) async {
    try {
      final dynamic response = await _supabase
          .from('issued_certificates')
          .select('id')
          .eq('student_id', studentId)
          .eq('status', 'issued');

      return _rows(response).length;
    } catch (_) {
      return 0;
    }
  }

  List<_StudentDashboardActivity> _buildActivities({
    required List<Map<String, dynamic>> progressRows,
    required Map<String, Map<String, dynamic>> lessonsById,
    required Map<String, Map<String, dynamic>> modulesById,
    required Map<String, Map<String, dynamic>> coursesById,
  }) {
    final activities = <_StudentDashboardActivity>[];

    final orderedRows = List<Map<String, dynamic>>.from(progressRows)
      ..sort((first, second) {
        return _activityDate(second).compareTo(_activityDate(first));
      });

    for (final row in orderedRows) {
      final lessonId = _text(row['lesson_id']);
      final lesson = lessonId == null ? null : lessonsById[lessonId];
      final moduleId = lesson == null ? null : _text(lesson['module_id']);
      final module = moduleId == null ? null : modulesById[moduleId];
      final courseId = module == null ? null : _text(module['course_id']);
      final course = courseId == null ? null : coursesById[courseId];

      if (lesson == null || course == null) continue;

      final completed = _text(row['completed_at']) != null;
      final activityDate = _activityDate(row);

      activities.add(
        _StudentDashboardActivity(
          title: _text(lesson['title']) ?? 'Aula',
          subtitle: completed
              ? 'Aula concluída em ${_text(course['title']) ?? 'seu curso'}'
              : 'Você continuou em ${_text(course['title']) ?? 'seu curso'}',
          date: activityDate,
          completed: completed,
        ),
      );

      if (activities.length == 4) break;
    }

    return activities;
  }

  _StudentDashboardNextStep _buildNextStep({
    required List<Map<String, dynamic>> progressRows,
    required Map<String, Map<String, dynamic>> lessonsById,
    required Map<String, Map<String, dynamic>> modulesById,
    required Map<String, Map<String, dynamic>> coursesById,
    required Set<String> completedLessonIds,
    required int totalLessonCount,
  }) {
    if (progressRows.isEmpty || coursesById.isEmpty) {
      return const _StudentDashboardNextStep(
        title: 'Comece sua jornada',
        description: 'Escolha um curso disponível e inicie sua primeira aula.',
        actionLabel: 'Ver cursos',
        icon: Icons.play_circle_outline_rounded,
      );
    }

    final orderedRows = List<Map<String, dynamic>>.from(progressRows)
      ..sort((first, second) {
        return _activityDate(second).compareTo(_activityDate(first));
      });

    for (final row in orderedRows) {
      final lessonId = _text(row['lesson_id']);
      if (lessonId == null || completedLessonIds.contains(lessonId)) continue;

      final lesson = lessonsById[lessonId];
      final moduleId = lesson == null ? null : _text(lesson['module_id']);
      final module = moduleId == null ? null : modulesById[moduleId];
      final courseId = module == null ? null : _text(module['course_id']);
      final course = courseId == null ? null : coursesById[courseId];

      if (lesson == null || course == null) continue;

      return _StudentDashboardNextStep(
        title: _text(course['title']) ?? 'Continue sua evolução',
        description:
            'Continue na aula ${_text(lesson['title']) ?? 'em andamento'} e avance no seu ritmo.',
        actionLabel: 'Continuar curso',
        icon: Icons.play_arrow_rounded,
      );
    }

    if (totalLessonCount > 0 && completedLessonIds.length >= totalLessonCount) {
      return const _StudentDashboardNextStep(
        title: 'Uma etapa concluída',
        description:
            'Parabéns pela sua evolução. Veja os próximos conteúdos disponíveis.',
        actionLabel: 'Ver cursos',
        icon: Icons.auto_awesome_rounded,
      );
    }

    return const _StudentDashboardNextStep(
      title: 'Continue sua jornada',
      description: 'Acesse seus conteúdos e avance para a próxima aula.',
      actionLabel: 'Ver cursos',
      icon: Icons.play_circle_outline_rounded,
    );
  }

  void _openCourses() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(StudentAppRoutes.courses, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.home,
      scrollController: _scrollController,
      backgroundColor: _dashboardBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadDashboard,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            SliverToBoxAdapter(child: _buildHeader()),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (_dashboard != null)
              SliverToBoxAdapter(child: _buildDashboard(_dashboard!)),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'PERFIL',
                style: TextStyle(
                  color: UnlColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.9,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Acompanhe sua evolução e retome seus conteúdos com facilidade.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(_StudentDashboardData dashboard) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildJourneySection(dashboard),
          const SizedBox(height: 28),
          _buildNextStepSection(dashboard.nextStep),
          const SizedBox(height: 34),
          _buildActivitySection(dashboard.activities),
          const SizedBox(height: 34),
          _buildGoalSection(dashboard),
        ],
      ),
    );
  }

  Widget _buildJourneySection(_StudentDashboardData dashboard) {
    final progress = (dashboard.progressPercent / 100)
        .clamp(0.0, 1.0)
        .toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _dashboardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUA JORNADA',
            style: TextStyle(
              color: UnlColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sua evolução até aqui.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${dashboard.progressPercent}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    dashboard.totalLessonCount == 0
                        ? 'Seu progresso aparecerá aqui quando você iniciar uma aula.'
                        : '${dashboard.completedLessonCount} de ${dashboard.totalLessonCount} aulas concluídas',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.54),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.black,
              valueColor: const AlwaysStoppedAnimation<Color>(UnlColors.gold),
            ),
          ),
          const SizedBox(height: 23),
          Divider(color: Colors.white.withOpacity(0.08), height: 1),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _JourneyMetric(
                      icon: Icons.menu_book_outlined,
                      value: dashboard.startedCourseCount,
                      label: 'cursos iniciados',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _JourneyMetric(
                      icon: Icons.school_outlined,
                      value: dashboard.startedTrailCount,
                      label: 'trilhas em andamento',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _JourneyMetric(
                      icon: Icons.check_circle_outline_rounded,
                      value: dashboard.completedLessonCount,
                      label: 'aulas concluídas',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _JourneyMetric(
                      icon: Icons.workspace_premium_outlined,
                      value: dashboard.issuedCertificateCount,
                      label: 'certificados',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNextStepSection(_StudentDashboardNextStep nextStep) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _openCourses,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: UnlColors.gold.withOpacity(0.28)),
            color: UnlColors.gold.withOpacity(0.06),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: UnlColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(nextStep.icon, color: UnlColors.gold, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRÓXIMO PASSO',
                      style: TextStyle(
                        color: UnlColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      nextStep.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      nextStep.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.56),
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          nextStep.actionLabel,
                          style: const TextStyle(
                            color: UnlColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: UnlColors.gold,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivitySection(List<_StudentDashboardActivity> activities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ATIVIDADE RECENTE',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Histórico da sua evolução',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            height: 1.12,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 16),
        if (activities.isEmpty)
          Text(
            'Quando você começar suas aulas, sua evolução aparecerá aqui.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontSize: 14,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          )
        else
          for (var index = 0; index < activities.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: Colors.white10),
            _ActivityRow(activity: activities[index]),
          ],
      ],
    );
  }

  Widget _buildGoalSection(_StudentDashboardData dashboard) {
    final progress = dashboard.totalLessonCount == 0
        ? 0.0
        : (dashboard.completedLessonCount / dashboard.totalLessonCount)
              .clamp(0.0, 1.0)
              .toDouble();
    final certificateReady = dashboard.issuedCertificateCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'META ATUAL',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          dashboard.totalLessonCount == 0
              ? 'Iniciar sua primeira etapa.'
              : 'Avançar nas aulas em andamento.',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            height: 1.12,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          dashboard.totalLessonCount == 0
              ? 'Escolha um curso e comece sua evolução dentro da plataforma.'
              : 'Cada aula concluída aproxima você da sua próxima conquista.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.56),
            fontSize: 14,
            height: 1.48,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 22),
        _GoalProgressLine(
          label: 'Aulas concluídas',
          value: dashboard.totalLessonCount == 0
              ? '0 de 0'
              : '${dashboard.completedLessonCount} de ${dashboard.totalLessonCount}',
          progress: progress,
        ),
        const SizedBox(height: 20),
        _GoalProgressLine(
          label: 'Certificados',
          value: certificateReady ? 'Disponível' : 'Em andamento',
          progress: certificateReady ? 1 : 0,
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 84),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: UnlColors.gold,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.refresh_rounded, color: UnlColors.gold, size: 31),
          const SizedBox(height: 14),
          const Text(
            'Não foi possível atualizar seu dashboard.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _loadError ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _loadDashboard,
            style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
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

  DateTime _activityDate(Map<String, dynamic> row) {
    final value =
        _text(row['completed_at']) ??
        _text(row['last_watched_at']) ??
        _text(row['updated_at']) ??
        '';

    return DateTime.tryParse(value)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

class _StudentDashboardData {
  const _StudentDashboardData({
    required this.startedCourseCount,
    required this.startedTrailCount,
    required this.completedLessonCount,
    required this.totalLessonCount,
    required this.issuedCertificateCount,
    required this.progressPercent,
    required this.activities,
    required this.nextStep,
  });

  final int startedCourseCount;
  final int startedTrailCount;
  final int completedLessonCount;
  final int totalLessonCount;
  final int issuedCertificateCount;
  final int progressPercent;
  final List<_StudentDashboardActivity> activities;
  final _StudentDashboardNextStep nextStep;

  factory _StudentDashboardData.empty({required int issuedCertificateCount}) {
    return _StudentDashboardData(
      startedCourseCount: 0,
      startedTrailCount: 0,
      completedLessonCount: 0,
      totalLessonCount: 0,
      issuedCertificateCount: issuedCertificateCount,
      progressPercent: 0,
      activities: const [],
      nextStep: const _StudentDashboardNextStep(
        title: 'Comece sua jornada',
        description: 'Escolha um curso disponível e inicie sua primeira aula.',
        actionLabel: 'Ver cursos',
        icon: Icons.play_circle_outline_rounded,
      ),
    );
  }
}

class _StudentDashboardNextStep {
  const _StudentDashboardNextStep({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.icon,
  });

  final String title;
  final String description;
  final String actionLabel;
  final IconData icon;
}

class _StudentDashboardActivity {
  const _StudentDashboardActivity({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.completed,
  });

  final String title;
  final String subtitle;
  final DateTime date;
  final bool completed;
}

class _JourneyMetric extends StatelessWidget {
  const _JourneyMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: UnlColors.gold, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.04,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.50),
                  fontSize: 11,
                  height: 1.22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final _StudentDashboardActivity activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: activity.completed
                  ? UnlColors.gold.withOpacity(0.12)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              activity.completed
                  ? Icons.check_rounded
                  : Icons.play_arrow_rounded,
              color: activity.completed ? UnlColors.gold : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activity.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatRelativeDate(activity.date),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _formatRelativeDate(DateTime value) {
    final localDate = value.toLocal();
    final difference = DateTime.now().difference(localDate);

    if (difference.isNegative || difference.inMinutes < 1) return 'Agora';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min';
    if (difference.inHours < 24) return '${difference.inHours} h';
    if (difference.inDays == 1) return 'Ontem';

    return '${difference.inDays} dias';
  }
}

class _GoalProgressLine extends StatelessWidget {
  const _GoalProgressLine({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0).toDouble(),
            minHeight: 6,
            backgroundColor: Colors.black,
            valueColor: const AlwaysStoppedAnimation<Color>(UnlColors.gold),
          ),
        ),
      ],
    );
  }
}
