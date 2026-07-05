// VERSÃO: v31
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/unl_colors.dart';
import '../widgets/student_app_shell.dart';

const Color _assessmentBackground = Color(0xFF050609);

class StudentAssessmentScreen extends StatefulWidget {
  const StudentAssessmentScreen({super.key, required this.assessmentId});

  final String assessmentId;

  @override
  State<StudentAssessmentScreen> createState() =>
      _StudentAssessmentScreenState();
}

class _StudentAssessmentScreenState extends State<StudentAssessmentScreen> {
  final ScrollController _scrollController = ScrollController();

  _StudentAssessment? _assessment;
  List<_StudentAssessmentQuestion> _questions = const [];
  List<_StudentAssessmentOption> _options = const [];
  List<_StudentAssessmentAttempt> _attempts = const [];
  Map<String, _StudentAssessmentAnswer> _answers = const {};

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _feedback;
  _StudentAssessmentResult? _result;
  int _currentQuestionIndex = 0;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadAssessment();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAssessment() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _feedback = null;
        _result = null;
        _currentQuestionIndex = 0;
        _answers = const {};
      });
    }

    try {
      final dynamic assessmentResponse = await _supabase
          .from('assessments')
          .select(
            'id,title,description,instructions,scope_type,course_id,trail_id,'
            'lesson_id,trail_evaluation_mode,access_condition,'
            'min_correct_percentage,certificate_required,attempts_allowed,'
            'time_limit_minutes,question_order,status,is_active',
          )
          .eq('id', widget.assessmentId)
          .eq('status', 'published')
          .eq('is_active', true)
          .maybeSingle();

      if (assessmentResponse is! Map) {
        throw StateError('assessment_not_found');
      }

      final assessment = _StudentAssessment.fromRow(
        Map<String, dynamic>.from(assessmentResponse),
      );

      final dynamic questionsResponse = await _supabase
          .from('assessment_questions')
          .select(
            'id,assessment_id,question_type,prompt,help_text,points,required,'
            'sort_order',
          )
          .eq('assessment_id', assessment.id)
          .order('sort_order', ascending: true);

      var questions = _rows(
        questionsResponse,
      ).map(_StudentAssessmentQuestion.fromRow).toList(growable: false);

      if (assessment.questionOrder == 'random' && questions.length > 1) {
        questions = List<_StudentAssessmentQuestion>.from(questions)
          ..shuffle(math.Random());
      }

      final questionIds = questions
          .map((item) => item.id)
          .toList(growable: false);
      final options = await _loadOptions(questionIds);
      final attempts = await _loadAttempts(assessment.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _assessment = assessment;
        _questions = List<_StudentAssessmentQuestion>.unmodifiable(questions);
        _options = List<_StudentAssessmentOption>.unmodifiable(options);
        _attempts = List<_StudentAssessmentAttempt>.unmodifiable(attempts);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _assessment = null;
        _questions = const [];
        _options = const [];
        _attempts = const [];
        _isLoading = false;
        _loadError = 'Não foi possível carregar esta avaliação agora.';
      });
    }
  }

  Future<List<_StudentAssessmentOption>> _loadOptions(
    List<String> questionIds,
  ) async {
    if (questionIds.isEmpty) {
      return const [];
    }

    try {
      final dynamic publicOptionsResponse = await _supabase
          .from('assessment_question_options_public')
          .select('id,question_id,label,sort_order')
          .inFilter('question_id', questionIds)
          .order('sort_order', ascending: true);

      return _rows(
        publicOptionsResponse,
      ).map(_StudentAssessmentOption.fromRow).toList(growable: false);
    } catch (_) {
      final dynamic fallbackOptionsResponse = await _supabase
          .from('assessment_question_options')
          .select('id,question_id,label,sort_order')
          .inFilter('question_id', questionIds)
          .order('sort_order', ascending: true);

      return _rows(
        fallbackOptionsResponse,
      ).map(_StudentAssessmentOption.fromRow).toList(growable: false);
    }
  }

  Future<List<_StudentAssessmentAttempt>> _loadAttempts(
    String assessmentId,
  ) async {
    final userId = _supabase.auth.currentUser?.id;

    if (userId == null) {
      return const [];
    }

    try {
      final dynamic attemptsResponse = await _supabase
          .from('assessment_attempts')
          .select(
            'id,assessment_id,user_id,status,correct_percentage,created_at',
          )
          .eq('assessment_id', assessmentId)
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return _rows(
        attemptsResponse,
      ).map(_StudentAssessmentAttempt.fromRow).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeDestination: StudentAppDestination.courses,
      scrollController: _scrollController,
      backgroundColor: _assessmentBackground,
      body: RefreshIndicator(
        color: UnlColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _loadAssessment,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 104)),
            if (_isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (_loadError != null)
              SliverToBoxAdapter(child: _buildErrorState())
            else if (_result != null)
              SliverToBoxAdapter(child: _buildResultState(_result!))
            else if (_assessment == null || _questions.isEmpty)
              SliverToBoxAdapter(child: _buildUnavailableState())
            else
              SliverToBoxAdapter(child: _buildAssessmentContent()),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentContent() {
    final assessment = _assessment!;
    final question = _questions[_currentQuestionIndex];
    final progress = _questions.isEmpty
        ? 0.0
        : _completedRequiredCount / _questions.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _returnToCourse,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withOpacity(0.72),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text(
              'Voltar ao curso',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'AVALIAÇÃO FINAL',
            style: TextStyle(
              color: UnlColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            assessment.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.55,
            ),
          ),
          if (_descriptionFor(assessment).isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              _descriptionFor(assessment),
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 14,
                height: 1.48,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 22),
          _buildAssessmentInfo(assessment),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(UnlColors.gold),
            ),
          ),
          const SizedBox(height: 14),
          _buildQuestionStepper(),
          if (_feedback != null) ...[
            const SizedBox(height: 22),
            _buildFeedback(_feedback!),
          ],
          const SizedBox(height: 30),
          Text(
            question.prompt,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          if (question.helpText != null && question.helpText!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              question.helpText!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.47),
                fontSize: 13,
                height: 1.48,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildAnswerField(question),
          const SizedBox(height: 30),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 18),
          _buildQuestionActions(),
        ],
      ),
    );
  }

  Widget _buildAssessmentInfo(_StudentAssessment assessment) {
    final details = <String>[
      '${_formatPercent(assessment.minCorrectPercentage)}% mínimo para aprovação',
      if (assessment.timeLimitMinutes != null)
        '${assessment.timeLimitMinutes} min para responder',
      if (assessment.attemptsAllowed > 0)
        '${_attempts.length} de ${assessment.attemptsAllowed} tentativa(s) usada(s)',
    ];

    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final detail in details)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.10)),
              borderRadius: BorderRadius.circular(99),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Text(
              detail,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuestionStepper() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var index = 0; index < _questions.length; index++)
          _buildQuestionStep(index),
      ],
    );
  }

  Widget _buildQuestionStep(int index) {
    final question = _questions[index];
    final isCurrent = index == _currentQuestionIndex;
    final isAnswered = _isAnswerComplete(question, _answers[question.id]);

    return Semantics(
      label: 'Ir para questão ${index + 1}',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: () => setState(() => _currentQuestionIndex = index),
          borderRadius: BorderRadius.circular(99),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? UnlColors.gold
                  : isAnswered
                  ? UnlColors.gold.withOpacity(0.16)
                  : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: isCurrent
                    ? UnlColors.gold
                    : isAnswered
                    ? UnlColors.gold.withOpacity(0.58)
                    : Colors.white.withOpacity(0.10),
              ),
            ),
            child: isAnswered && !isCurrent
                ? const Icon(
                    Icons.check_rounded,
                    color: UnlColors.gold,
                    size: 17,
                  )
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isCurrent ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerField(_StudentAssessmentQuestion question) {
    final answer = _answers[question.id] ?? _StudentAssessmentAnswer.empty();
    final options = _optionsFor(question.id);

    if (_isChoiceQuestion(question.questionType)) {
      if (options.isEmpty) {
        return Text(
          'Esta questão ainda não possui alternativas cadastradas no ADM.',
          style: TextStyle(
            color: UnlColors.gold.withOpacity(0.90),
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        );
      }

      return Column(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            _buildChoiceOption(question, options[index], answer),
            if (index < options.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }

    if (question.questionType == 'scale') {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var value = 1; value <= 5; value++)
            _buildScaleOption(question, value, answer),
        ],
      );
    }

    return TextFormField(
      key: ValueKey<String>('answer-${question.id}'),
      initialValue: answer.textAnswer,
      onChanged: (value) => _updateAnswer(question.id, textAnswer: value),
      minLines: question.questionType == 'short_text' ? 3 : 7,
      maxLines: question.questionType == 'short_text' ? 4 : 10,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Digite sua resposta...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.32)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.025),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: UnlColors.gold),
        ),
      ),
    );
  }

  Widget _buildChoiceOption(
    _StudentAssessmentQuestion question,
    _StudentAssessmentOption option,
    _StudentAssessmentAnswer answer,
  ) {
    final isSelected = answer.selectedOptionIds.contains(option.id);
    final allowsMany = question.questionType == 'multiple_choice';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _toggleOption(question, option.id),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? UnlColors.gold.withOpacity(0.11)
                : Colors.white.withOpacity(0.025),
            border: Border.all(
              color: isSelected
                  ? UnlColors.gold
                  : Colors.white.withOpacity(0.10),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: allowsMany ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: allowsMany ? BorderRadius.circular(6) : null,
                  color: isSelected ? UnlColors.gold : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? UnlColors.gold
                        : Colors.white.withOpacity(0.28),
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.black,
                        size: 16,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.68),
                    fontSize: 14,
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScaleOption(
    _StudentAssessmentQuestion question,
    int value,
    _StudentAssessmentAnswer answer,
  ) {
    final isSelected = answer.numericAnswer == '$value';

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => _updateAnswer(question.id, numericAnswer: '$value'),
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? UnlColors.gold
                : Colors.white.withOpacity(0.025),
            border: Border.all(
              color: isSelected
                  ? UnlColors.gold
                  : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white.withOpacity(0.72),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionActions() {
    final isFirst = _currentQuestionIndex == 0;
    final isLast = _currentQuestionIndex == _questions.length - 1;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isFirst
                ? null
                : () => setState(() => _currentQuestionIndex -= 1),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: Colors.white.withOpacity(0.78),
              disabledForegroundColor: Colors.white.withOpacity(0.25),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 19),
            label: const Text(
              'Anterior',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isSubmitting
                ? null
                : isLast
                ? _submitAssessment
                : () => setState(() => _currentQuestionIndex += 1),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: UnlColors.gold,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withOpacity(0.12),
              disabledForegroundColor: Colors.white.withOpacity(0.32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.black,
                    ),
                  )
                : Icon(
                    isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    size: 20,
                  ),
            label: Text(
              _isSubmitting
                  ? 'Finalizando...'
                  : isLast
                  ? 'Finalizar'
                  : 'Próxima',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedback(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: UnlColors.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UnlColors.gold.withOpacity(0.22)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.white.withOpacity(0.78),
          fontSize: 13,
          height: 1.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 150),
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
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
      child: Column(
        children: [
          const Icon(Icons.quiz_outlined, color: UnlColors.gold, size: 45),
          const SizedBox(height: 18),
          const Text(
            'Não foi possível abrir a avaliação',
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
              color: Colors.white54,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _loadAssessment,
            style: OutlinedButton.styleFrom(
              foregroundColor: UnlColors.gold,
              side: BorderSide(color: UnlColors.gold.withOpacity(0.35)),
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

  Widget _buildUnavailableState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
      child: Column(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: UnlColors.gold,
            size: 44,
          ),
          const SizedBox(height: 18),
          const Text(
            'Avaliação indisponível',
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
            'Ela pode estar bloqueada, pausada ou ainda não possuir questões cadastradas no ADM.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _returnToCourse,
            style: TextButton.styleFrom(foregroundColor: UnlColors.gold),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text(
              'Voltar ao curso',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultState(_StudentAssessmentResult result) {
    final assessment = _assessment;
    final isPassed = result.status.toLowerCase() == 'passed';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 108, 20, 0),
      child: Column(
        children: [
          Icon(
            isPassed
                ? Icons.check_circle_rounded
                : Icons.replay_circle_filled_rounded,
            color: isPassed ? UnlColors.gold : Colors.white,
            size: 64,
          ),
          const SizedBox(height: 24),
          Text(
            isPassed ? 'Aprovado' : 'Tente novamente',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.08,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.65,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            assessment == null
                ? 'Resultado da sua avaliação registrado.'
                : 'Você alcançou ${_formatPercent(result.correctPercentage)}%. O mínimo desta avaliação é ${_formatPercent(assessment.minCorrectPercentage)}%.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 14,
              height: 1.48,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (result.correctPercentage / 100)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(
                isPassed ? UnlColors.gold : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 34),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(isPassed),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: UnlColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text(
                'Voltar ao curso',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAssessment() async {
    if (_isSubmitting || _assessment == null || _questions.isEmpty) {
      return;
    }

    final firstMissingIndex = _firstRequiredQuestionWithoutAnswer;

    if (firstMissingIndex != null) {
      setState(() {
        _currentQuestionIndex = firstMissingIndex;
        _feedback =
            'Responda todas as questões obrigatórias antes de finalizar.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _feedback = null;
    });

    try {
      final payload = _questions
          .map((question) {
            final answer =
                _answers[question.id] ?? _StudentAssessmentAnswer.empty();

            return <String, dynamic>{
              'question_id': question.id,
              'selected_option_ids': answer.selectedOptionIds,
              'text_answer': answer.textAnswer,
              'numeric_answer': answer.numericAnswer,
            };
          })
          .toList(growable: false);

      final dynamic response = await _supabase.rpc(
        'assessment_submit_attempt',
        params: <String, dynamic>{
          'p_assessment_id': _assessment!.id,
          'p_answers': payload,
        },
      );

      final row = _firstRow(response);

      if (row == null) {
        throw StateError('assessment_submit_empty_response');
      }

      final result = _StudentAssessmentResult.fromRow(row);
      final attempts = await _loadAttempts(_assessment!.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
        _attempts = List<_StudentAssessmentAttempt>.unmodifiable(attempts);
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _feedback = _errorMessage(error);
      });
    }
  }

  void _updateAnswer(
    String questionId, {
    List<String>? selectedOptionIds,
    String? textAnswer,
    String? numericAnswer,
  }) {
    final current = _answers[questionId] ?? _StudentAssessmentAnswer.empty();

    setState(() {
      _answers = <String, _StudentAssessmentAnswer>{
        ..._answers,
        questionId: _StudentAssessmentAnswer(
          selectedOptionIds: selectedOptionIds ?? current.selectedOptionIds,
          textAnswer: textAnswer ?? current.textAnswer,
          numericAnswer: numericAnswer ?? current.numericAnswer,
        ),
      };
    });
  }

  void _toggleOption(_StudentAssessmentQuestion question, String optionId) {
    final current = _answers[question.id] ?? _StudentAssessmentAnswer.empty();
    final selected = current.selectedOptionIds;

    if (question.questionType == 'multiple_choice') {
      _updateAnswer(
        question.id,
        selectedOptionIds: selected.contains(optionId)
            ? selected.where((id) => id != optionId).toList(growable: false)
            : <String>[...selected, optionId],
      );
      return;
    }

    _updateAnswer(question.id, selectedOptionIds: <String>[optionId]);
  }

  void _returnToCourse() {
    Navigator.of(context).maybePop(_result?.status.toLowerCase() == 'passed');
  }

  List<_StudentAssessmentOption> _optionsFor(String questionId) {
    return _options
        .where((option) => option.questionId == questionId)
        .toList(growable: false);
  }

  int get _completedRequiredCount {
    return _questions
        .where(
          (question) =>
              !question.required ||
              _isAnswerComplete(question, _answers[question.id]),
        )
        .length;
  }

  int? get _firstRequiredQuestionWithoutAnswer {
    for (var index = 0; index < _questions.length; index++) {
      final question = _questions[index];

      if (question.required &&
          !_isAnswerComplete(question, _answers[question.id])) {
        return index;
      }
    }

    return null;
  }

  bool _isAnswerComplete(
    _StudentAssessmentQuestion question,
    _StudentAssessmentAnswer? answer,
  ) {
    if (answer == null) {
      return false;
    }

    if (_isChoiceQuestion(question.questionType)) {
      return answer.selectedOptionIds.isNotEmpty;
    }

    if (question.questionType == 'scale') {
      return answer.numericAnswer.trim().isNotEmpty;
    }

    return answer.textAnswer.trim().isNotEmpty;
  }

  bool _isChoiceQuestion(String value) {
    return value == 'single_choice' ||
        value == 'multiple_choice' ||
        value == 'true_false';
  }

  String _descriptionFor(_StudentAssessment assessment) {
    final instructions = assessment.instructions?.trim() ?? '';

    if (instructions.isNotEmpty) {
      return instructions;
    }

    return assessment.description?.trim() ?? '';
  }

  String _formatPercent(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _errorMessage(Object error) {
    final message = error.toString().trim();

    if (message.contains('assessment_submit_empty_response')) {
      return 'Não foi possível registrar o resultado desta avaliação.';
    }

    if (message.contains('assessment_not_found')) {
      return 'Esta avaliação não está disponível no momento.';
    }

    return 'Não foi possível finalizar a avaliação. Tente novamente.';
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

  Map<String, dynamic>? _firstRow(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }

    return null;
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return fallback;
    }

    return text;
  }

  String? _nullableText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  int _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }
}

class _StudentAssessment {
  const _StudentAssessment({
    required this.id,
    required this.title,
    required this.description,
    required this.instructions,
    required this.scopeType,
    required this.courseId,
    required this.trailId,
    required this.lessonId,
    required this.accessCondition,
    required this.minCorrectPercentage,
    required this.certificateRequired,
    required this.attemptsAllowed,
    required this.timeLimitMinutes,
    required this.questionOrder,
  });

  final String id;
  final String title;
  final String? description;
  final String? instructions;
  final String scopeType;
  final String? courseId;
  final String? trailId;
  final String? lessonId;
  final String accessCondition;
  final double minCorrectPercentage;
  final bool certificateRequired;
  final int attemptsAllowed;
  final int? timeLimitMinutes;
  final String questionOrder;

  factory _StudentAssessment.fromRow(Map<String, dynamic> row) {
    String text(dynamic value, {String fallback = ''}) {
      final result = value?.toString().trim();
      return result == null || result.isEmpty || result == 'null'
          ? fallback
          : result;
    }

    String? nullableText(dynamic value) {
      final result = text(value);
      return result.isEmpty ? null : result;
    }

    int asInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _StudentAssessment(
      id: text(row['id']),
      title: text(row['title'], fallback: 'Avaliação final'),
      description: nullableText(row['description']),
      instructions: nullableText(row['instructions']),
      scopeType: text(row['scope_type']),
      courseId: nullableText(row['course_id']),
      trailId: nullableText(row['trail_id']),
      lessonId: nullableText(row['lesson_id']),
      accessCondition: text(row['access_condition']),
      minCorrectPercentage: asDouble(row['min_correct_percentage']),
      certificateRequired:
          row['certificate_required'] == true ||
          row['certificate_required']?.toString().toLowerCase() == 'true',
      attemptsAllowed: asInt(row['attempts_allowed']),
      timeLimitMinutes: row['time_limit_minutes'] == null
          ? null
          : asInt(row['time_limit_minutes']),
      questionOrder: text(row['question_order'], fallback: 'fixed'),
    );
  }
}

class _StudentAssessmentQuestion {
  const _StudentAssessmentQuestion({
    required this.id,
    required this.questionType,
    required this.prompt,
    required this.helpText,
    required this.points,
    required this.required,
    required this.sortOrder,
  });

  final String id;
  final String questionType;
  final String prompt;
  final String? helpText;
  final double points;
  final bool required;
  final int sortOrder;

  factory _StudentAssessmentQuestion.fromRow(Map<String, dynamic> row) {
    String text(dynamic value, {String fallback = ''}) {
      final result = value?.toString().trim();
      return result == null || result.isEmpty || result == 'null'
          ? fallback
          : result;
    }

    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int asInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _StudentAssessmentQuestion(
      id: text(row['id']),
      questionType: text(row['question_type'], fallback: 'single_choice'),
      prompt: text(row['prompt'], fallback: 'Questão sem enunciado.'),
      helpText: text(row['help_text']).isEmpty ? null : text(row['help_text']),
      points: asDouble(row['points']),
      required:
          row['required'] == true ||
          row['required']?.toString().toLowerCase() == 'true',
      sortOrder: asInt(row['sort_order']),
    );
  }
}

class _StudentAssessmentOption {
  const _StudentAssessmentOption({
    required this.id,
    required this.questionId,
    required this.label,
    required this.sortOrder,
  });

  final String id;
  final String questionId;
  final String label;
  final int sortOrder;

  factory _StudentAssessmentOption.fromRow(Map<String, dynamic> row) {
    String text(dynamic value, {String fallback = ''}) {
      final result = value?.toString().trim();
      return result == null || result.isEmpty || result == 'null'
          ? fallback
          : result;
    }

    int asInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _StudentAssessmentOption(
      id: text(row['id']),
      questionId: text(row['question_id']),
      label: text(row['label']),
      sortOrder: asInt(row['sort_order']),
    );
  }
}

class _StudentAssessmentAttempt {
  const _StudentAssessmentAttempt({
    required this.id,
    required this.status,
    required this.correctPercentage,
  });

  final String id;
  final String status;
  final double correctPercentage;

  factory _StudentAssessmentAttempt.fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString().trim() ?? '';
    final status = row['status']?.toString().trim() ?? '';
    final value = row['correct_percentage'];

    return _StudentAssessmentAttempt(
      id: id,
      status: status,
      correctPercentage: value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0,
    );
  }
}

class _StudentAssessmentAnswer {
  const _StudentAssessmentAnswer({
    required this.selectedOptionIds,
    required this.textAnswer,
    required this.numericAnswer,
  });

  final List<String> selectedOptionIds;
  final String textAnswer;
  final String numericAnswer;

  factory _StudentAssessmentAnswer.empty() {
    return const _StudentAssessmentAnswer(
      selectedOptionIds: <String>[],
      textAnswer: '',
      numericAnswer: '',
    );
  }
}

class _StudentAssessmentResult {
  const _StudentAssessmentResult({
    required this.attemptId,
    required this.status,
    required this.scorePoints,
    required this.maxPoints,
    required this.correctPercentage,
  });

  final String attemptId;
  final String status;
  final double scorePoints;
  final double maxPoints;
  final double correctPercentage;

  factory _StudentAssessmentResult.fromRow(Map<String, dynamic> row) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _StudentAssessmentResult(
      attemptId: row['attempt_id']?.toString().trim() ?? '',
      status: row['status']?.toString().trim() ?? '',
      scorePoints: asDouble(row['score_points']),
      maxPoints: asDouble(row['max_points']),
      correctPercentage: asDouble(row['correct_percentage']),
    );
  }
}
