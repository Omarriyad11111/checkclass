import 'package:checkclass/core/errors/app_exceptions.dart';
import 'package:checkclass/data/session_repository.dart';
import 'package:checkclass/models/vote_answer.dart';
import 'package:checkclass/services/auth_service.dart';
import 'package:checkclass/services/session_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

SessionService serviceFor(FakeFirebaseFirestore db, String uid) {
  final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
  return SessionService(AuthService(auth), SessionRepository(db));
}

void main() {
  late FakeFirebaseFirestore db;
  late SessionService teacher;
  late SessionService student;
  late String code;

  Future<String?> statusOf(String questionId) async {
    final doc = await db.doc('sessions/$code/questions/$questionId').get();
    return doc.data()?['status'] as String?;
  }

  Future<int> voteCount(String questionId) async =>
      (await db.collection('sessions/$code/questions/$questionId/votes').get()).size;

  setUp(() async {
    db = FakeFirebaseFirestore();
    teacher = serviceFor(db, 'teacher');
    student = serviceFor(db, 'student1');
    code = await teacher.createSession();
  });

  test('Session-Code hat 6 gültige Zeichen und die Session ist gespeichert', () async {
    expect(code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));
    final doc = await db.collection('sessions').doc(code).get();
    expect(doc.data()!['teacherId'], 'teacher');
    expect(doc.data()!['active'], isTrue);
  });

  test('parallel erzeugte Codes sind eindeutig', () async {
    final codes = await Future.wait(List.generate(25, (_) => teacher.createSession()));
    expect(codes.toSet().length, 25);
  });

  group('Beitritt', () {
    test('ungültiges Format und unbekannter Code', () async {
      await expectLater(student.joinSession('x'), throwsA(isA<InvalidCodeException>()));
      await expectLater(student.joinSession('ZZZZZZ'), throwsA(isA<InvalidCodeException>()));
    });

    test('Eingabe wird normalisiert (Leerzeichen, Kleinschreibung)', () async {
      final session = await student.joinSession(' ${code.toLowerCase()} ');
      expect(session.code, code);
    });

    test('beendete Session: Beitritt nicht möglich', () async {
      await teacher.endSession(code, null);
      await expectLater(student.joinSession(code), throwsA(isA<SessionEndedException>()));
    });

    test('die Lehrkraft kann der eigenen Session nicht beitreten', () async {
      await expectLater(teacher.joinSession(code), throwsA(isA<ValidationException>()));
    });

    test('Beitritt registriert die Teilnehmenden anonym (nur uid)', () async {
      await student.joinSession(code);
      final doc = await db.doc('sessions/$code/participants/student1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!.keys, ['joinedAt']);
    });
  });

  group('Ein-Tipp-Start (▶ Abstimmung starten)', () {
    Future<String> currentQuestionId() async =>
        (await db.collection('sessions').doc(code).get()).data()!['currentQuestionId'] as String;

    test('legt die Frage an und öffnet sie in einem Vorgang', () async {
      final qid = await teacher.startNewVoting(code: code, text: 'Alles verstanden?');

      expect(await currentQuestionId(), qid);
      expect(await statusOf(qid), 'open');
      final session = await db.collection('sessions').doc(code).get();
      expect(session.data()!['question'], 'Alles verstanden?');
    });

    test('Teilnehmende, die schon beigetreten waren, können sofort abstimmen', () async {
      await student.joinSession(code); // vor dem Start beigetreten
      final qid = await teacher.startNewVoting(code: code, text: 'Alles verstanden?');

      await student.submitVote(code: code, questionId: qid, answer: VoteAnswer.yes);
      expect(await voteCount(qid), 1);
    });

    test('Spätbeitretende können ebenfalls abstimmen', () async {
      final qid = await teacher.startNewVoting(code: code, text: 'Alles verstanden?');
      final late = serviceFor(db, 'late-student');
      expect((await late.joinSession(code)).currentQuestionId, qid);
      await late.submitVote(code: code, questionId: qid, answer: VoteAnswer.no);
      expect(await voteCount(qid), 1);
    });

    test('nach dem Beenden: neue Frage startet erst mit eigenem Start', () async {
      final q1 = await teacher.startNewVoting(code: code, text: 'Erste Frage');
      await student.submitVote(code: code, questionId: q1, answer: VoteAnswer.yes);
      await teacher.endVoting(code, q1);
      expect(await statusOf(q1), 'closed');

      // "＋ Neue Frage" + "▶ Abstimmung starten"
      final q2 = await teacher.startNewVoting(
          code: code, text: 'Zweite Frage', previousQuestionId: q1);
      expect(await statusOf(q1), 'closed');
      expect(await statusOf(q2), 'open');
      expect(await voteCount(q1), 1); // alte Stimmen bleiben

      await student.submitVote(code: code, questionId: q2, answer: VoteAnswer.no);
      expect(await voteCount(q2), 1);
    });

    test('Ersetzen einer nur vorbereiteten Frage schließt sie', () async {
      final q1 = await teacher.prepareQuestion(code: code, text: 'Entwurf');
      final q2 = await teacher.startNewVoting(
          code: code, text: 'Besserer Text', previousQuestionId: q1);
      expect(await statusOf(q1), 'closed');
      expect(await statusOf(q2), 'open');
    });

    test('prepared → open bleibt auch einzeln möglich (z. B. erneuter Versuch)', () async {
      final qid = await teacher.prepareQuestion(code: code, text: 'Frage');
      expect(await statusOf(qid), 'prepared');
      await teacher.startVoting(code, qid);
      expect(await statusOf(qid), 'open');
    });

    test('leere Frage startet nichts', () async {
      await expectLater(
        teacher.startNewVoting(code: code, text: '  '),
        throwsA(isA<ValidationException>()),
      );
      final doc = await db.collection('sessions').doc(code).get();
      expect(doc.data()!['currentQuestionId'], isNull);
    });
  });

  group('Abstimmungsablauf', () {
    late String qid;

    setUp(() async {
      qid = await teacher.prepareQuestion(code: code, text: 'Alles verstanden?');
    });

    test('Beitreten VOR dem Start ist möglich und zeigt die vorbereitete Frage', () async {
      final session = await student.joinSession(code);
      expect(session.currentQuestionId, qid);
      expect(session.question, 'Alles verstanden?');
      expect(await statusOf(qid), 'prepared');
    });

    test('Beitreten, bevor überhaupt eine Frage existiert', () async {
      final fresh = await teacher.createSession();
      final session = await serviceFor(db, 'student2').joinSession(fresh);
      expect(session.currentQuestionId, isNull);
    });

    test('vor dem Start wird die Ablehnung korrekt erklärt', () async {
      final error = await student.explainVoteDenied(code, qid);
      expect(error, isA<VotingNotStartedException>());
    });

    test('Start öffnet die Abstimmung, danach kann abgestimmt werden', () async {
      await teacher.startVoting(code, qid);
      expect(await statusOf(qid), 'open');

      await student.submitVote(code: code, questionId: qid, answer: VoteAnswer.yes);
      expect(await voteCount(qid), 1);
    });

    test('Spätbeitretende sehen die laufende Frage und können abstimmen', () async {
      await teacher.startVoting(code, qid);
      final late = serviceFor(db, 'late-student');
      final session = await late.joinSession(code);
      expect(session.currentQuestionId, qid);

      await late.submitVote(code: code, questionId: qid, answer: VoteAnswer.no);
      expect(await voteCount(qid), 1);
    });

    test('pro Frage nur eine Stimme', () async {
      await teacher.startVoting(code, qid);
      await student.submitVote(code: code, questionId: qid, answer: VoteAnswer.yes);
      await expectLater(
        student.submitVote(code: code, questionId: qid, answer: VoteAnswer.no),
        throwsA(isA<AlreadyVotedException>()),
      );
      final votes = await db.collection('sessions/$code/questions/$qid/votes').get();
      expect(votes.size, 1);
      expect(votes.docs.single.data()['answer'], 'yes');
    });

    test('Ende: Stimmen bleiben, Ablehnung wird als "beendet" erklärt', () async {
      await teacher.startVoting(code, qid);
      await student.submitVote(code: code, questionId: qid, answer: VoteAnswer.yes);
      await teacher.endVoting(code, qid);

      expect(await statusOf(qid), 'closed');
      expect(await voteCount(qid), 1);
      final error = await serviceFor(db, 'student2').explainVoteDenied(code, qid);
      expect(error, isA<QuestionClosedException>());
    });

    test('Session beendet: Ablehnung wird als "Session beendet" erklärt', () async {
      await teacher.startVoting(code, qid);
      await teacher.endSession(code, qid);
      final error = await student.explainVoteDenied(code, qid);
      expect(error, isA<SessionEndedException>());
    });

    test('neue Frage ist zunächst nicht aktiv, alte ist beendet', () async {
      await teacher.startVoting(code, qid);
      final q2 = await teacher.prepareQuestion(
        code: code,
        text: 'Wer hat die Berechnung verstanden?',
        previousQuestionId: qid,
      );

      expect(q2, isNot(qid));
      expect(await statusOf(qid), 'closed');
      expect(await statusOf(q2), 'prepared');
      expect(await student.explainVoteDenied(code, q2), isA<VotingNotStartedException>());
    });

    test('neue Frage starten: erneutes Abstimmen ist möglich', () async {
      await teacher.startVoting(code, qid);
      await student.submitVote(code: code, questionId: qid, answer: VoteAnswer.yes);

      final q2 = await teacher.prepareQuestion(
          code: code, text: 'Zweite Frage', previousQuestionId: qid);
      await teacher.startVoting(code, q2);
      await student.submitVote(code: code, questionId: q2, answer: VoteAnswer.no);

      expect(await voteCount(q2), 1);
    });

    test('leere oder zu lange Fragen werden abgelehnt', () async {
      await expectLater(
        teacher.prepareQuestion(code: code, text: '   '),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        teacher.prepareQuestion(code: code, text: 'x' * 201),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
