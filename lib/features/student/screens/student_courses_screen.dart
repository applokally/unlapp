import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../screens/student_course_detail_screen.dart';
import '../widgets/student_app_shell.dart';

const Color _coursesBackground = Color(0xFF050609);
const Color _courseCardBackground = Color(0xFF050505);

class _CourseCoverSelection {
  const _CourseCoverSelection({required this.path, required this.layout});

  final String? path;

  /// "vertical" para capas verticais; qualquer outro valor é tratado
  /// como horizontal, evitando quebra em alterações por hot reload.
  final String? layout;
}

class _StudentCourse {
  const _StudentCourse({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.description,
    required this.coverUrl,
    required this.coverLayout,
    required this.isFeatured,
    required this.lessonCount,
    required this.durationSeconds,
  });

  final String id;
  final String title;
  final String? shortDescription;
  final String? description;
  final String? coverUrl;

  /// Nullable por segurança: cursos existentes em memória após hot reload
  /// continuam sendo tratados como horizontais até uma recarga completa.
  final String? coverLayout;

  final bool isFeatured;
  final int lessonCount;
  final int durationSeconds;

  bool get isVerticalCover => coverLayout == 'vertical';
}

class StudentCoursesScreen extends StatefulWidget {
  const StudentCoursesScreen({super.key});

  static const String routeName = StudentAppRoutes.courses;

  @override
  State<StudentCoursesScreen> createState() => _StudentCoursesScreenState();
}

class _StudentCoursesScreenState extends State<StudentCoursesScreen> {
  final ScrollController _scrollController = ScrollController();

  List<_StudentCourse> _courses = const [];
  bool _isLoading = true;
  String? _loadError;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final courses = await _fetchCourses();

      if (!mounted) return;

      setState(() {
        _courses = courses;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Não foi possível carregar os cursos agora.';
      });
    }
  }

  Future<List<_StudentCourse>> _fetchCourses() async {
    final results = await Future.wait<dynamic>([
      _supabase
          .from('courses')
          .select(
            'id,title,short_description,description,cover_path,'
            'cover_vertical_path,cover_horizontal_path,cover_featured_path,'
            'status,is_featured,published_at',
          )
          .eq('status', 'published')
          .order('is_featured', ascending: false)
          .order('published_at', ascending: false),
      _supabase.from('course_category_map').select('course_id,category_id'),
    ]);

    final allCourseRows = _rows(results[0]);
    final mappedCourseIds = _rows(
      results[1],
    ).map((row) => _text(row['course_id'])).whereType<String>().toSet();

    final courseRows = allCourseRows
        .where((course) {
          final courseId = _text(course['id']);

          return courseId != null && !mappedCourseIds.contains(courseId);
        })
        .toList(growable: false);

    final courseIds = courseRows
        .map((course) => _text(course['id']))
        .whereType<String>()
        .toList(growable: false);

    if (courseIds.isEmpty) return const [];

    final dynamic modulesResponse = await _supabase
        .from('course_modules')
        .select('id,course_id,sort_order,status')
        .inFilter('course_id', courseIds)
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
                .select('id,module_id,duration_sec,sort_order,status')
                .inFilter('module_id', moduleIds)
                .eq('status', 'published')
                .order('sort_order', ascending: true),
          );

    final moduleCourseIds = <String, String>{};

    for (final module in moduleRows) {
      final moduleId = _text(module['id']);
      final courseId = _text(module['course_id']);

      if (moduleId != null && courseId != null) {
        moduleCourseIds[moduleId] = courseId;
      }
    }

    final lessonsByCourse = <String, List<Map<String, dynamic>>>{};

    for (final lesson in lessonRows) {
      final moduleId = _text(lesson['module_id']);
      final courseId = moduleId == null ? null : moduleCourseIds[moduleId];

      if (courseId == null) continue;

      (lessonsByCourse[courseId] ??= []).add(lesson);
    }

    return courseRows
        .map((course) {
          final courseId = _text(course['id'])!;
          final lessons = lessonsByCourse[courseId] ?? const [];
          final durationSeconds = lessons.fold<int>(
            0,
            (total, lesson) => total + _asInt(lesson['duration_sec']),
          );
          final cover = _selectCourseCover(course);

          return _StudentCourse(
            id: courseId,
            title: _text(course['title']) ?? 'Curso',
            shortDescription: _text(course['short_description']),
            description: _text(course['description']),
            coverUrl: _resolveCoverUrl(cover.path),
            coverLayout: cover.layout,
            isFeatured: _asBool(course['is_featured']),
            lessonCount: lessons.length,
            durationSeconds: durationSeconds,
          );
        })
        .toList(growable: false);
  }

  _CourseCoverSelection _selectCourseCover(Map<String, dynamic> course) {
    final verticalPath = _text(course['cover_vertical_path']);

    if (verticalPath != null) {
      return _CourseCoverSelection(path: verticalPath, layout: 'vertical');
    }

    final horizontalPath = _text(course['cover_horizontal_path']);

    if (horizontalPath != null) {
      return _CourseCoverSelection(path: horizontalPath, layout: 'horizontal');
    }

    final featuredPath = _text(course['cover_featured_path']);

    if (featuredPath != null) {
      return _CourseCoverSelection(path: featuredPath, layout: 'horizontal');
    }

    return _CourseCoverSelection(
      path: _text(course['cover_path']),
      layout: 'horizontal',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.courses,
      scrollController: _scrollController,
      backgroundColor: _coursesBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: const Color(0xFF191A20),
        onRefresh: _loadCourses,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            SliverToBoxAdapter(child: _buildPageHeader()),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (_courses.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyState())
            else
              SliverToBoxAdapter(child: _buildCourseRows()),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BIBLIOTECA',
            style: TextStyle(
              color: UnlColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.1,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Cursos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Explore os conteúdos disponíveis e avance na sua jornada de aprendizado.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseRows() {
    final rows = <Widget>[];
    final pendingVerticalCourses = <_StudentCourse>[];

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

    for (final course in _courses) {
      if (!course.isVerticalCover) {
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index < rows.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildVerticalCourseRow({
    required _StudentCourse first,
    required _StudentCourse? second,
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

  Widget _buildVerticalCourseCard(_StudentCourse course) {
    // A capa mantém praticamente a mesma altura atual. O card fica menor
    // porque a área textual foi reduzida.
    return AspectRatio(
      aspectRatio: 1 / 2.14,
      child: _buildCourseCardSurface(course: course, isVertical: true),
    );
  }

  Widget _buildHorizontalCourseCard(_StudentCourse course) {
    return _buildCourseCardSurface(course: course, isVertical: false);
  }

  Widget _buildCourseCardSurface({
    required _StudentCourse course,
    required bool isVertical,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StudentCourseDetailScreen(courseId: course.id),
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.06),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Container(
          decoration: BoxDecoration(
            color: _courseCardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isVertical)
                Expanded(
                  flex: 18,
                  child: _buildCourseImage(course, aspectRatio: null),
                )
              else
                _buildCourseImage(course, aspectRatio: 16 / 9),
              if (isVertical)
                Expanded(
                  flex: 6,
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
    _StudentCourse course, {
    required double? aspectRatio,
  }) {
    final image = Stack(
      fit: StackFit.expand,
      children: [
        if (course.coverUrl != null)
          Image.network(
            course.coverUrl!,
            // A altura maior do card permite preencher a largura da capa
            // vertical, preservando a composição sem margens laterais.
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
      ],
    );

    if (aspectRatio == null) return image;

    return AspectRatio(aspectRatio: aspectRatio, child: image);
  }

  Widget _buildCourseDetails(_StudentCourse course, {required bool compact}) {
    return Container(
      width: double.infinity,
      color: _courseCardBackground,
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
                const Spacer(),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Abrir curso',
                      style: TextStyle(
                        color: UnlColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: UnlColors.gold,
                      size: 15,
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
                const SizedBox(height: 14),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Abrir curso',
                      style: TextStyle(
                        color: UnlColors.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: UnlColors.gold,
                      size: 17,
                    ),
                  ],
                ),
              ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _skeleton(height: 326)),
              const SizedBox(width: 14),
              Expanded(child: _skeleton(height: 326)),
            ],
          ),
          const SizedBox(height: 14),
          _skeleton(height: 310),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: UnlColors.errorBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: UnlColors.error.withOpacity(0.34)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Não foi possível carregar os cursos.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _loadCourses,
              style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.menu_book_outlined,
              color: UnlColors.gold,
              size: 48,
            ),
            const SizedBox(height: 20),
            const Text(
              'Nenhum curso disponível',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.65,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              'Novos conteúdos serão disponibilizados aqui em breve.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.48),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
      ),
    );
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

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }
}
