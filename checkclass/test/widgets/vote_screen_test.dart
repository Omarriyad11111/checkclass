import 'package:checkclass/models/vote_answer.dart';
import 'package:checkclass/models/question.dart';
import 'package:checkclass/models/session.dart';
import 'dart:async';

import 'package:checkclass/data/session_repository.dart';
import 'package:checkclass/features/student/vote_screen.dart';
import 'package:checkclass/providers.dart';
import 'package:checkclass/services/auth_service.dart';
import 'package:checkclass/services/connection_monitor.dart';
import 'package:checkclass/services/session_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const code = 'ABC234';
const waitText = 'Warte auf den Start der Abstimmung …';
const yesLabel = 'JA – verstanden';
const noLabel = 'NEIN – bitte nochmal erklären';

Session session({String? questionId, String question = '', bool active = true}) => Session(
      code: code,
      teacherId: 'teacher',
      question: question,
      currentQuestionId: questionId,
      active: active,
    );

Question question(String id, String text, QuestionStatus status) =>
    Question(id: id, text: text, status: status);

/// Ein Button ist freigeschaltet, wenn sein InkWell einen onTap hat.
bool isEnabled(WidgetTester tester, String label) {
  final inkWell = tester.widget<InkWell>(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
  );
  return inkWell.onTap != null;
}

void main() {
  late StreamController<Session?> sessionStream;
  late Map<String, StreamController<Question?>> questionStreams;

  Future<void> pumpScreen(WidgetTester tester, {VoteAnswer? myVoteQ1}) async {
    sessionStream = StreamController<Session?>.broadcast();
    questionStreams = {
      'q1': StreamController<Question?>.broadcast(),
      'q2': StreamController<Question?>.broadcast(),
    };
    addTearDown(() {
      sessionStream.close();
      for (final c in questionStreams.values) {
        c.close();
      }
    });

    final service = SessionService(
      AuthService(MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 's1'))),
      SessionRepository(FakeFirebaseFirestore()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionServiceProvider.overrideWithValue(service),
          sessionProvider(code).overrideWith((ref) => sessionStream.stream),
          connectionStatusProvider(code)
              .overrideWith((ref) => Stream.value(ConnectionStatus.connected)),
          questionProvider((code: code, id: 'q1'))
              .overrideWith((ref) => questionStreams['q1']!.stream),
          questionProvider((code: code, id: 'q2'))
              .overrideWith((ref) => questionStreams['q2']!.stream),
          myVoteProvider((code: code, id: 'q1')).overrideWith((ref) => Stream.value(myVoteQ1)),
          myVoteProvider((code: code, id: 'q2')).overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: VoteScreen(code: code)),
      ),
    );
    await tester.pump();
  }

  /// Lehrkraft zeigt eine Frage in einem bestimmten Status.
  Future<void> show(
    WidgetTester tester, {
    required String id,
    required String text,
    required QuestionStatus status,
  }) async {
    sessionStream.add(session(questionId: id, question: text));
    await tester.pumpAndSettle();
    questionStreams[id]!.add(question(id, text, status));
    await tester.pumpAndSettle();
  }

  Future<void> setStatus(
    WidgetTester tester, {
    required String id,
    required String text,
    required QuestionStatus status,
  }) async {
    questionStreams[id]!.add(question(id, text, status));
    await tester.pumpAndSettle();
  }

  testWidgets('vor dem Start: Frage sichtbar, Wartehinweis, Buttons gesperrt', (tester) async {
    await pumpScreen(tester);
    await show(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.prepared);

    expect(find.text('Alles verstanden?'), findsOneWidget);
    expect(find.text(waitText), findsOneWidget);
    expect(isEnabled(tester, yesLabel), isFalse);
    expect(isEnabled(tester, noLabel), isFalse);
  });

  testWidgets('nach dem Start werden beide Buttons bei bereits Beigetretenen freigeschaltet',
      (tester) async {
    await pumpScreen(tester);
    await show(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.prepared);
    expect(isEnabled(tester, yesLabel), isFalse);

    await setStatus(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.open);

    expect(find.text(waitText), findsNothing);
    expect(isEnabled(tester, yesLabel), isTrue);
    expect(isEnabled(tester, noLabel), isTrue);
  });

  testWidgets('Spätbeitretende sehen die laufende Frage sofort abstimmbar', (tester) async {
    await pumpScreen(tester);
    await show(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.open);

    expect(find.text(waitText), findsNothing);
    expect(isEnabled(tester, yesLabel), isTrue);
  });

  testWidgets('nach der Abstimmung: Bestätigung, keine zweite Stimme möglich', (tester) async {
    await pumpScreen(tester, myVoteQ1: VoteAnswer.yes);
    await show(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.open);

    expect(find.text('✓ Antwort gespeichert'), findsOneWidget);
    expect(isEnabled(tester, yesLabel), isFalse);
    expect(isEnabled(tester, noLabel), isFalse);
  });

  testWidgets('nach dem Ende: "Abstimmung beendet" und gesperrte Buttons', (tester) async {
    await pumpScreen(tester);
    await show(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.open);
    await setStatus(tester, id: 'q1', text: 'Alles verstanden?', status: QuestionStatus.closed);

    expect(find.text('Abstimmung beendet'), findsOneWidget);
    expect(isEnabled(tester, yesLabel), isFalse);
    expect(isEnabled(tester, noLabel), isFalse);
  });

  testWidgets('neue Frage: zunächst Wartehinweis, nach dem Start wieder abstimmbar',
      (tester) async {
    await pumpScreen(tester, myVoteQ1: VoteAnswer.yes);
    await show(tester, id: 'q1', text: 'Erste Frage', status: QuestionStatus.open);
    expect(find.text('✓ Antwort gespeichert'), findsOneWidget);

    await show(tester, id: 'q2', text: 'Zweite Frage', status: QuestionStatus.prepared);
    expect(find.text('Zweite Frage'), findsOneWidget);
    expect(find.text(waitText), findsOneWidget);
    expect(find.text('✓ Antwort gespeichert'), findsNothing);
    expect(isEnabled(tester, yesLabel), isFalse);

    await setStatus(tester, id: 'q2', text: 'Zweite Frage', status: QuestionStatus.open);
    expect(isEnabled(tester, yesLabel), isTrue);
    expect(isEnabled(tester, noLabel), isTrue);
  });

  testWidgets('noch keine Frage: Wartehinweis', (tester) async {
    await pumpScreen(tester);
    sessionStream.add(session());
    await tester.pumpAndSettle();
    expect(find.text(waitText), findsOneWidget);
  });

  testWidgets('beendete Session: Hinweis', (tester) async {
    await pumpScreen(tester);
    sessionStream.add(session(questionId: 'q1', question: 'Erste Frage', active: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('beendet'), findsOneWidget);
  });
}
