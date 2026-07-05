// VERSÃO: v30
// Download validado com identificação real do formato do certificado.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _myCertificatesBackground = Color(0xFF050609);
const String _studentCertificatesEndpoint =
    'https://www.universidadedelideres.com.br/api/student/certificados';

enum _CertificatesViewState { loading, ready, error }

class StudentMyCertificatesScreen extends StatefulWidget {
  const StudentMyCertificatesScreen({super.key});

  static const String routeName = '/student-my-certificates';

  @override
  State<StudentMyCertificatesScreen> createState() =>
      _StudentMyCertificatesScreenState();
}

class _StudentMyCertificatesScreenState
    extends State<StudentMyCertificatesScreen> {
  final ScrollController _scrollController = ScrollController();

  List<_StudentCertificate> _certificates = const [];
  _CertificatesViewState _viewState = _CertificatesViewState.loading;
  String? _loadError;
  String? _deletingCertificateId;
  String? _downloadingCertificateId;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCertificates() async {
    if (mounted) {
      setState(() {
        _viewState = _CertificatesViewState.loading;
        _loadError = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw StateError('student_not_authenticated');
      }

      final certificates = await _fetchCertificates(user.id);

      if (!mounted) return;

      setState(() {
        _certificates = certificates;
        _viewState = _CertificatesViewState.ready;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _certificates = const [];
        _viewState = _CertificatesViewState.error;
        _loadError = 'Não foi possível carregar seus certificados agora.';
      });
    }
  }

  Future<List<_StudentCertificate>> _fetchCertificates(String studentId) async {
    final accessToken = _supabase.auth.currentSession?.accessToken.trim() ?? '';

    if (accessToken.isEmpty) {
      throw StateError('student_session_missing');
    }

    final client = HttpClient();

    try {
      final request = await client
          .getUrl(Uri.parse(_studentCertificatesEndpoint))
          .timeout(const Duration(seconds: 15));

      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'A rota de certificados retornou HTTP ${response.statusCode}.',
          uri: Uri.parse(_studentCertificatesEndpoint),
        );
      }

      final decoded = jsonDecode(responseBody);

      if (decoded is! Map) {
        throw const FormatException('Resposta de certificados inválida.');
      }

      final certificates =
          _rows(decoded['certificates'])
              .map((row) => _mapCertificate(row, 'issued_certificates'))
              .whereType<_StudentCertificate>()
              .toList()
            ..sort(
              (first, second) => second.issuedAt.compareTo(first.issuedAt),
            );

      return _resolveMissingContentTitles(certificates);
    } on TimeoutException {
      throw StateError('certificates_request_timeout');
    } on SocketException {
      throw StateError('certificates_network_error');
    } on FormatException {
      throw StateError('certificates_invalid_response');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _deleteCertificateFromWebsite(String certificateId) async {
    final accessToken = _supabase.auth.currentSession?.accessToken.trim() ?? '';

    if (accessToken.isEmpty) {
      throw StateError('student_session_missing');
    }

    final client = HttpClient();

    try {
      final request = await client
          .deleteUrl(Uri.parse(_studentCertificatesEndpoint))
          .timeout(const Duration(seconds: 15));

      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({'certificateId': certificateId}));

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'A rota de certificados retornou HTTP ${response.statusCode}: '
          '${responseBody.trim()}',
          uri: Uri.parse(_studentCertificatesEndpoint),
        );
      }

      final decoded = jsonDecode(responseBody);

      if (decoded is! Map || decoded['ok'] != true) {
        throw const FormatException('Resposta de exclusão inválida.');
      }
    } on TimeoutException {
      throw StateError('certificates_delete_timeout');
    } on SocketException {
      throw StateError('certificates_network_error');
    } on FormatException {
      throw StateError('certificates_invalid_response');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<_StudentCertificate>> _resolveMissingContentTitles(
    List<_StudentCertificate> certificates,
  ) async {
    final courseIds = certificates
        .where(
          (certificate) =>
              certificate.courseId != null && certificate.courseTitle.isEmpty,
        )
        .map((certificate) => certificate.courseId!)
        .toSet()
        .toList(growable: false);

    final trailIds = certificates
        .where(
          (certificate) =>
              certificate.trailId != null && certificate.courseTitle.isEmpty,
        )
        .map((certificate) => certificate.trailId!)
        .toSet()
        .toList(growable: false);

    final titlesByCourseId = <String, String>{};
    final titlesByTrailId = <String, String>{};

    if (courseIds.isNotEmpty) {
      try {
        final dynamic response = await _supabase
            .from('courses')
            .select('id,title')
            .inFilter('id', courseIds);

        for (final row in _rows(response)) {
          final id = _text(row['id']);
          final title = _text(row['title']);

          if (id != null && title != null) {
            titlesByCourseId[id] = title;
          }
        }
      } catch (_) {
        // O certificado continua legível mesmo quando a política de leitura
        // dos cursos não estiver disponível para este aluno.
      }
    }

    if (trailIds.isNotEmpty) {
      try {
        final dynamic response = await _supabase
            .from('course_categories')
            .select('id,title')
            .inFilter('id', trailIds);

        for (final row in _rows(response)) {
          final id = _text(row['id']);
          final title = _text(row['title']);

          if (id != null && title != null) {
            titlesByTrailId[id] = title;
          }
        }
      } catch (_) {
        // Mantém o fallback visual do certificado quando a trilha não puder
        // ser consultada pela política atual.
      }
    }

    return certificates
        .map((certificate) {
          if (certificate.courseTitle.isNotEmpty) return certificate;

          final resolvedTitle =
              (certificate.courseId == null
                  ? null
                  : titlesByCourseId[certificate.courseId!]) ??
              (certificate.trailId == null
                  ? null
                  : titlesByTrailId[certificate.trailId!]);

          return certificate.copyWith(courseTitle: resolvedTitle ?? 'Formação');
        })
        .toList(growable: false);
  }

  _StudentCertificate? _mapCertificate(
    Map<String, dynamic> row,
    String sourceTable,
  ) {
    final id = _text(row['id']);
    if (id == null) return null;

    final certificatePath = _text(row['certificate_path']);

    return _StudentCertificate(
      id: id,
      sourceTable: sourceTable,
      courseId: _text(row['course_id']),
      trailId: _text(row['trail_id']),
      studentName: _text(row['student_name']) ?? '',
      courseTitle: _text(row['course_title']) ?? '',
      periodStart: _parseDate(row['period_start']),
      completedAt: _parseDate(row['completed_at']),
      workloadHours: _asDouble(row['workload_hours']),
      scorePercent: _asDouble(row['score_percent']),
      certificateUrl: _resolveCertificateUrl(
        directUrl: _text(row['certificate_url']),
        certificatePath: certificatePath,
      ),
      issuedAt:
          _parseDate(row['created_at']) ??
          _parseDate(row['completed_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<void> _copyCertificateLink(_StudentCertificate certificate) async {
    final url = certificate.certificateUrl;

    if (url == null || url.isEmpty) {
      _showMessage('O arquivo deste certificado ainda não está disponível.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));

    if (!mounted) return;

    _showMessage('Link do certificado copiado.');
  }

  Future<void> _downloadCertificate(_StudentCertificate certificate) async {
    final url = certificate.certificateUrl;

    if (url == null || url.isEmpty) {
      _showMessage('O arquivo deste certificado ainda não está disponível.');
      return;
    }

    final accessToken = _supabase.auth.currentSession?.accessToken.trim() ?? '';

    if (accessToken.isEmpty) {
      _showMessage('Entre novamente para baixar o certificado.');
      return;
    }

    if (mounted) {
      setState(() => _downloadingCertificateId = certificate.id);
    }

    final client = HttpClient();
    File? temporaryFile;

    try {
      final downloadUri = Uri.parse(url);
      final request = await client
          .getUrl(downloadUri)
          .timeout(const Duration(seconds: 15));

      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, '*/*');

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'O certificado retornou HTTP ${response.statusCode}.',
          uri: downloadUri,
        );
      }

      final output = BytesBuilder(copy: false);

      await for (final chunk in response) {
        output.add(chunk);
      }

      final bytes = output.takeBytes();

      if (bytes.length < 16) {
        throw const FormatException(
          'Arquivo de certificado vazio ou inválido.',
        );
      }

      final responseMimeType =
          response.headers.contentType?.mimeType.toLowerCase() ?? '';
      final extension = _certificateExtension(
        bytes: bytes,
        mimeType: responseMimeType,
        sourceUri: downloadUri,
      );
      final mimeType = _certificateMimeTypeForExtension(extension);

      if (!_isValidCertificatePayload(bytes, responseMimeType, extension)) {
        throw const FormatException(
          'O servidor não retornou um certificado válido.',
        );
      }

      final fileName = _certificateFileName(certificate, extension);
      final temporaryDirectory = await getTemporaryDirectory();
      temporaryFile = File('${temporaryDirectory.path}/$fileName');

      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }

      await temporaryFile.writeAsBytes(bytes, flush: true);

      final stagedLength = await temporaryFile.length();

      if (stagedLength != bytes.length || stagedLength < 16) {
        throw const FileSystemException(
          'Não foi possível preparar o certificado para salvamento.',
        );
      }

      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: temporaryFile.path,
          mimeTypesFilter: [mimeType],
        ),
      );

      if (savedPath == null || savedPath.trim().isEmpty) {
        _showMessage('Salvamento cancelado.');
        return;
      }

      _showMessage('Certificado salvo. Verifique a pasta escolhida.');
    } on TimeoutException {
      _showMessage('O download demorou mais que o esperado. Tente novamente.');
    } on SocketException {
      _showMessage('Não foi possível baixar o certificado agora.');
    } on FileSystemException {
      _showMessage('Não foi possível preparar o certificado para salvamento.');
    } on FormatException {
      _showMessage('O certificado retornado está inválido. Tente novamente.');
    } catch (_) {
      _showMessage('Não foi possível salvar o certificado no dispositivo.');
    } finally {
      client.close(force: true);

      if (temporaryFile != null) {
        try {
          if (await temporaryFile.exists()) {
            await temporaryFile.delete();
          }
        } catch (_) {
          // O arquivo temporário não interfere no certificado já salvo.
        }
      }

      if (mounted) {
        setState(() => _downloadingCertificateId = null);
      }
    }
  }

  bool _isValidCertificatePayload(
    Uint8List bytes,
    String mimeType,
    String extension,
  ) {
    final normalizedMimeType = mimeType.toLowerCase();

    if (normalizedMimeType.contains('application/json') ||
        normalizedMimeType.contains('text/html')) {
      return false;
    }

    return _certificateExtensionFromPayload(bytes) == extension;
  }

  String _certificateExtension({
    required Uint8List bytes,
    required String? mimeType,
    required Uri sourceUri,
  }) {
    // A assinatura dos bytes é a fonte de verdade. Alguns links privados do
    // Supabase não carregam extensão na URL e podem responder como
    // application/octet-stream, o que antes fazia uma imagem PNG ser salva
    // com o sufixo .pdf no iPhone.
    final payloadExtension = _certificateExtensionFromPayload(bytes);
    if (payloadExtension != null) {
      return payloadExtension;
    }

    switch (mimeType?.toLowerCase()) {
      case 'application/pdf':
        return 'pdf';
      case 'image/png':
        return 'png';
      case 'image/jpeg':
        return 'jpg';
      case 'image/svg+xml':
        return 'svg';
      case 'image/webp':
        return 'webp';
    }

    final path = sourceUri.path;
    final lastSlash = path.lastIndexOf('/');
    final fileName = lastSlash == -1 ? path : path.substring(lastSlash + 1);
    final lastDot = fileName.lastIndexOf('.');

    if (lastDot != -1 && lastDot < fileName.length - 1) {
      final extension = fileName.substring(lastDot + 1).toLowerCase();

      if (_isSupportedCertificateExtension(extension)) {
        return extension == 'jpeg' ? 'jpg' : extension;
      }
    }

    // Não presumimos PDF quando o tipo real não pôde ser identificado.
    // Isso evita salvar uma imagem como .pdf e abrir no aplicativo errado.
    throw const FormatException('Formato de certificado não reconhecido.');
  }

  String? _certificateExtensionFromPayload(Uint8List bytes) {
    if (_hasBytes(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2D])) {
      return 'pdf';
    }

    if (_hasBytes(bytes, const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return 'png';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }

    final previewLength = bytes.length < 1024 ? bytes.length : 1024;
    final preview = utf8
        .decode(bytes.sublist(0, previewLength), allowMalformed: true)
        .trimLeft()
        .toLowerCase();

    if (preview.startsWith('<svg') ||
        preview.startsWith('<?xml') && preview.contains('<svg')) {
      return 'svg';
    }

    return null;
  }

  bool _hasBytes(Uint8List bytes, List<int> expected) {
    if (bytes.length < expected.length) {
      return false;
    }

    for (var index = 0; index < expected.length; index++) {
      if (bytes[index] != expected[index]) {
        return false;
      }
    }

    return true;
  }

  bool _isSupportedCertificateExtension(String extension) {
    return const {
      'pdf',
      'png',
      'jpg',
      'jpeg',
      'svg',
      'webp',
    }.contains(extension);
  }

  String _certificateMimeTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'svg':
        return 'image/svg+xml';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  String _certificateFileName(
    _StudentCertificate certificate,
    String extension,
  ) {
    final normalizedTitle = certificate.title
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();

    final normalizedId = certificate.id
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();

    final safeTitle = normalizedTitle.isEmpty ? 'certificado' : normalizedTitle;
    final safeId = normalizedId.isEmpty ? 'emitido' : normalizedId;

    return 'certificado-$safeTitle-$safeId.$extension';
  }

  Future<void> _confirmDeleteCertificate(
    _StudentCertificate certificate,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text(
            'Excluir certificado?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'O certificado de ${certificate.title} deixará de aparecer na sua área.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
              child: const Text(
                'Excluir',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Entre novamente para continuar.');
      return;
    }

    setState(() => _deletingCertificateId = certificate.id);

    try {
      await _deleteCertificateFromWebsite(certificate.id);

      if (!mounted) return;

      setState(() {
        _certificates = _certificates
            .where(
              (item) =>
                  item.id != certificate.id ||
                  item.sourceTable != certificate.sourceTable,
            )
            .toList(growable: false);
      });

      _showMessage('Certificado excluído da sua área.');
    } catch (_) {
      _showMessage('Não foi possível excluir este certificado agora.');
    } finally {
      if (mounted) {
        setState(() => _deletingCertificateId = null);
      }
    }
  }

  void _closePage() {
    Navigator.of(context).maybePop();
  }

  void _showMessage(String message) {
    if (!mounted) return;

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
      backgroundColor: _myCertificatesBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadCertificates,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
            SliverToBoxAdapter(child: _buildHeader()),
            if (_viewState == _CertificatesViewState.loading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_viewState == _CertificatesViewState.error)
              SliverToBoxAdapter(child: _buildErrorState())
            else ...[
              SliverToBoxAdapter(child: _buildMetrics()),
              SliverToBoxAdapter(child: _buildListHeader()),
              SliverToBoxAdapter(child: _buildCertificatesContent()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
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
                  'CERTIFICADOS',
                  style: TextStyle(
                    color: UnlColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.1,
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Meus certificados',
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
                  'Acompanhe suas formações concluídas e os certificados emitidos.',
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

  Widget _buildMetrics() {
    final availableFiles = _certificates
        .where((certificate) => certificate.certificateUrl != null)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _CertificateMetric(
                  icon: Icons.workspace_premium_outlined,
                  value: '${_certificates.length}',
                  label: 'emitidos',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _CertificateMetric(
                  icon: Icons.file_download_outlined,
                  value: '$availableFiles',
                  label: 'com arquivo',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _CertificateMetric(
                  icon: Icons.verified_outlined,
                  value: '${_certificates.length}',
                  label: 'aprovados',
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Divider(height: 1, color: Colors.white10),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HISTÓRICO',
                  style: TextStyle(
                    color: UnlColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.75,
                  ),
                ),
                SizedBox(height: 9),
                Text(
                  'Certificados disponíveis',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.55,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _loadCertificates,
            style: TextButton.styleFrom(
              foregroundColor: UnlColors.gold,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'Atualizar',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificatesContent() {
    if (_certificates.isEmpty) {
      return _buildEmptyState();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: [
          for (var index = 0; index < _certificates.length; index++) ...[
            _CertificateRow(
              certificate: _certificates[index],
              isDeleting: _deletingCertificateId == _certificates[index].id,
              isDownloading:
                  _downloadingCertificateId == _certificates[index].id,
              onCopyLink: () => _copyCertificateLink(_certificates[index]),
              onDownload: () => _downloadCertificate(_certificates[index]),
              onDelete: () => _confirmDeleteCertificate(_certificates[index]),
            ),
            if (index < _certificates.length - 1)
              const Divider(height: 34, color: Colors.white10),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 74, 28, 36),
      child: Column(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: UnlColors.gold,
            size: 50,
          ),
          const SizedBox(height: 20),
          const Text(
            'Nenhum certificado liberado ainda',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Continue avançando nos cursos. Depois da aprovação na avaliação final, o certificado emitido aparecerá aqui.',
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
            onPressed: _loadCertificates,
            style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Atualizar certificados',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 112),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: UnlColors.gold,
            strokeWidth: 2.2,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 54, 20, 0),
      child: Column(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: UnlColors.gold,
            size: 42,
          ),
          const SizedBox(height: 18),
          const Text(
            'Não foi possível carregar seus certificados',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _loadError ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _loadCertificates,
            style: OutlinedButton.styleFrom(
              foregroundColor: UnlColors.gold,
              side: const BorderSide(color: Color(0x44DBC094)),
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

  String? _resolveCertificateUrl({
    required String? directUrl,
    required String? certificatePath,
  }) {
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;
    if (certificatePath == null || certificatePath.isEmpty) return null;

    if (certificatePath.startsWith('https://') ||
        certificatePath.startsWith('http://')) {
      return certificatePath;
    }

    var normalized = certificatePath.replaceFirst(RegExp(r'^/+'), '');
    if (normalized.startsWith('certificates/')) {
      normalized = normalized.replaceFirst('certificates/', '');
    }

    if (normalized.isEmpty) return null;

    return _supabase.storage.from('certificates').getPublicUrl(normalized);
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

  DateTime? _parseDate(dynamic value) {
    final text = _text(value);
    if (text == null) return null;

    return DateTime.tryParse(text)?.toLocal();
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '');
  }
}

class _StudentCertificate {
  const _StudentCertificate({
    required this.id,
    required this.sourceTable,
    required this.courseId,
    required this.trailId,
    required this.studentName,
    required this.courseTitle,
    required this.periodStart,
    required this.completedAt,
    required this.workloadHours,
    required this.scorePercent,
    required this.certificateUrl,
    required this.issuedAt,
  });

  final String id;
  final String sourceTable;
  final String? courseId;
  final String? trailId;
  final String studentName;
  final String courseTitle;
  final DateTime? periodStart;
  final DateTime? completedAt;
  final double? workloadHours;
  final double? scorePercent;
  final String? certificateUrl;
  final DateTime issuedAt;

  String get title => courseTitle.isEmpty ? 'Formação concluída' : courseTitle;

  _StudentCertificate copyWith({String? courseTitle}) {
    return _StudentCertificate(
      id: id,
      sourceTable: sourceTable,
      courseId: courseId,
      trailId: trailId,
      studentName: studentName,
      courseTitle: courseTitle ?? this.courseTitle,
      periodStart: periodStart,
      completedAt: completedAt,
      workloadHours: workloadHours,
      scorePercent: scorePercent,
      certificateUrl: certificateUrl,
      issuedAt: issuedAt,
    );
  }
}

class _CertificateMetric extends StatelessWidget {
  const _CertificateMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: UnlColors.gold, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.50),
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CertificateRow extends StatelessWidget {
  const _CertificateRow({
    required this.certificate,
    required this.isDeleting,
    required this.isDownloading,
    required this.onCopyLink,
    required this.onDownload,
    required this.onDelete,
  });

  final _StudentCertificate certificate;
  final bool isDeleting;
  final bool isDownloading;
  final VoidCallback onCopyLink;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hasFile = certificate.certificateUrl != null;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: UnlColors.gold,
        collapsedIconColor: Colors.white54,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          certificate.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            height: 1.12,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.45,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CertificateBadge(
                icon: Icons.verified_outlined,
                label: 'Emitido',
                gold: true,
              ),
              _CertificateBadge(
                icon: Icons.workspace_premium_outlined,
                label: _formatScore(certificate.scorePercent),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  certificate.studentName.isEmpty
                      ? 'Certificado emitido para você.'
                      : 'Certificado emitido para ${certificate.studentName}.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.54),
                    fontSize: 13,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 22,
                  runSpacing: 12,
                  children: [
                    _CertificateDetail(
                      label: 'Início',
                      value: _formatDate(certificate.periodStart),
                    ),
                    _CertificateDetail(
                      label: 'Conclusão',
                      value: _formatDate(certificate.completedAt),
                    ),
                    _CertificateDetail(
                      label: 'Carga horária',
                      value: _formatWorkload(certificate.workloadHours),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (hasFile)
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      TextButton.icon(
                        onPressed: onCopyLink,
                        style: TextButton.styleFrom(
                          foregroundColor: UnlColors.gold,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text(
                          'Copiar link',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: isDownloading ? null : onDownload,
                        style: TextButton.styleFrom(
                          foregroundColor: UnlColors.gold,
                          disabledForegroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        icon: isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: UnlColors.gold,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          isDownloading ? 'Baixando...' : 'Baixar',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: isDeleting ? null : onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade200,
                          disabledForegroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        icon: isDeleting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                        label: const Text(
                          'Excluir',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Certificado emitido. O arquivo será disponibilizado em breve.',
                    style: TextStyle(
                      color: UnlColors.gold.withOpacity(0.88),
                      fontSize: 12.5,
                      height: 1.4,
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

  static String _formatDate(DateTime? value) {
    if (value == null) return 'Não informado';

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  static String _formatWorkload(double? value) {
    if (value == null) return 'Não informada';

    if (value == value.roundToDouble()) {
      return '${value.toInt()}h';
    }

    return '${value.toStringAsFixed(1).replaceAll('.', ',')}h';
  }

  static String _formatScore(double? value) {
    if (value == null) return 'Aprovado';

    if (value == value.roundToDouble()) {
      return '${value.toInt()}%';
    }

    return '${value.toStringAsFixed(1).replaceAll('.', ',')}%';
  }
}

class _CertificateBadge extends StatelessWidget {
  const _CertificateBadge({
    required this.icon,
    required this.label,
    this.gold = false,
  });

  final IconData icon;
  final String label;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final color = gold ? UnlColors.gold : Colors.white.withOpacity(0.60);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: gold
            ? UnlColors.gold.withOpacity(0.10)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: gold
              ? UnlColors.gold.withOpacity(0.22)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateDetail extends StatelessWidget {
  const _CertificateDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white.withOpacity(0.82),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
