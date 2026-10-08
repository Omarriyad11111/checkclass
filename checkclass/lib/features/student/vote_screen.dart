import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/connection_badge.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/motion.dart';
import '../../models/question.dart';
import '../../models/session.dart';
import '../../models/vote_answer.dart';
import '../../providers.dart';

class VoteScreen extends ConsumerStatefulWidget {
  const VoteScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends ConsumerState<VoteScreen> {
  bool _busy = false;

  Future<void> _vote(Session s, VoteAnswer answer) async {
    unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
    setState(() => _busy = true);
    try {
      await ref.read(sessionServiceProvider).submitVote(
            code: widget.code,
            questionId: s.currentQuestionId!,
            answer: answer,
          );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider(widget.code));
    void home() => context.go(Routes.home);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: ConnectionIndicator(code: widget.code),
        leading: IconButton(
          tooltip: 'Verlassen',
          icon: const Icon(Icons.close_rounded),
          onPressed: home,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: sessionAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(
                  message: errorText(e),
                  onRetry: () => ref.invalidate(sessionProvider(widget.code)),
                ),
                data: (s) {
                  if (s == null) {
                    return ErrorView(message: 'Diesen Code gibt es nicht.', onHome: home);
                  }
                  if (!s.active) {
                    return ErrorView(
                      icon: Icons.check_circle_outline_rounded,
                      message: 'Die Session wurde beendet. Danke fürs Mitmachen!',
                      onHome: home,
                    );
                  }
                  if (s.currentQuestionId == null) {
                    return const ErrorView(
                      icon: Icons.hourglass_empty_rounded,
                      message: 'Warte auf den Start der Abstimmung …',
                    );
                  }
                  return _panel(s);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(Session s) {
    final key = (code: widget.code, id: s.currentQuestionId!);
    final question = ref.watch(questionProvider(key)).value;
    final myVote = ref.watch(myVoteProvider(key)).value;

    final status = question?.status;
    final open = status == QuestionStatus.open;
    final voted = myVote != null;
    final canVote = open && !voted && !_busy;

    String? message;
    if (voted) {
      message = '✓ Antwort gespeichert';
    } else if (status == QuestionStatus.prepared) {
      message = 'Warte auf den Start der Abstimmung …';
    } else if (status == QuestionStatus.closed) {
      message = 'Abstimmung beendet';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Neue Frage erscheint automatisch (Session-Stream) mit sanftem Wechsel.
        // Lange Fragen scrollen innerhalb der Karte, statt das Layout zu sprengen.
        Flexible(
          flex: 2,
          child: SingleChildScrollView(
            child: AnimatedSwitcher(
              duration: motionDuration(context, const Duration(milliseconds: 250)),
              child: Card(
                key: ValueKey(key.id),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      question?.text ?? s.question,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: AnimatedSwitcher(
            duration: motionDuration(context, const Duration(milliseconds: 250)),
            child: message == null
                ? const SizedBox.shrink(key: ValueKey('none'))
                : Semantics(
                    key: ValueKey(message),
                    liveRegion: true,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          flex: 3,
          child: _VoteButton(
            emoji: '🟢',
            label: 'JA – verstanden',
            color: AppTheme.understood,
            enabled: canVote,
            selected: myVote == VoteAnswer.yes,
            onPressed: () => _vote(s, VoteAnswer.yes),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          flex: 3,
          child: _VoteButton(
            emoji: '🔴',
            label: 'NEIN – bitte nochmal erklären',
            color: AppTheme.notUnderstood,
            enabled: canVote,
            selected: myVote == VoteAnswer.no,
            onPressed: () => _vote(s, VoteAnswer.no),
          ),
        ),
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.emoji,
    required this.label,
    required this.color,
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final String emoji;
  final String label;
  final Color color;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fade = motionDuration(context, const Duration(milliseconds: 250));
    return AnimatedOpacity(
      duration: fade,
      opacity: enabled || selected ? 1 : 0.35,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            // Inhalt skaliert bei wenig Platz herunter (kleine Phones, Querformat).
            child: LayoutBuilder(
              builder: (context, c) => Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: (c.maxWidth - 32).clamp(0.0, double.infinity),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(emoji, style: const TextStyle(fontSize: 48)),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Kurze Bestätigung: Häkchen „poppt“ auf.
                    AnimatedScale(
                      scale: selected ? 1 : 0,
                      duration: motionDuration(context, const Duration(milliseconds: 220)),
                      curve: Curves.easeOutBack,
                      child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 36),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
