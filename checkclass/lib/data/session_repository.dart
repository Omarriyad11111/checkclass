import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/question.dart';
import '../models/session.dart';
import '../models/vote_answer.dart';
import '../models/vote_tally.dart';

/// Einziger Ort mit direktem Firestore-Zugriff.
///
/// sessions/{code}
///   └ questions/{questionId}
///       └ votes/{uid}
class SessionRepository {
  SessionRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _session(String code) =>
      _db.collection('sessions').doc(code);

  DocumentReference<Map<String, dynamic>> _question(String code, String id) =>
      _session(code).collection('questions').doc(id);

  DocumentReference<Map<String, dynamic>> _vote(
          String code, String qid, String uid) =>
      _question(code, qid).collection('votes').doc(uid);

  Map<String, dynamic> _normalized(Map<String, dynamic>? data) {
    final map = {...?data};
    final created = map['createdAt'];
    if (created is Timestamp) map['createdAt'] = created.toDate();
    return map;
  }

  CollectionReference<Map<String, dynamic>> _participants(String code) =>
      _session(code).collection('participants');

  // ---------------------------------------------------------------- Lehrer

  /// Legt die Session nur an, wenn der Code noch nicht existiert.
  /// Gibt `false` zurück, wenn der Code bereits vergeben ist.
  Future<bool> createSession({
    required String code,
    required String teacherId,
  }) {
    return _db.runTransaction<bool>((tx) async {
      final ref = _session(code);
      final snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {
        'teacherId': teacherId,
        'question': '',
        'currentQuestionId': null,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// Bereitet eine neue Frage vor und schließt die vorherige (atomar).
  /// Die neue Frage ist sichtbar, aber noch NICHT abstimmbar (`prepared`).
  Future<String> prepareQuestion({
    required String code,
    required String text,
    String? previousQuestionId,
  }) async {
    final ref = _session(code).collection('questions').doc();
    final batch = _db.batch();
    if (previousQuestionId != null) {
      batch.update(
        _question(code, previousQuestionId),
        {'status': QuestionStatus.closed.value},
      );
    }
    batch.set(ref, {
      'text': text,
      'status': QuestionStatus.prepared.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_session(code), {'question': text, 'currentQuestionId': ref.id});
    await batch.commit();
    return ref.id;
  }

  /// ▶ Abstimmung starten: prepared → open.
  Future<void> openQuestion(String code, String questionId) =>
      _question(code, questionId).update({'status': QuestionStatus.open.value});

  /// ⏹ Abstimmung beenden: → closed. Abgegebene Stimmen bleiben erhalten.
  Future<void> closeQuestion(String code, String questionId) =>
      _question(code, questionId).update({'status': QuestionStatus.closed.value});

  Future<void> endSession(String code, String? currentQuestionId) {
    final batch = _db.batch();
    if (currentQuestionId != null) {
      batch.update(
        _question(code, currentQuestionId),
        {'status': QuestionStatus.closed.value},
      );
    }
    batch.update(_session(code), {'active': false});
    return batch.commit();
  }

  // --------------------------------------------------------------- Schüler

  /// Meldet das Gerät anonym als Teilnehmende:n an (nur uid, keine Daten).
  Future<void> registerParticipant(String code, String uid) =>
      _participants(code).doc(uid).set({'joinedAt': FieldValue.serverTimestamp()});

  /// Einmalige Abfrage direkt vom Server (schlägt offline bewusst fehl).
  Future<Session?> fetchSession(String code) async {
    final snap =
        await _session(code).get(const GetOptions(source: Source.server));
    return snap.exists ? Session.fromMap(code, _normalized(snap.data())) : null;
  }

  Future<Question?> fetchQuestion(String code, String id) async {
    final snap =
        await _question(code, id).get(const GetOptions(source: Source.server));
    return snap.exists ? Question.fromMap(id, _normalized(snap.data())) : null;
  }

  /// Gibt `true` zurück, wenn die Stimme gespeichert wurde, `false`, wenn
  /// bereits eine Stimme existiert. Die Rules verbieten Überschreiben ohnehin.
  Future<bool> castVote({
    required String code,
    required String questionId,
    required String uid,
    required VoteAnswer answer,
  }) {
    final ref = _vote(code, questionId, uid);
    return _db.runTransaction<bool>((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) return false;
      tx.set(ref, {
        'answer': answer.value,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  // ------------------------------------------------------------ Live-Streams

  /// Leere Cache-Snapshots (z. B. kurz nach Verbindungsverlust) werden
  /// ignoriert, damit nie fälschlich „Session nicht gefunden“ erscheint.
  Stream<Session?> watchSession(String code) => _session(code)
      .snapshots()
      .where((s) => s.exists || !s.metadata.isFromCache)
      .map((s) => s.exists ? Session.fromMap(code, _normalized(s.data())) : null);

  /// `true`, solange Daten nur aus dem lokalen Cache kommen (= keine
  /// Serververbindung). Basis für die Verbindungsanzeige.
  Stream<bool> watchFromCache(String code) => _session(code)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.metadata.isFromCache);

  /// Anzahl der beigetretenen Teilnehmenden (nur Lehrkraft darf lesen).
  Stream<int> watchParticipantCount(String code) =>
      _participants(code).snapshots().map((q) => q.size);

  Stream<Question?> watchQuestion(String code, String id) =>
      _question(code, id).snapshots().map(
            (s) => s.exists ? Question.fromMap(id, _normalized(s.data())) : null,
          );

  /// Die eigene Stimme (Schüler dürfen nur diese lesen).
  Stream<VoteAnswer?> watchMyVote(String code, String qid, String uid) =>
      _vote(code, qid, uid)
          .snapshots()
          .map((s) => s.exists ? VoteAnswer.tryParse(s.data()?['answer']) : null);

  /// Alle Stimmen einer Frage, laufend ausgezählt (nur Lehrer erlaubt).
  Stream<VoteTally> watchTally(String code, String qid) =>
      _question(code, qid).collection('votes').snapshots().map(
            (q) => VoteTally.fromAnswers(
              q.docs
                  .map((d) => VoteAnswer.tryParse(d.data()['answer']))
                  .whereType<VoteAnswer>(),
            ),
          );
}
