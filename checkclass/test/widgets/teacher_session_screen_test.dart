import 'package:checkclass/data/session_repository.dart';
import 'package:checkclass/features/teacher/teacher_session_screen.dart';
import 'package:checkclass/models/question.dart';
import 'package:checkclass/models/session.dart';
import 'package:checkclass/models/vote_tally.dart';
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
const key = (code: code, id: 'q1');

Session session({String? questionId, bool active = true}) => Session(
      code: code,
      teacherId: 'teacher',
      question: 'Alles verstanden?',
      currentQuestionId: questionId,
      active: active,
    );

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Session session,
    QuestionStatus? status,
    VoteTally tally = const VoteTally(),
  }) async {
    // Hoch genug, damit die ListView alle Elemente aufbaut.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = SessionService(
      AuthService(MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'teacher'))),
      SessionRepository(FakeFirebaseFirestore()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionServiceProvider.overrideWithValue(service),
          sessionProvider(code).overrideWith((ref) => Stream.value(session)),
          connectionStatusProvider(code)
              .overrideWith((ref) => Stream.value(ConnectionStatus.connected)),
          participantCountProvider(code).overrideWith((ref) => Stream.value(8)),
          if (status != null) ...[
            questionProvider(key).overrideWith((ref) =>
                Stream.value(Question(id: 'q1', text: 'Alles verstanden?', status: status))),
            tallyProvider(key).overrideWith((ref) => Stream.value(tally)),
          ],
        ],
        child: const MaterialApp(home: TeacherSessionScreen(code: code)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Start: Frage steht bereit, genau ein Hauptbutton', (tester) async {
    await pumpScreen(tester, session: session());

    expect(find.text('Alles verstanden?'), findsOneWidget); // vorbelegt im Feld
    expect(find.text('Abstimmung starten'), findsOneWidget);
    expect(find.text('Frage bereitstellen'), findsNothing);
    expect(find.text('Abstimmung beenden'), findsNothing);
    expect(find.text('Neue Frage'), findsNothing);
  });

  testWidgets('laufende Abstimmung: Ergebnisse live, nur "Abstimmung beenden"', (tester) async {
    await pumpScreen(
      tester,
      session: session(questionId: 'q1'),
      status: QuestionStatus.open,
      tally: const VoteTally(yes: 24, no: 6),
    );

    expect(find.text('Abstimmung läuft'), findsOneWidget);
    expect(find.text('Abstimmung beenden'), findsOneWidget);
    expect(find.text('Abstimmung starten'), findsNothing);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('Noch offen'), findsOneWidget);
  });

  testWidgets('beendet: Ergebnis bleibt sichtbar, nur "Neue Frage"', (tester) async {
    await pumpScreen(
      tester,
      session: session(questionId: 'q1'),
      status: QuestionStatus.closed,
      tally: const VoteTally(yes: 3, no: 1),
    );

    expect(find.text('Abstimmung beendet'), findsOneWidget);
    expect(find.text('Neue Frage'), findsOneWidget);
    expect(find.text('Abstimmung starten'), findsNothing);
    expect(find.text('Abstimmung beenden'), findsNothing);
    expect(find.text('Verstanden'), findsOneWidget);
  });

  testWidgets('"Neue Frage" öffnet die Eingabe, gestartet wird erst mit "Abstimmung starten"',
      (tester) async {
    await pumpScreen(
      tester,
      session: session(questionId: 'q1'),
      status: QuestionStatus.closed,
    );

    await tester.tap(find.text('Neue Frage'));
    await tester.pumpAndSettle();

    expect(find.text('Abstimmung starten'), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
    expect(find.text('Neue Frage'), findsNothing);
  });

  testWidgets('nur vorbereitete Frage (z. B. nach Fehler): Start ist weiterhin möglich',
      (tester) async {
    await pumpScreen(
      tester,
      session: session(questionId: 'q1'),
      status: QuestionStatus.prepared,
    );

    expect(find.text('Abstimmung starten'), findsOneWidget);
    expect(find.text('Bereit – noch keine Abstimmung'), findsOneWidget);
  });
}
