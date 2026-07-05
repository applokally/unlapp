// VERSÃO: v31
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _lessonBackground = Color(0xFF050609);
const Color _lessonSurface = Color(0xFF0A0A0A);

// Mesmo endpoint que a versão web usa para gerar a URL assinada do arquivo.
const String _studentStorageUrlEndpoint =
    'https://www.universidadedelideres.com.br/api/student/storage-url';

class StudentLessonScreen extends StatefulWidget {
  const StudentLessonScreen({super.key, required this.lessonId});

  final String lessonId;

  @override
  State<StudentLessonScreen> createState() => _StudentLessonScreenState();
}

class _StudentLessonScreenState extends State<StudentLessonScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commentController = TextEditingController();

  _StudentLessonBundle? _bundle;
  VideoPlayerController? _playerController;
  String? _primaryContentUrl;
  bool _isLoading = true;
  bool _isPreparingContent = false;
  bool _isSavingProgress = false;
  bool _isSendingComment = false;
  String? _loadError;
  String? _playerError;
  int _lastSavedSeconds = 0;
  List<_LessonContentSource> _playableContentSources = const [];
  int _activePlayableContentIndex = -1;
  bool _isRecoveringPlayer = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadLesson();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commentController.dispose();
    final controller = _playerController;
    if (controller != null) {
      controller
        ..removeListener(_handlePlayerChanged)
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _loadLesson() async {
    await _disposePlayer();

    if (mounted) {
      setState(() {
        _isLoading = true;
        _isPreparingContent = false;
        _isSavingProgress = false;
        _isSendingComment = false;
        _primaryContentUrl = null;
        _playerError = null;
        _loadError = null;
        _playableContentSources = const [];
        _activePlayableContentIndex = -1;
        _isRecoveringPlayer = false;
      });
    }

    try {
      final bundle = await _fetchLessonBundle();

      if (!mounted) {
        return;
      }

      setState(() {
        _bundle = bundle;
        _isLoading = false;
        _loadError = null;
        _lastSavedSeconds = bundle.currentProgress?.progressSeconds ?? 0;
      });

      unawaited(_registerLessonOpened());
      unawaited(_preparePrimaryContent(bundle.currentLesson));
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _bundle = null;
        _isLoading = false;
        _loadError = 'Não foi possível carregar esta aula agora.';
      });
    }
  }

  Future<void> _disposePlayer() async {
    final controller = _playerController;
    _playerController = null;

    if (controller == null) {
      return;
    }

    controller.removeListener(_handlePlayerChanged);
    await controller.dispose();
  }

  Future<_StudentLessonBundle> _fetchLessonBundle() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('student_not_authenticated');
    }

    final dynamic lessonResponse = await _supabase
        .from('lessons')
        .select(
          'id,module_id,title,description,sort_order,status,content_type,'
          'video_provider,video_url,duration_sec,is_preview,source_mode,'
          'content_body,primary_asset_path,primary_asset_name,'
          'primary_asset_mime_type,primary_asset_size_bytes,external_url,'
          'live_provider,meeting_sdk,zoom_meeting_id,zoom_passcode,'
          'zoom_join_url,scheduled_start_at,scheduled_end_at,zoom_recording_url',
        )
        .eq('id', widget.lessonId)
        .eq('status', 'published')
        .maybeSingle();

    if (lessonResponse is! Map) {
      throw StateError('lesson_not_found');
    }

    final currentLesson = _StudentLesson.fromMap(
      Map<String, dynamic>.from(lessonResponse),
    );

    final dynamic moduleResponse = await _supabase
        .from('course_modules')
        .select('id,course_id,title,description,sort_order,status')
        .eq('id', currentLesson.moduleId)
        .eq('status', 'published')
        .maybeSingle();

    if (moduleResponse is! Map) {
      throw StateError('module_not_found');
    }

    final currentModule = _StudentLessonModule.fromMap(
      Map<String, dynamic>.from(moduleResponse),
    );

    final dynamic courseResponse = await _supabase
        .from('courses')
        .select('id,title,status')
        .eq('id', currentModule.courseId)
        .eq('status', 'published')
        .maybeSingle();

    if (courseResponse is! Map) {
      throw StateError('course_not_found');
    }

    final course = Map<String, dynamic>.from(courseResponse);
    final courseTitle = _text(course['title']) ?? 'Curso';

    final dynamic modulesResponse = await _supabase
        .from('course_modules')
        .select('id,course_id,title,description,sort_order,status')
        .eq('course_id', currentModule.courseId)
        .eq('status', 'published')
        .order('sort_order', ascending: true);

    final modules = _rows(
      modulesResponse,
    ).map(_StudentLessonModule.fromMap).toList(growable: false);

    final moduleIds = modules
        .map((module) => module.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final lessons = moduleIds.isEmpty
        ? const <_StudentLesson>[]
        : _rows(
            await _supabase
                .from('lessons')
                .select(
                  'id,module_id,title,description,sort_order,status,'
                  'content_type,video_provider,video_url,duration_sec,'
                  'is_preview,source_mode,content_body,primary_asset_path,'
                  'primary_asset_name,primary_asset_mime_type,'
                  'primary_asset_size_bytes,external_url,live_provider,'
                  'meeting_sdk,zoom_meeting_id,zoom_passcode,zoom_join_url,'
                  'scheduled_start_at,scheduled_end_at,zoom_recording_url',
                )
                .inFilter('module_id', moduleIds)
                .eq('status', 'published')
                .order('sort_order', ascending: true),
          ).map(_StudentLesson.fromMap).toList(growable: false);

    final lessonIds = lessons
        .map((lesson) => lesson.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final progressRows = lessonIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _rows(
            await _supabase
                .from('lesson_progress')
                .select(
                  'id,lesson_id,student_id,progress_seconds,completed_at,'
                  'last_watched_at,updated_at',
                )
                .eq('student_id', user.id)
                .inFilter('lesson_id', lessonIds),
          );

    final progressByLessonId = <String, _StudentLessonProgress>{
      for (final row in progressRows)
        if ((_text(row['lesson_id']) ?? '').isNotEmpty)
          _text(row['lesson_id'])!: _StudentLessonProgress.fromMap(row),
    };

    // Os carregamentos extras não podem impedir a abertura da aula.
    // Cada método sempre devolve uma lista, inclusive quando não houver dados.
    final assets = await _loadLessonAssets(currentLesson.id);
    final comments = await _loadApprovedLessonComments(currentLesson.id);

    return _StudentLessonBundle(
      courseId: _text(course['id']) ?? currentModule.courseId,
      courseTitle: courseTitle,
      currentModuleTitle: currentModule.title,
      currentLesson: currentLesson,
      modules: modules,
      lessons: lessons,
      progressByLessonId: progressByLessonId,
      assets: assets,
      comments: comments,
    );
  }

  Future<List<_StudentLessonAsset>> _loadLessonAssets(String lessonId) async {
    var loadedAssets = const <_StudentLessonAsset>[];

    try {
      final dynamic response = await _supabase
          .from('lesson_assets')
          .select(
            'id,lesson_id,asset_type,title,storage_path,mime_type,'
            'size_bytes,sort_order,file_name',
          )
          .eq('lesson_id', lessonId)
          .order('sort_order', ascending: true);

      final assets = _rows(response)
          .map(_StudentLessonAsset.fromMap)
          .where((asset) => asset.storagePath.isNotEmpty)
          .toList(growable: false);

      loadedAssets = await Future.wait<_StudentLessonAsset>(
        assets.map((asset) async {
          final signedUrl = await _resolveLessonMaterialUrl(asset.storagePath);
          return asset.copyWithSignedUrl(signedUrl);
        }),
      );
    } catch (error) {
      debugPrint('Arquivos da aula: não foi possível carregar: $error');
    }

    return List<_StudentLessonAsset>.unmodifiable(loadedAssets);
  }

  Future<List<_StudentLessonComment>> _loadApprovedLessonComments(
    String lessonId,
  ) async {
    var loadedComments = const <_StudentLessonComment>[];

    try {
      final dynamic response = await _supabase
          .from('lesson_comments')
          .select(
            'id,lesson_id,student_id,student_name,student_avatar_url,'
            'comment,status,admin_note,created_at',
          )
          .eq('lesson_id', lessonId)
          .eq('status', 'approved')
          .order('created_at', ascending: false);

      loadedComments = _rows(response)
          .map(_StudentLessonComment.fromMap)
          .where((comment) => comment.comment.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      debugPrint('Comentários da aula: não foi possível carregar: $error');
    }

    return List<_StudentLessonComment>.unmodifiable(loadedComments);
  }

  Future<String?> _resolveLessonMaterialUrl(String storagePath) async {
    final cleanPath = storagePath.trim();

    if (cleanPath.isEmpty) {
      return null;
    }

    if (_isHttpUrl(cleanPath)) {
      return cleanPath;
    }

    return _requestWebsiteStorageUrl(
      bucket: 'lesson-materials',
      path: cleanPath,
    );
  }

  Future<_StudentProfileData?> _loadCurrentStudentProfile(String userId) async {
    if (userId.isEmpty) {
      return null;
    }

    try {
      final dynamic response = await _supabase
          .from('profiles')
          .select('id,full_name,avatar_url')
          .eq('id', userId)
          .maybeSingle();

      if (response is! Map) {
        return null;
      }

      return _StudentProfileData.fromMap(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  String _studentDisplayName(User user, _StudentProfileData? profile) {
    return profile?.fullName ??
        _text(user.userMetadata?['full_name']) ??
        _text(user.userMetadata?['name']) ??
        _text(user.email) ??
        'Aluno';
  }

  Future<void> _submitLessonComment() async {
    final bundle = _bundle;
    final comment = _commentController.text.trim();
    final user = _supabase.auth.currentUser;

    if (bundle == null || comment.isEmpty) {
      _showMessage('Escreva um comentário antes de enviar.');
      return;
    }

    if (user == null) {
      _showMessage('Faça login novamente para enviar um comentário.');
      return;
    }

    if (mounted) {
      setState(() => _isSendingComment = true);
    }

    try {
      final profile = await _loadCurrentStudentProfile(user.id);

      // O app grava pelo cliente Supabase autenticado, usando a mesma sessão
      // do aluno. O registro fica pendente para a moderação já existente no ADM.
      await _supabase.from('lesson_comments').insert({
        'lesson_id': bundle.currentLesson.id,
        'student_id': user.id,
        'student_name': _studentDisplayName(user, profile),
        'student_avatar_url': profile?.avatarUrl,
        'comment': comment,
        'status': 'pending',
      });

      if (!mounted) {
        return;
      }

      _commentController.clear();
      _showMessage('Comentário enviado para análise do ADM.');
    } on PostgrestException catch (error) {
      debugPrint(
        'Comentários da aula: falha ao enviar '
        '[${error.code ?? 'sem_código'}] ${error.message}',
      );
      _showMessage(
        error.message.trim().isEmpty
            ? 'Não foi possível enviar o comentário.'
            : error.message,
      );
    } catch (error) {
      debugPrint('Comentários da aula: falha inesperada ao enviar: $error');
      _showMessage('Não foi possível enviar o comentário.');
    } finally {
      if (mounted) {
        setState(() => _isSendingComment = false);
      }
    }
  }

  Future<void> _openLessonAsset(_StudentLessonAsset asset) async {
    var url = asset.signedUrl;

    if (url == null || url.isEmpty) {
      url = await _resolveLessonMaterialUrl(asset.storagePath);
    }

    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !uri.hasScheme) {
      _showMessage('Não foi possível abrir este arquivo.');
      return;
    }

    try {
      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }

      if (!opened) {
        _showMessage('Não foi possível abrir este arquivo.');
      }
    } catch (_) {
      _showMessage('Não foi possível abrir este arquivo.');
    }
  }

  Future<void> _registerLessonOpened() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }

    await _saveProgress(
      seconds: bundle.currentProgress?.progressSeconds ?? 0,
      completed: bundle.currentProgress?.isCompleted ?? false,
      showFeedback: false,
    );
  }

  Future<void> _preparePrimaryContent(_StudentLesson lesson) async {
    if (mounted) {
      setState(() {
        _isPreparingContent = true;
        _playerError = null;
      });
    }

    try {
      final contentSources = await _resolvePrimaryContentSources(lesson);

      if (!mounted || _bundle?.currentLesson.id != lesson.id) {
        return;
      }

      if (contentSources.isEmpty) {
        setState(() {
          _primaryContentUrl = null;
          _isPreparingContent = false;
        });
        return;
      }

      if (_isPlayableMedia(lesson)) {
        final playableSources = contentSources
            .where((source) => source.canPlayNatively)
            .toList(growable: false);

        if (playableSources.isEmpty) {
          setState(() {
            _primaryContentUrl = contentSources.first.url;
            _isPreparingContent = false;
            _playerError =
                'O link cadastrado não é um arquivo de mídia reproduzível no player.';
          });
          return;
        }

        await _disposePlayer();

        _playableContentSources = List<_LessonContentSource>.unmodifiable(
          playableSources,
        );
        _activePlayableContentIndex = -1;
        _isRecoveringPlayer = false;

        final initialized = await _initializeNextPlayableContentSource();

        if (!mounted || _bundle?.currentLesson.id != lesson.id) {
          return;
        }

        if (!initialized) {
          setState(() {
            _primaryContentUrl = contentSources.first.url;
            _isPreparingContent = false;
            _playerError = 'Não foi possível preparar o conteúdo desta aula.';
          });
        }
        return;
      }

      setState(() {
        _primaryContentUrl = contentSources.first.url;
        _isPreparingContent = false;
      });
    } catch (_) {
      if (!mounted || _bundle?.currentLesson.id != lesson.id) {
        return;
      }

      setState(() {
        _primaryContentUrl = null;
        _isPreparingContent = false;
        _playerError = 'Não foi possível preparar o conteúdo desta aula.';
      });
    }
  }

  Future<bool> _initializeNextPlayableContentSource() async {
    final bundle = _bundle;
    if (bundle == null) {
      return false;
    }

    for (
      var index = _activePlayableContentIndex + 1;
      index < _playableContentSources.length;
      index++
    ) {
      final source = _playableContentSources[index];
      VideoPlayerController? controller;

      try {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(source.url),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
            preventsDisplaySleepDuringVideoPlayback: true,
          ),
        );
        await controller.initialize();
        await controller.setVolume(1.0);

        if (controller.value.hasError) {
          throw StateError(
            controller.value.errorDescription ?? 'video_player_source_error',
          );
        }

        final savedSeconds = bundle.currentProgress?.progressSeconds ?? 0;
        final durationSeconds = controller.value.duration.inSeconds;

        if (savedSeconds > 0 && savedSeconds < durationSeconds) {
          await controller.seekTo(Duration(seconds: savedSeconds));
        }

        if (!mounted || _bundle?.currentLesson.id != bundle.currentLesson.id) {
          await controller.dispose();
          return false;
        }

        controller.addListener(_handlePlayerChanged);

        setState(() {
          _playerController = controller;
          _primaryContentUrl = source.url;
          _isPreparingContent = false;
          _lastSavedSeconds = savedSeconds;
          _activePlayableContentIndex = index;
          _playerError = null;
        });

        return true;
      } catch (error) {
        debugPrint(
          'Player da aula: fonte ${index + 1} rejeitada pelo servidor: $error',
        );

        if (controller != null) {
          await controller.dispose();
        }
      }
    }

    return false;
  }

  Future<void> _recoverFromPlayerFailure(String description) async {
    if (_isRecoveringPlayer) {
      return;
    }

    _isRecoveringPlayer = true;

    try {
      debugPrint('Player da aula: $description');

      await _disposePlayer();

      final recovered = await _initializeNextPlayableContentSource();

      if (!recovered && mounted) {
        setState(() {
          _isPreparingContent = false;
          _playerError = 'Não foi possível preparar o conteúdo desta aula.';
        });
      }
    } finally {
      _isRecoveringPlayer = false;
    }
  }

  Future<List<_LessonContentSource>> _resolvePrimaryContentSources(
    _StudentLesson lesson,
  ) async {
    final sources = <_LessonContentSource>[];
    final urls = <String>{};

    void addSource({required String? url, required bool canPlayNatively}) {
      final value = url?.trim() ?? '';

      if (value.isEmpty || !urls.add(value)) {
        return;
      }

      sources.add(
        _LessonContentSource(url: value, canPlayNatively: canPlayNatively),
      );
    }

    final primaryPath = lesson.primaryAssetPath?.trim() ?? '';

    if (primaryPath.isNotEmpty) {
      if (_isHttpUrl(primaryPath)) {
        addSource(
          url: primaryPath,
          canPlayNatively: _isDirectMediaUrl(primaryPath),
        );
      } else {
        // Não assina o Storage diretamente no app. A rota web usa a service
        // role e aplica a mesma normalização de caminho já validada no site.
        final signedUrl = await _requestWebsiteStorageUrl(
          bucket: 'lesson-content',
          path: primaryPath,
        );

        addSource(url: signedUrl, canPlayNatively: true);
      }
    }

    // Vídeo por URL ou gravação já resolvida como arquivo de mídia direto.
    // Links de páginas (Zoom, YouTube, Vimeo etc.) não são enviados ao player
    // nativo porque não são streams MP4/HLS reproduzíveis pelo AVPlayer/ExoPlayer.
    final candidates = [
      lesson.videoUrl,
      lesson.zoomRecordingUrl,
      lesson.externalUrl,
    ];

    for (final candidate in candidates) {
      final resolved = await _resolveExternalContentUrl(candidate);

      if (resolved == null || resolved.isEmpty) {
        continue;
      }

      addSource(url: resolved, canPlayNatively: _isDirectMediaUrl(resolved));
    }

    return sources;
  }

  Future<String?> _resolveExternalContentUrl(String? candidate) async {
    final value = candidate?.trim() ?? '';

    if (value.isEmpty) {
      return null;
    }

    if (_isHttpUrl(value)) {
      return value;
    }

    return _requestWebsiteStorageUrl(
      bucket: _storageBucketHint(value),
      path: value,
    );
  }

  String _storageBucketHint(String path) {
    final normalized = path.trim().replaceFirst(RegExp(r'^/+'), '');

    if (normalized.startsWith('lesson-materials/')) {
      return 'lesson-materials';
    }

    if (normalized.startsWith('materials/')) {
      return 'materials';
    }

    if (normalized.startsWith('covers/')) {
      return 'covers';
    }

    return 'lesson-content';
  }

  Future<String?> _requestWebsiteStorageUrl({
    required String bucket,
    required String path,
  }) async {
    final cleanPath = path.trim();

    if (cleanPath.isEmpty) {
      return null;
    }

    final client = HttpClient();

    try {
      final request = await client
          .postUrl(Uri.parse(_studentStorageUrlEndpoint))
          .timeout(const Duration(seconds: 15));

      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(
        jsonEncode({
          'bucket': bucket,
          'path': cleanPath,
          'expiresIn': 60 * 60 * 6,
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Player da aula: a rota de mídia retornou HTTP ${response.statusCode} '
          'para o bucket $bucket.',
        );
        return null;
      }

      final decoded = jsonDecode(responseBody);

      if (decoded is! Map) {
        debugPrint('Player da aula: resposta de mídia inválida.');
        return null;
      }

      final signedUrl = decoded['signedUrl']?.toString().trim() ?? '';

      if (signedUrl.isEmpty) {
        debugPrint('Player da aula: rota de mídia não retornou signedUrl.');
        return null;
      }

      return signedUrl;
    } on TimeoutException {
      debugPrint(
        'Player da aula: a rota de mídia excedeu o tempo de resposta.',
      );
      return null;
    } on SocketException {
      debugPrint('Player da aula: não foi possível alcançar a rota de mídia.');
      return null;
    } on FormatException {
      debugPrint('Player da aula: a rota de mídia retornou JSON inválido.');
      return null;
    } catch (error) {
      debugPrint('Player da aula: falha ao solicitar a mídia: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _handlePlayerChanged() {
    final controller = _playerController;
    final bundle = _bundle;

    if (controller == null ||
        bundle == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (controller.value.hasError) {
      unawaited(
        _recoverFromPlayerFailure(
          controller.value.errorDescription ?? 'video_player_source_error',
        ),
      );
      return;
    }

    final position = controller.value.position;
    final duration = controller.value.duration;
    final seconds = position.inSeconds;

    if (seconds >= _lastSavedSeconds + 15) {
      _lastSavedSeconds = seconds;
      unawaited(
        _saveProgress(
          seconds: seconds,
          completed: bundle.currentProgress?.isCompleted ?? false,
          showFeedback: false,
        ),
      );
    }

    final finished =
        duration > Duration.zero &&
        position >= duration - const Duration(milliseconds: 450) &&
        !controller.value.isPlaying;

    if (finished && !(bundle.currentProgress?.isCompleted ?? false)) {
      unawaited(
        _saveProgress(
          seconds: duration.inSeconds,
          completed: true,
          showFeedback: false,
        ),
      );
    }
  }

  Future<void> _saveProgress({
    required int seconds,
    required bool completed,
    required bool showFeedback,
  }) async {
    final bundle = _bundle;
    final user = _supabase.auth.currentUser;

    if (bundle == null || user == null || _isSavingProgress) {
      return;
    }

    if (mounted) {
      setState(() => _isSavingProgress = true);
    }

    final currentProgress = bundle.currentProgress;
    final safeSeconds = seconds > (currentProgress?.progressSeconds ?? 0)
        ? seconds
        : (currentProgress?.progressSeconds ?? 0);
    final shouldComplete = completed || (currentProgress?.isCompleted ?? false);
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      final dynamic response = await _supabase
          .from('lesson_progress')
          .upsert({
            'lesson_id': bundle.currentLesson.id,
            'student_id': user.id,
            'progress_seconds': safeSeconds,
            'completed_at': shouldComplete
                ? (currentProgress?.completedAt ?? now)
                : null,
            'last_watched_at': now,
            'updated_at': now,
          }, onConflict: 'lesson_id,student_id')
          .select(
            'id,lesson_id,student_id,progress_seconds,completed_at,'
            'last_watched_at,updated_at',
          )
          .maybeSingle();

      if (response is! Map) {
        throw StateError('progress_not_returned');
      }

      final updated = _StudentLessonProgress.fromMap(
        Map<String, dynamic>.from(response),
      );

      if (!mounted || _bundle?.currentLesson.id != bundle.currentLesson.id) {
        return;
      }

      setState(() {
        _bundle = bundle.copyWithProgress(updated);
        _lastSavedSeconds = updated.progressSeconds;
      });

      if (showFeedback) {
        _showMessage(
          updated.isCompleted
              ? 'Aula concluída com sucesso.'
              : 'Seu progresso foi salvo.',
        );
      }
    } catch (_) {
      if (showFeedback) {
        _showMessage('Não foi possível salvar o progresso desta aula.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingProgress = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF151515),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(StudentAppRoutes.courses, (route) => false);
  }

  void _openLesson(_StudentLesson lesson) {
    final bundle = _bundle;
    if (bundle == null || lesson.id == bundle.currentLesson.id) {
      return;
    }

    final currentSeconds =
        _playerController?.value.position.inSeconds ??
        bundle.currentProgress?.progressSeconds ??
        0;

    unawaited(
      _saveProgress(
        seconds: currentSeconds,
        completed: bundle.currentProgress?.isCompleted ?? false,
        showFeedback: false,
      ),
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => StudentLessonScreen(lessonId: lesson.id),
      ),
    );
  }

  Future<void> _completeOrAdvance() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }

    final next = bundle.nextLesson;

    if (bundle.currentProgress?.isCompleted ?? false) {
      if (next != null) {
        _openLesson(next);
      } else {
        _showMessage(
          'Todas as aulas foram concluídas. A avaliação será liberada conforme as regras do curso.',
        );
      }
      return;
    }

    await _saveProgress(
      seconds: bundle.currentLesson.durationSeconds,
      completed: true,
      showFeedback: true,
    );
  }

  Future<void> _copyContentLink() async {
    final url = _primaryContentUrl;
    if (url == null || url.isEmpty) {
      _showMessage('O link deste conteúdo não está disponível.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));
    _showMessage('Link do conteúdo copiado.');
  }

  Future<void> _openFullscreenPlayer() async {
    final controller = _playerController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _LessonFullscreenPlayer(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.courses,
      scrollController: _scrollController,
      backgroundColor: _lessonBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadLesson,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 114)),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (_bundle != null)
              SliverToBoxAdapter(child: _buildLessonContent(_bundle!)),
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 122),
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
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: _goBack,
            tooltip: 'Voltar',
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(height: 30),
          const Icon(
            Icons.play_circle_outline_rounded,
            color: UnlColors.gold,
            size: 40,
          ),
          const SizedBox(height: 17),
          const Text(
            'Não foi possível abrir esta aula.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _loadError ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontSize: 14,
              height: 1.48,
            ),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _loadLesson,
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

  Widget _buildLessonContent(_StudentLessonBundle bundle) {
    final current = bundle.currentLesson;
    final completedCount = bundle.completedLessonCount;
    final totalCount = bundle.orderedLessons.length;
    final coursePercent = totalCount == 0
        ? 0
        : ((completedCount / totalCount) * 100).round();
    final previous = bundle.previousLesson;
    final next = bundle.nextLesson;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _goBack,
                tooltip: 'Voltar para o curso',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bundle.courseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.56),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            bundle.currentModuleTitle.toUpperCase(),
            style: const TextStyle(
              color: UnlColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            current.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.55,
            ),
          ),
          if (current.description != null &&
              current.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              current.description!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.54),
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 22),
          _buildPrimaryContent(current),
          const SizedBox(height: 22),
          Row(
            children: [
              Icon(_contentIcon(current), color: UnlColors.gold, size: 18),
              const SizedBox(width: 8),
              Text(
                _contentLabel(current),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.70),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (current.durationSeconds > 0) ...[
                const SizedBox(width: 10),
                Text(
                  _formatDuration(current.durationSeconds),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                bundle.currentProgress?.isCompleted ?? false
                    ? Icons.check_circle_rounded
                    : Icons.play_circle_outline_rounded,
                color: bundle.currentProgress?.isCompleted ?? false
                    ? UnlColors.gold
                    : Colors.white.withOpacity(0.46),
                size: 21,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            '$completedCount de $totalCount aulas concluídas',
            style: TextStyle(
              color: Colors.white.withOpacity(0.60),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: coursePercent / 100,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.09),
              valueColor: const AlwaysStoppedAnimation<Color>(UnlColors.gold),
            ),
          ),
          const SizedBox(height: 31),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSavingProgress ? null : _completeOrAdvance,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: UnlColors.gold,
                disabledBackgroundColor: UnlColors.gold.withOpacity(0.38),
                foregroundColor: Colors.black,
                disabledForegroundColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isSavingProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.2,
                      ),
                    )
                  : Icon(
                      bundle.currentProgress?.isCompleted ?? false
                          ? (next == null
                                ? Icons.check_circle_outline_rounded
                                : Icons.arrow_forward_rounded)
                          : Icons.check_rounded,
                      size: 21,
                    ),
              label: Text(
                _isSavingProgress
                    ? 'Salvando...'
                    : _completionLabel(bundle, next),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: previous == null
                      ? null
                      : () => _openLesson(previous),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white24,
                    side: BorderSide(
                      color: previous == null
                          ? Colors.white.withOpacity(0.07)
                          : Colors.white.withOpacity(0.16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text(
                    'Anterior',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: next == null ? null : () => _openLesson(next),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: UnlColors.gold,
                    disabledForegroundColor: Colors.white24,
                    side: BorderSide(
                      color: next == null
                          ? Colors.white.withOpacity(0.07)
                          : UnlColors.gold.withOpacity(0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text(
                    'Próxima',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 34),
          _buildLessonList(bundle),
          const SizedBox(height: 34),
          _buildLessonAssetsSection(bundle.assets),
          const SizedBox(height: 34),
          _buildLessonCommentsSection(bundle.comments),
        ],
      ),
    );
  }

  Widget _buildPrimaryContent(_StudentLesson lesson) {
    if (_isTextLesson(lesson)) {
      return _buildTextContent(lesson);
    }

    if (_isImageLesson(lesson)) {
      return _buildImageContent(lesson);
    }

    if (_isPlayableMedia(lesson)) {
      return _buildMediaContent(lesson);
    }

    return _buildDocumentOrLinkContent(lesson);
  }

  Widget _buildTextContent(_StudentLesson lesson) {
    final body = lesson.contentBody?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _lessonSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: body.isEmpty
          ? Text(
              'Esta aula ainda não possui conteúdo textual publicado.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontSize: 14,
                height: 1.55,
              ),
            )
          : SelectableText(
              body,
              style: TextStyle(
                color: Colors.white.withOpacity(0.83),
                fontSize: 16,
                height: 1.7,
                fontWeight: FontWeight.w400,
              ),
            ),
    );
  }

  Widget _buildImageContent(_StudentLesson lesson) {
    if (_isPreparingContent) {
      return _buildContentLoading();
    }

    final url = _primaryContentUrl;
    if (url == null || url.isEmpty) {
      return _buildUnavailableContent(
        icon: Icons.image_outlined,
        title: 'Imagem indisponível',
        description:
            _playerError ??
            'A imagem principal desta aula ainda não está disponível.',
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        color: Colors.black,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildUnavailableContent(
            icon: Icons.broken_image_outlined,
            title: 'Não foi possível carregar a imagem',
            description: 'Atualize a página e tente novamente.',
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent(_StudentLesson lesson) {
    if (_isPreparingContent) {
      return _buildContentLoading();
    }

    final controller = _playerController;
    if (controller == null || !controller.value.isInitialized) {
      return _buildUnavailableContent(
        icon: _isAudioLesson(lesson)
            ? Icons.headphones_rounded
            : Icons.play_circle_outline_rounded,
        title: _isAudioLesson(lesson)
            ? 'Áudio indisponível'
            : 'Vídeo indisponível',
        description:
            _playerError ??
            'O arquivo desta aula não pôde ser reproduzido agora.',
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final position = value.position > duration ? duration : value.position;

        if (_isAudioLesson(lesson)) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _lessonSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: UnlColors.gold.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.headphones_rounded,
                    color: UnlColors.gold,
                    size: 29,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  value.isPlaying
                      ? 'Reproduzindo aula em áudio'
                      : 'Aula em áudio',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _buildPlayerProgress(controller, position, duration),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatClock(position),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatClock(duration),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                IconButton(
                  onPressed: () {
                    if (value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  iconSize: 34,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: UnlColors.gold,
                  ),
                ),
              ],
            ),
          );
        }

        final aspectRatio = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: Colors.black,
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: VideoPlayer(controller),
                ),
                Container(
                  color: const Color(0xFF0A0A0A),
                  child: Column(
                    children: [
                      _buildPlayerProgress(controller, position, duration),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                if (value.isPlaying) {
                                  controller.pause();
                                } else {
                                  controller.play();
                                }
                              },
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${_formatClock(position)} / ${_formatClock(duration)}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _openFullscreenPlayer,
                              tooltip: 'Tela cheia',
                              icon: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerProgress(
    VideoPlayerController controller,
    Duration position,
    Duration duration,
  ) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
      ),
      child: Slider(
        value: duration.inMilliseconds <= 0
            ? 0
            : position.inMilliseconds
                  .clamp(0, duration.inMilliseconds)
                  .toDouble(),
        min: 0,
        max: duration.inMilliseconds <= 0
            ? 1
            : duration.inMilliseconds.toDouble(),
        activeColor: UnlColors.gold,
        inactiveColor: Colors.white.withOpacity(0.16),
        onChanged: duration.inMilliseconds <= 0
            ? null
            : (value) {
                controller.seekTo(Duration(milliseconds: value.round()));
              },
      ),
    );
  }

  Widget _buildDocumentOrLinkContent(_StudentLesson lesson) {
    if (_isPreparingContent) {
      return _buildContentLoading();
    }

    final isLive = _isLiveLesson(lesson);
    final isPresentation = _isPresentationLesson(lesson);
    final isPdf = _isPdfLesson(lesson);
    final hasLink = _primaryContentUrl?.isNotEmpty == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _lessonSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLive
                ? Icons.live_tv_outlined
                : isPresentation
                ? Icons.slideshow_outlined
                : isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.link_rounded,
            color: UnlColors.gold,
            size: 33,
          ),
          const SizedBox(height: 15),
          Text(
            isLive
                ? 'Aula ao vivo'
                : isPresentation
                ? 'Aula em slides'
                : isPdf
                ? 'Material em PDF'
                : 'Conteúdo externo',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasLink
                ? 'Este conteúdo utiliza um arquivo ou link externo. Toque abaixo para copiar o acesso.'
                : 'O acesso principal desta aula ainda não está disponível.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (hasLink) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _copyContentLink,
              style: OutlinedButton.styleFrom(
                foregroundColor: UnlColors.gold,
                side: BorderSide(color: UnlColors.gold.withOpacity(0.34)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text(
                'Copiar link do conteúdo',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContentLoading() {
    return Container(
      height: 220,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _lessonSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: UnlColors.gold, strokeWidth: 2.2),
          SizedBox(height: 15),
          Text(
            'Preparando conteúdo...',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableContent({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      height: 220,
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _lessonSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: UnlColors.gold, size: 35),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonAssetsSection(List<_StudentLessonAsset> assets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Arquivos',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 11),
        if (assets.isEmpty)
          _buildLessonSectionEmpty(
            icon: Icons.folder_open_outlined,
            message: 'Esta aula não possui arquivos complementares.',
          )
        else
          for (final asset in assets) ...[
            _buildLessonAssetCard(asset),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildLessonAssetCard(_StudentLessonAsset asset) {
    final title = asset.title?.isNotEmpty == true
        ? asset.title!
        : (asset.fileName?.isNotEmpty == true
              ? asset.fileName!
              : 'Material complementar');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openLessonAsset(asset),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            color: _lessonSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: UnlColors.gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(_assetIcon(asset), color: UnlColors.gold, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _assetMetaLabel(asset),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.open_in_new_rounded,
                color: UnlColors.gold,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLessonCommentsSection(List<_StudentLessonComment> comments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comentários',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Envie sua dúvida ou contribuição. Ela será publicada após a aprovação do ADM.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.52),
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _lessonSurface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: _commentController,
                minLines: 3,
                maxLines: 6,
                maxLength: 1200,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.42,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  hintText: 'Escreva um comentário sobre esta aula...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.34),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  counterStyle: TextStyle(
                    color: Colors.white.withOpacity(0.32),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _isSendingComment ? null : _submitLessonComment,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  backgroundColor: UnlColors.gold,
                  disabledBackgroundColor: UnlColors.gold.withOpacity(0.36),
                  foregroundColor: Colors.black,
                  disabledForegroundColor: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isSendingComment
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _isSendingComment ? 'Enviando...' : 'Enviar comentário',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (comments.isEmpty)
          _buildLessonSectionEmpty(
            icon: Icons.forum_outlined,
            message: 'Ainda não há comentários aprovados nesta aula.',
          )
        else
          for (var index = 0; index < comments.length; index++) ...[
            _buildLessonCommentCard(comments[index]),
            if (index < comments.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildLessonCommentCard(_StudentLessonComment comment) {
    final avatarUrl = comment.studentAvatarUrl?.trim() ?? '';
    final initials = _initials(comment.studentName);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _lessonSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 37,
            height: 37,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: UnlColors.gold.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: avatarUrl.isEmpty
                ? Text(
                    initials,
                    style: const TextStyle(
                      color: UnlColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Text(
                      initials,
                      style: const TextStyle(
                        color: UnlColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCommentDate(comment.createdAt),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.38),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  comment.comment,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.76),
                    fontSize: 13.5,
                    height: 1.48,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (comment.adminNote != null &&
                    comment.adminNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: UnlColors.gold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: UnlColors.gold.withOpacity(0.28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resposta do ADM',
                          style: TextStyle(
                            color: UnlColors.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.45,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          comment.adminNote!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.84),
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonSectionEmpty({
    required IconData icon,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      decoration: BoxDecoration(
        color: _lessonSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.34), size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withOpacity(0.44),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _assetIcon(_StudentLessonAsset asset) {
    final value =
        '${asset.assetType} ${asset.mimeType ?? ''} ${asset.fileName ?? ''}'
            .toLowerCase();

    if (value.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (value.contains('power') ||
        value.contains('presentation') ||
        value.contains('ppt')) {
      return Icons.slideshow_outlined;
    }
    if (value.contains('video')) return Icons.play_circle_outline_rounded;
    if (value.contains('audio')) return Icons.headphones_rounded;
    if (value.contains('image') ||
        value.contains('.png') ||
        value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.webp')) {
      return Icons.image_outlined;
    }
    if (value.contains('link') || value.contains('url')) {
      return Icons.link_rounded;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _assetMetaLabel(_StudentLessonAsset asset) {
    final labels = <String>[
      if (asset.assetType.trim().isNotEmpty) _assetTypeLabel(asset.assetType),
      if (asset.sizeBytes > 0) _formatFileSize(asset.sizeBytes),
    ];

    return labels.isEmpty ? 'Arquivo complementar' : labels.join(' • ');
  }

  String _assetTypeLabel(String value) {
    final type = value.trim().toLowerCase();

    if (type.contains('pdf')) return 'PDF';
    if (type.contains('power') || type.contains('ppt')) return 'Apresentação';
    if (type.contains('video')) return 'Vídeo';
    if (type.contains('audio')) return 'Áudio';
    if (type.contains('image') || type.contains('imagem')) return 'Imagem';
    if (type.contains('link')) return 'Link';
    return 'Material';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Arquivo';

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).ceil()} KB';
    }

    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatCommentDate(String value) {
    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      return '';
    }

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/${local.year} • $hour:$minute';
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    return '${parts.first.substring(0, 1)}'
            '${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Widget _buildLessonList(_StudentLessonBundle bundle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AULAS DO CURSO',
          style: TextStyle(
            color: UnlColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 12),
        for (final module in bundle.modules) ...[
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: module.id == bundle.currentLesson.moduleId,
              iconColor: UnlColors.gold,
              collapsedIconColor: Colors.white54,
              title: Text(
                module.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${bundle.lessonsForModule(module.id).length} aulas',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.46),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                for (final lesson in bundle.lessonsForModule(module.id))
                  _buildLessonListItem(bundle, lesson),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
        ],
      ],
    );
  }

  Widget _buildLessonListItem(
    _StudentLessonBundle bundle,
    _StudentLesson lesson,
  ) {
    final isCurrent = lesson.id == bundle.currentLesson.id;
    final isComplete =
        bundle.progressByLessonId[lesson.id]?.isCompleted ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isCurrent ? null : () => _openLesson(lesson),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Icon(
                isComplete
                    ? Icons.check_circle_rounded
                    : isCurrent
                    ? Icons.play_circle_fill_rounded
                    : _contentIcon(lesson),
                color: isComplete || isCurrent
                    ? UnlColors.gold
                    : Colors.white.withOpacity(0.42),
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  lesson.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent
                        ? Colors.white
                        : Colors.white.withOpacity(0.70),
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w700,
                  ),
                ),
              ),
              if (lesson.durationSeconds > 0) ...[
                const SizedBox(width: 12),
                Text(
                  _formatDuration(lesson.durationSeconds),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _completionLabel(_StudentLessonBundle bundle, _StudentLesson? next) {
    if (!(bundle.currentProgress?.isCompleted ?? false)) {
      return 'Concluir aula';
    }

    if (next != null) {
      return 'Ir para próxima aula';
    }

    return 'Aula concluída';
  }

  bool _isPlayableMedia(_StudentLesson lesson) {
    return _isVideoLesson(lesson) || _isAudioLesson(lesson);
  }

  bool _isVideoLesson(_StudentLesson lesson) {
    final value =
        '${lesson.contentType} ${lesson.primaryAssetMimeType ?? ''} '
                '${lesson.primaryAssetName ?? ''} ${lesson.videoUrl ?? ''}'
            .toLowerCase();

    return value.contains('video') ||
        value.contains('.mp4') ||
        value.contains('.mov') ||
        value.contains('.webm') ||
        value.contains('.m4v');
  }

  bool _isAudioLesson(_StudentLesson lesson) {
    final value =
        '${lesson.contentType} ${lesson.primaryAssetMimeType ?? ''} '
                '${lesson.primaryAssetName ?? ''} ${lesson.videoUrl ?? ''}'
            .toLowerCase();

    return value.contains('audio') ||
        value.contains('.mp3') ||
        value.contains('.m4a') ||
        value.contains('.aac') ||
        value.contains('.wav');
  }

  bool _isImageLesson(_StudentLesson lesson) {
    final value =
        '${lesson.contentType} ${lesson.primaryAssetMimeType ?? ''} '
                '${lesson.primaryAssetName ?? ''}'
            .toLowerCase();

    return value.contains('image') ||
        value.contains('imagem') ||
        value.contains('.png') ||
        value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.webp');
  }

  bool _isTextLesson(_StudentLesson lesson) {
    final value = lesson.contentType.toLowerCase();
    return value.contains('text') || value.contains('texto');
  }

  bool _isPdfLesson(_StudentLesson lesson) {
    final value =
        '${lesson.contentType} ${lesson.primaryAssetMimeType ?? ''} '
                '${lesson.primaryAssetName ?? ''}'
            .toLowerCase();
    return value.contains('pdf');
  }

  bool _isPresentationLesson(_StudentLesson lesson) {
    final value =
        '${lesson.contentType} ${lesson.primaryAssetMimeType ?? ''} '
                '${lesson.primaryAssetName ?? ''}'
            .toLowerCase();
    return value.contains('power') ||
        value.contains('presentation') ||
        value.contains('ppt');
  }

  bool _isLiveLesson(_StudentLesson lesson) {
    final value =
        '${lesson.contentType} ${lesson.sourceMode ?? ''} '
                '${lesson.liveProvider ?? ''} ${lesson.meetingSdk ?? ''}'
            .toLowerCase();
    return value.contains('live') ||
        value.contains('ao_vivo') ||
        value.contains('zoom');
  }

  IconData _contentIcon(_StudentLesson lesson) {
    if (_isVideoLesson(lesson)) return Icons.play_circle_outline_rounded;
    if (_isAudioLesson(lesson)) return Icons.headphones_rounded;
    if (_isImageLesson(lesson)) return Icons.image_outlined;
    if (_isPdfLesson(lesson)) return Icons.picture_as_pdf_outlined;
    if (_isPresentationLesson(lesson)) return Icons.slideshow_outlined;
    if (_isLiveLesson(lesson)) return Icons.live_tv_outlined;
    if (_isTextLesson(lesson)) return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _contentLabel(_StudentLesson lesson) {
    if (_isVideoLesson(lesson)) return 'Vídeo aula';
    if (_isAudioLesson(lesson)) return 'Aula em áudio';
    if (_isImageLesson(lesson)) return 'Aula em imagem';
    if (_isPdfLesson(lesson)) return 'Material PDF';
    if (_isPresentationLesson(lesson)) return 'Aula em slides';
    if (_isLiveLesson(lesson)) return 'Aula ao vivo';
    if (_isTextLesson(lesson)) return 'Aula em texto';
    return 'Conteúdo da aula';
  }

  bool _isHttpUrl(String value) {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  bool _isDirectMediaUrl(String value) {
    final normalized = value.toLowerCase().split('?').first;

    return normalized.endsWith('.mp4') ||
        normalized.endsWith('.webm') ||
        normalized.endsWith('.ogg') ||
        normalized.endsWith('.mov') ||
        normalized.endsWith('.m4v') ||
        normalized.endsWith('.mp3') ||
        normalized.endsWith('.m4a') ||
        normalized.endsWith('.aac') ||
        normalized.endsWith('.wav') ||
        normalized.contains('/storage/v1/object/');
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

  String _formatClock(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
}

class _LessonContentSource {
  const _LessonContentSource({
    required this.url,
    required this.canPlayNatively,
  });

  final String url;
  final bool canPlayNatively;
}

class _LessonFullscreenPlayer extends StatefulWidget {
  const _LessonFullscreenPlayer({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_LessonFullscreenPlayer> createState() =>
      _LessonFullscreenPlayerState();
}

class _LessonFullscreenPlayerState extends State<_LessonFullscreenPlayer> {
  bool _forceLandscapeLeft = true;

  @override
  void initState() {
    super.initState();
    unawaited(_enterFullscreen());
  }

  @override
  void dispose() {
    unawaited(_restoreApplicationOrientation());
    super.dispose();
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreApplicationOrientation() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _rotateFullscreen() async {
    _forceLandscapeLeft = !_forceLandscapeLeft;

    await SystemChrome.setPreferredOrientations([
      _forceLandscapeLeft
          ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.landscapeRight,
    ]);

    if (mounted) {
      setState(() {});
    }
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final duration = value.duration;
            final position = value.position > duration
                ? duration
                : value.position;
            final aspectRatio = value.aspectRatio > 0
                ? value.aspectRatio
                : 16 / 9;

            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: IconButton(
                    onPressed: _close,
                    tooltip: 'Sair da tela cheia',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.52),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: UnlColors.gold,
                            bufferedColor: Color(0x77FFFFFF),
                            backgroundColor: Color(0x33FFFFFF),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                if (value.isPlaying) {
                                  controller.pause();
                                } else {
                                  controller.play();
                                }
                              },
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${_formatFullscreenClock(position)} / '
                              '${_formatFullscreenClock(duration)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _rotateFullscreen,
                              tooltip: 'Rotacionar vídeo',
                              icon: const Icon(
                                Icons.screen_rotation_alt_rounded,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              onPressed: _close,
                              tooltip: 'Sair da tela cheia',
                              icon: const Icon(
                                Icons.fullscreen_exit_rounded,
                                color: Colors.white,
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
          },
        ),
      ),
    );
  }

  String _formatFullscreenClock(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _StudentLessonAsset {
  const _StudentLessonAsset({
    required this.id,
    required this.lessonId,
    required this.assetType,
    required this.title,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.sortOrder,
    required this.fileName,
    required this.signedUrl,
  });

  final String id;
  final String lessonId;
  final String assetType;
  final String? title;
  final String storagePath;
  final String? mimeType;
  final int sizeBytes;
  final int sortOrder;
  final String? fileName;
  final String? signedUrl;

  factory _StudentLessonAsset.fromMap(Map<String, dynamic> map) {
    return _StudentLessonAsset(
      id: map['id']?.toString() ?? '',
      lessonId: map['lesson_id']?.toString() ?? '',
      assetType: map['asset_type']?.toString().trim() ?? '',
      title: _cleanText(map['title']),
      storagePath: map['storage_path']?.toString().trim() ?? '',
      mimeType: _cleanText(map['mime_type']),
      sizeBytes: _readInt(map['size_bytes']),
      sortOrder: _readInt(map['sort_order']),
      fileName: _cleanText(map['file_name']),
      signedUrl: _cleanText(map['signed_url']),
    );
  }

  _StudentLessonAsset copyWithSignedUrl(String? value) {
    return _StudentLessonAsset(
      id: id,
      lessonId: lessonId,
      assetType: assetType,
      title: title,
      storagePath: storagePath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      sortOrder: sortOrder,
      fileName: fileName,
      signedUrl: value,
    );
  }
}

class _StudentLessonComment {
  const _StudentLessonComment({
    required this.id,
    required this.lessonId,
    required this.studentId,
    required this.studentName,
    required this.studentAvatarUrl,
    required this.comment,
    required this.status,
    required this.adminNote,
    required this.createdAt,
  });

  final String id;
  final String lessonId;
  final String? studentId;
  final String studentName;
  final String? studentAvatarUrl;
  final String comment;
  final String status;
  final String? adminNote;
  final String createdAt;

  factory _StudentLessonComment.fromMap(Map<String, dynamic> map) {
    return _StudentLessonComment(
      id: map['id']?.toString() ?? '',
      lessonId: map['lesson_id']?.toString() ?? '',
      studentId: _cleanText(map['student_id']),
      studentName: _cleanText(map['student_name']) ?? 'Aluno',
      studentAvatarUrl: _cleanText(map['student_avatar_url']),
      comment: _cleanText(map['comment']) ?? '',
      status: _cleanText(map['status']) ?? '',
      adminNote: _cleanText(map['admin_note']),
      createdAt: _cleanText(map['created_at']) ?? '',
    );
  }
}

class _StudentProfileData {
  const _StudentProfileData({required this.fullName, required this.avatarUrl});

  final String? fullName;
  final String? avatarUrl;

  factory _StudentProfileData.fromMap(Map<String, dynamic> map) {
    return _StudentProfileData(
      fullName: _cleanText(map['full_name']),
      avatarUrl: _cleanText(map['avatar_url']),
    );
  }
}

class _StudentLessonBundle {
  const _StudentLessonBundle({
    required this.courseId,
    required this.courseTitle,
    required this.currentModuleTitle,
    required this.currentLesson,
    required this.modules,
    required this.lessons,
    required this.progressByLessonId,
    required this.assets,
    required this.comments,
  });

  final String courseId;
  final String courseTitle;
  final String currentModuleTitle;
  final _StudentLesson currentLesson;
  final List<_StudentLessonModule> modules;
  final List<_StudentLesson> lessons;
  final Map<String, _StudentLessonProgress> progressByLessonId;
  final List<_StudentLessonAsset> assets;
  final List<_StudentLessonComment> comments;

  List<_StudentLesson> get orderedLessons {
    final moduleOrder = <String, int>{
      for (var index = 0; index < modules.length; index++)
        modules[index].id: index,
    };

    final items = List<_StudentLesson>.from(lessons);
    items.sort((first, second) {
      final firstModule = moduleOrder[first.moduleId] ?? 999999;
      final secondModule = moduleOrder[second.moduleId] ?? 999999;

      if (firstModule != secondModule) {
        return firstModule.compareTo(secondModule);
      }

      return first.sortOrder.compareTo(second.sortOrder);
    });

    return items;
  }

  _StudentLessonProgress? get currentProgress =>
      progressByLessonId[currentLesson.id];

  int get completedLessonCount {
    return orderedLessons
        .where((lesson) => progressByLessonId[lesson.id]?.isCompleted ?? false)
        .length;
  }

  _StudentLesson? get previousLesson {
    final index = orderedLessons.indexWhere(
      (lesson) => lesson.id == currentLesson.id,
    );
    if (index <= 0) {
      return null;
    }
    return orderedLessons[index - 1];
  }

  _StudentLesson? get nextLesson {
    final index = orderedLessons.indexWhere(
      (lesson) => lesson.id == currentLesson.id,
    );
    if (index < 0 || index >= orderedLessons.length - 1) {
      return null;
    }
    return orderedLessons[index + 1];
  }

  List<_StudentLesson> lessonsForModule(String moduleId) {
    final items = lessons
        .where((lesson) => lesson.moduleId == moduleId)
        .toList();
    items.sort((first, second) => first.sortOrder.compareTo(second.sortOrder));
    return items;
  }

  _StudentLessonBundle copyWithProgress(_StudentLessonProgress progress) {
    return _StudentLessonBundle(
      courseId: courseId,
      courseTitle: courseTitle,
      currentModuleTitle: currentModuleTitle,
      currentLesson: currentLesson,
      modules: modules,
      lessons: lessons,
      progressByLessonId: {...progressByLessonId, progress.lessonId: progress},
      assets: assets,
      comments: comments,
    );
  }
}

class _StudentLessonModule {
  const _StudentLessonModule({
    required this.id,
    required this.courseId,
    required this.title,
    required this.description,
    required this.sortOrder,
  });

  final String id;
  final String courseId;
  final String title;
  final String? description;
  final int sortOrder;

  factory _StudentLessonModule.fromMap(Map<String, dynamic> map) {
    return _StudentLessonModule(
      id: map['id']?.toString() ?? '',
      courseId: map['course_id']?.toString() ?? '',
      title: map['title']?.toString().trim() ?? 'Módulo',
      description: _cleanText(map['description']),
      sortOrder: _readInt(map['sort_order']),
    );
  }
}

class _StudentLesson {
  const _StudentLesson({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.description,
    required this.sortOrder,
    required this.contentType,
    required this.videoProvider,
    required this.videoUrl,
    required this.durationSeconds,
    required this.sourceMode,
    required this.contentBody,
    required this.primaryAssetPath,
    required this.primaryAssetName,
    required this.primaryAssetMimeType,
    required this.externalUrl,
    required this.liveProvider,
    required this.meetingSdk,
    required this.zoomJoinUrl,
    required this.zoomRecordingUrl,
  });

  final String id;
  final String moduleId;
  final String title;
  final String? description;
  final int sortOrder;
  final String contentType;
  final String? videoProvider;
  final String? videoUrl;
  final int durationSeconds;
  final String? sourceMode;
  final String? contentBody;
  final String? primaryAssetPath;
  final String? primaryAssetName;
  final String? primaryAssetMimeType;
  final String? externalUrl;
  final String? liveProvider;
  final String? meetingSdk;
  final String? zoomJoinUrl;
  final String? zoomRecordingUrl;

  factory _StudentLesson.fromMap(Map<String, dynamic> map) {
    return _StudentLesson(
      id: map['id']?.toString() ?? '',
      moduleId: map['module_id']?.toString() ?? '',
      title: map['title']?.toString().trim() ?? 'Aula',
      description: _cleanText(map['description']),
      sortOrder: _readInt(map['sort_order']),
      contentType: map['content_type']?.toString().trim() ?? 'lesson',
      videoProvider: _cleanText(map['video_provider']),
      videoUrl: _cleanText(map['video_url']),
      durationSeconds: _readInt(map['duration_sec']),
      sourceMode: _cleanText(map['source_mode']),
      contentBody: _cleanText(map['content_body']),
      primaryAssetPath: _cleanText(map['primary_asset_path']),
      primaryAssetName: _cleanText(map['primary_asset_name']),
      primaryAssetMimeType: _cleanText(map['primary_asset_mime_type']),
      externalUrl: _cleanText(map['external_url']),
      liveProvider: _cleanText(map['live_provider']),
      meetingSdk: _cleanText(map['meeting_sdk']),
      zoomJoinUrl: _cleanText(map['zoom_join_url']),
      zoomRecordingUrl: _cleanText(map['zoom_recording_url']),
    );
  }
}

class _StudentLessonProgress {
  const _StudentLessonProgress({
    required this.id,
    required this.lessonId,
    required this.studentId,
    required this.progressSeconds,
    required this.completedAt,
  });

  final String id;
  final String lessonId;
  final String studentId;
  final int progressSeconds;
  final String? completedAt;

  bool get isCompleted => completedAt != null && completedAt!.isNotEmpty;

  factory _StudentLessonProgress.fromMap(Map<String, dynamic> map) {
    return _StudentLessonProgress(
      id: map['id']?.toString() ?? '',
      lessonId: map['lesson_id']?.toString() ?? '',
      studentId: map['student_id']?.toString() ?? '',
      progressSeconds: _readInt(map['progress_seconds']),
      completedAt: _cleanText(map['completed_at']),
    );
  }
}

String? _cleanText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

int _readInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
