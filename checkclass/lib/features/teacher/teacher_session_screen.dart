import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animated_count.dart';
import '../../core/widgets/connection_badge.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/motion.dart';
import '../../models/question.dart';
import '../../models/session.dart';
import '../../models/vote_tally.dart';
import '../../providers.dart';
import '../../services/session_service.dart';
import 'widgets/result_bar.dart';

class TeacherSessionScreen extends ConsumerStatefulWidget {
  const TeacherSessionScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<TeacherSessionScreen> createState() => _TeacherSessionScreenState();
}

class _TeacherSessionScreenState extends ConsumerState<TeacherSessionScreen> {
  // Vorbelegt, damit die Abstimmung mit einem Tipp startet.
  final _controller = TextEditingController(text: SessionService.defaultQuestion);
  bool _busy = false;
  bool _composing = false;

  SessionService get _service => ref.read(sessionServiceProvider);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ein Tipp: Frage bereitstellen und sofort die Abstimmung starten.
  Future<void> _startNew(Session s) => _run(() async {
        await _service.startNewVoting(
          code: widget.code,
          text: _controller.text,
          previousQuestionId: s.currentQuestionId,
        );
        if (mounted) setState(() => _composing = false);
      });

  Future<void> _startVoting(Session s) =>
      _run(() => _service.startVoting(widget.code, s.currentQuestionId!));

  Future<void> _endVoting(Session s) =>
      _run(() => _service.endVoting(widget.code, s.currentQuestionId!));

  Future<void> _end(Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session beenden?'),
        content: const Text('Danach kann niemand mehr abstimmen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _service.endSession(widget.code, s.currentQuestionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider(widget.code));
    final session = sessionAsync.value;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: ConnectionIndicator(code: widget.code),
        actions: [
          if (session != null && session.active)
            TextButton(
              onPressed: _busy ? null : () => _end(session),
              child: const Text('Beenden'),
            )
          else
            IconButton(
              tooltip: 'Zur Startseite',
              icon: const Icon(Icons.home_rounded),
              onPressed: () => context.go(Routes.home),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: sessionAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: errorText(e),
                onRetry: () => ref.invalidate(sessionProvider(widget.code)),
              ),
              data: (s) => s == null
                  ? ErrorView(
                      message: 'Session nicht gefunden.',
                      onHome: () => context.go(Routes.home),
                    )
                  : _content(s),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(Session s) {
    final key = s.currentQuestionId == null
        ? null
        : (code: widget.code, id: s.currentQuestionId!);
    final question = key == null ? null : ref.watch(questionProvider(key)).value;
    final status = question?.status;
    final tally = key == null
        ? const VoteTally()
        : ref.watch(tallyProvider(key)).value ?? const VoteTally();
    final participants =
        ref.watch(participantCountProvider(widget.code)).value ?? 0;

    final isPrepared = s.active && status == QuestionStatus.prepared;
    final isOpen = s.active && status == QuestionStatus.open;
    final isClosed = status == QuestionStatus.closed;
    final showResults = status == QuestionStatus.open || isClosed;
    final showComposer = s.active && (key == null || _composing);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        _CodeCard(code: widget.code, participants: participants, compact: key != null),
        const SizedBox(height: 24),
        if (!s.active) ...[
          const _EndedNotice(),
          const SizedBox(height: 16),
        ],
        if (key != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status != null)
                  Text(
                    switch (status) {
                      QuestionStatus.prepared => 'Bereit – noch keine Abstimmung',
                      QuestionStatus.open => 'Abstimmung läuft',
                      QuestionStatus.closed => 'Abstimmung beendet',
                    },
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                const SizedBox(height: 4),
                Text(
                  s.question,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (showResults) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ResultTile(
                    emoji: '🟢',
                    label: 'Verstanden',
                    count: tally.yes,
                    percent: tally.yesPercent,
                    color: AppTheme.understood,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ResultTile(
                    emoji: '🔴',
                    label: 'Nicht verstanden',
                    count: tally.no,
                    percent: tally.noPercent,
                    color: AppTheme.notUnderstood,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProgressCard(answered: tally.total, participants: participants),
          ],
          if (isPrepared && !_composing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Teilnehmende sehen die Frage und warten auf den Start.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          const SizedBox(height: 24),
        ],
        if (isPrepared && !_composing) ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _startVoting(s),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Abstimmung starten'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _composing = true),
            child: const Text('Frage ändern'),
          ),
        ],
        if (isOpen)
          FilledButton.icon(
            onPressed: _busy ? null : () => _endVoting(s),
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Abstimmung beenden'),
          ),
        if (s.active && isClosed && !_composing)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => setState(() => _composing = true),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Neue Frage'),
          ),
        if (showComposer) _composer(s, canCancel: key != null),
      ],
    );
  }

  Widget _composer(Session s, {required bool canCancel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 3,
          maxLength: SessionService.maxQuestionLength,
          textInputAction: TextInputAction.done,
          style: Theme.of(context).textTheme.titleLarge,
          onTap: () {
            // Vorbelegten Text mit einem Tipp ersetzbar machen.
            if (_controller.text == SessionService.defaultQuestion) {
              _controller.selection =
                  TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
            }
          },
          onSubmitted: (_) {
            if (!_busy) _startNew(s);
          },
          decoration: InputDecoration(
            labelText: 'Frage',
            counterText: '',
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _startNew(s),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Abstimmung starten'),
        ),
        if (canCancel)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _composing = false),
            child: const Text('Abbrechen'),
          ),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.participants, required this.compact});

  final String code;
  final int participants;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Session-Code: ${code.split('').join(' ')}. $participants beigetreten.',
      excludeSemantics: true,
      child: Card(
        color: scheme.primaryContainer,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 20 : 32, horizontal: 16),
          child: Column(
            children: [
              FittedBox(
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: compact ? 48 : 72,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_alt_rounded, size: 20, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  AnimatedCount(
                    value: participants,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    ' beigetreten',
                    style: TextStyle(fontSize: 18, color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.answered, required this.participants});

  final int answered;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final waiting = math.max(0, participants - answered);
    final progress =
        participants == 0 ? 0.0 : (answered / participants).clamp(0.0, 1.0);
    final big = text.headlineMedium?.copyWith(fontWeight: FontWeight.w800);

    return Semantics(
      label: '$answered Antworten, $waiting noch offen',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Antworten', style: text.titleMedium),
                        AnimatedCount(value: answered, style: big),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Noch offen', style: text.titleMedium),
                        AnimatedCount(value: waiting, style: big),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: motionDuration(context, const Duration(milliseconds: 450)),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: value, minHeight: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndedNotice extends StatelessWidget {
  const _EndedNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded),
            const SizedBox(width: 12),
            Text('Session beendet', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
