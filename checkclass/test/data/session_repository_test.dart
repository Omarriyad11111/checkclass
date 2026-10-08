import 'package:checkclass/data/session_repository.dart';
import 'package:checkclass/models/question.dart';
import 'package:checkclass/models/vote_answer.dart';
import 'package:checkclass/models/vote_tally.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const code = 'ABC234';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeFirebaseFirestore db;
  late SessionRepository repo;

  Future<QuestionStatus?> statusOf(String id) async =>
      (await repo.fetchQuestion(code, id))?.status;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = SessionRepository(db);
    await repo.createSession(code: code, teacherId: 'teacher');
  });

  group('Frage-Lebenszyklus', () {
    test('vorbereitete Frage ist sichtbar, aber noch nicht aktiv', () async {
      final qid = await repo.prepareQuestion(code: code, text: 'Alles verstanden?');
      expect(await statusOf(qid), QuestionStatus.prepared);

      final session = await repo.fetchSession(code);
      expect(session!.currentQuestionId, qid);
      expect(session.question, 'Alles verstanden?');
      expect(session.active, isTrue);
    });

    test('Start: prepared → open, Ende: open → closed', () async {
      final qid = await repo.prepareQuestion(code: code, text: 'Frage');
      await repo.openQuestion(code, qid);
      expect(await statusOf(qid), QuestionStatus.open);
      await repo.closeQuestion(code, qid);
      expect(await statusOf(qid), QuestionStatus.closed);
    });

    test('Ende lässt abgegebene Stimmen und Ergebnis bestehen', () async {
      final qid = await repo.prepareQuestion(code: code, text: 'Frage');
      await repo.openQuestion(code, qid);
      await repo.castVote(code: code, questionId: qid, uid: 's1', answer: VoteAnswer.yes);
      await repo.castVote(code: code, questionId: qid, uid: 's2', answer: VoteAnswer.no);
      await repo.closeQuestion(code, qid);

      final tally = await repo.watchTally(code, qid).first;
      expect((tally.yes, tally.no), (1, 1));
    });

    test('neue Frage ist zunächst nur vorbereitet, die alte wird beendet', () async {
      final q1 = await repo.prepareQuestion(code: code, text: 'Erste');
      await repo.openQuestion(code, q1);
      final q2 = await repo.prepareQuestion(
          code: code, text: 'Zweite', previousQuestionId: q1);

      expect(await statusOf(q1), QuestionStatus.closed);
      expect(await statusOf(q2), QuestionStatus.prepared);

      final session = await repo.fetchSession(code);
      expect(session!.currentQuestionId, q2);
      expect(session.question, 'Zweite');
    });

    test('neue Frage starten: Abstimmung ist wieder möglich', () async {
      final q1 = await repo.prepareQuestion(code: code, text: 'Erste');
      await repo.openQuestion(code, q1);
      await repo.castVote(code: code, questionId: q1, uid: 's1', answer: VoteAnswer.yes);

      final q2 = await repo.prepareQuestion(
          code: code, text: 'Zweite', previousQuestionId: q1);
      await repo.openQuestion(code, q2);
      expect(await statusOf(q2), QuestionStatus.open);

      final ok = await repo.castVote(
          code: code, questionId: q2, uid: 's1', answer: VoteAnswer.no);
      expect(ok, isTrue);
    });

    test('Session beenden schließt Session und aktuelle Frage', () async {
      final qid = await repo.prepareQuestion(code: code, text: 'Frage');
      await repo.openQuestion(code, qid);
      await repo.endSession(code, qid);
      expect((await repo.fetchSession(code))!.active, isFalse);
      expect(await statusOf(qid), QuestionStatus.closed);
    });
  });

  group('Stimmen', () {
    test('Live: Ergebnisse aktualisieren sich bei jeder neuen Stimme', () async {
      final qid = await repo.prepareQuestion(code: code, text: 'Alles verstanden?');
      await repo.openQuestion(code, qid);
      final tallies = <VoteTally>[];
      final sub = repo.watchTally(code, qid).listen(tallies.add);
      await settle();
      expect(tallies.last.total, 0);

      await repo.castVote(code: code, questionId: qid, uid: 's1', answer: VoteAnswer.yes);
      await settle();
      expect((tallies.last.yes, tallies.last.no), (1, 0));

      await repo.castVote(code: code, questionId: qid, uid: 's2', answer: VoteAnswer.no);
      await settle();
      expect((tallies.last.yes, tallies.last.no), (1, 1));
      expect(tallies.last.yesPercent, 50);
      await sub.cancel();
    });

    test('eine Stimme pro Frage: zweite Stimme wird nicht gespeichert', () async {
      final qid = await repo.prepareQuestion(code: code, text: 'Frage');
      await repo.openQuestion(code, qid);
      final first = await repo.castVote(
          code: code, questionId: qid, uid: 's1', answer: VoteAnswer.yes);
      final second = await repo.castVote(
          code: code, questionId: qid, uid: 's1', answer: VoteAnswer.no);
      expect((first, second), (true, false));

      final tally = await repo.watchTally(code, qid).first;
      expect((tally.yes, tally.no), (1, 0));
    });
  });

  test('ein Code kann nur einmal vergeben werden', () async {
    final again = await repo.createSession(code: code, teacherId: 'other');
    expect(again, isFalse);
    expect((await repo.fetchSession(code))!.teacherId, 'teacher');
  });

  test('Teilnehmende werden live gezählt', () async {
    final counts = <int>[];
    final sub = repo.watchParticipantCount(code).listen(counts.add);
    await settle();
    await repo.registerParticipant(code, 's1');
    await repo.registerParticipant(code, 's2');
    await repo.registerParticipant(code, 's2'); // erneuter Beitritt zählt nicht doppelt
    await settle();
    expect(counts.last, 2);
    await sub.cancel();
  });
}
