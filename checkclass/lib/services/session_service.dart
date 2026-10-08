import 'dart:math';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/errors/app_exceptions.dart';
import '../data/firebase_error_mapper.dart';
import '../data/session_repository.dart';
import '../models/question.dart';
import '../models/session.dart';
import '../models/vote_answer.dart';
import 'auth_service.dart';

/// Fachlogik: Codes, Validierung, Fehlerübersetzung.
class SessionService {
  SessionService(this._auth, this._repo);

  final AuthService _auth;
  final SessionRepository _repo;

  // Ohne verwechselbare Zeichen (0/O, 1/I).
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;
  static const maxQuestionLength = 200;
  static const defaultQuestion = 'Alles verstanden?';
  static const _timeout = Duration(seconds: 12);
  static final _codePattern = RegExp(r'^[A-Z0-9]{4,6}$');

  final _random = Random.secure();

  String _generateCode() => String.fromCharCodes(
        List.generate(
          codeLength,
          (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
        ),
      );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(_timeout);
    } catch (e) {
      throw mapFirebaseError(e);
    }
  }

  // ---------------------------------------------------------------- Lehrer

  /// Erzeugt einen freien Code. Existiert er schon, wird neu gewürfelt;
  /// die Transaktion verhindert doppelte Codes auch bei Gleichzeitigkeit.
  Future<String> createSession() => _guard(() async {
        final uid = await _auth.ensureSignedIn();
        for (var attempt = 0; attempt < 8; attempt++) {
          final code = _generateCode();
          if (await _repo.createSession(code: code, teacherId: uid)) return code;
        }
        throw const UnknownAppException(
          'Es konnte kein freier Code erzeugt werden. Bitte erneut versuchen.',
        );
      });

  String _cleanQuestion(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Bitte gib eine Frage ein.');
    }
    if (trimmed.length > maxQuestionLength) {
      throw const ValidationException(
        'Die Frage ist zu lang (maximal $maxQuestionLength Zeichen).',
      );
    }
    return trimmed;
  }

  /// Bereitet eine Frage vor: Teilnehmende sehen sie, stimmen aber noch nicht ab
  /// (Status `prepared`).
  Future<String> prepareQuestion({
    required String code,
    required String text,
    String? previousQuestionId,
  }) =>
      _guard(() async {
        final clean = _cleanQuestion(text);
        await _auth.ensureSignedIn();
        return _repo.prepareQuestion(
          code: code,
          text: clean,
          previousQuestionId: previousQuestionId,
        );
      });

  /// Der sichtbare Ein-Tipp-Ablauf der Lehrkraft: Frage bereitstellen UND
  /// sofort die Abstimmung öffnen. Intern bleibt es prepared → open; schlägt
  /// der zweite Schritt fehl, bleibt die Frage `prepared` und die Lehrkraft
  /// kann mit „Abstimmung starten“ erneut öffnen.
  Future<String> startNewVoting({
    required String code,
    required String text,
    String? previousQuestionId,
  }) =>
      _guard(() async {
        final clean = _cleanQuestion(text);
        await _auth.ensureSignedIn();
        final id = await _repo.prepareQuestion(
          code: code,
          text: clean,
          previousQuestionId: previousQuestionId,
        );
        await _repo.openQuestion(code, id);
        return id;
      });

  /// ▶ Abstimmung starten – schaltet 🟢/🔴 für alle frei.
  Future<void> startVoting(String code, String questionId) =>
      _guard(() => _repo.openQuestion(code, questionId));

  /// ⏹ Abstimmung beenden – keine neuen Stimmen, Ergebnis bleibt.
  Future<void> endVoting(String code, String questionId) =>
      _guard(() => _repo.closeQuestion(code, questionId));

  Future<void> endSession(String code, String? currentQuestionId) =>
      _guard(() => _repo.endSession(code, currentQuestionId));

  // --------------------------------------------------------------- Schüler

  Future<Session> joinSession(String rawCode) => _guard(() async {
        final code = rawCode.trim().toUpperCase();
        if (!_codePattern.hasMatch(code)) throw const InvalidCodeException();
        final uid = await _auth.ensureSignedIn();
        final session = await _repo.fetchSession(code);
        if (session == null) throw const InvalidCodeException();
        if (!session.active) throw const SessionEndedException();
        if (session.teacherId == uid) {
          throw const ValidationException('Du leitest diese Session selbst.');
        }
        await _repo.registerParticipant(code, uid);
        return session;
      });

  Future<void> submitVote({
    required String code,
    required String questionId,
    required VoteAnswer answer,
  }) async {
    try {
      final uid = await _auth.ensureSignedIn();
      final written = await _repo
          .castVote(code: code, questionId: questionId, uid: uid, answer: answer)
          .timeout(_timeout);
      if (!written) throw const AlreadyVotedException();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw await explainVoteDenied(code, questionId);
      }
      throw mapFirebaseError(e);
    } catch (e) {
      throw mapFirebaseError(e);
    }
  }

  /// Findet heraus, warum eine Stimme abgelehnt wurde.
  @visibleForTesting
  Future<AppException> explainVoteDenied(String code, String questionId) async {
    try {
      final session = await _repo.fetchSession(code);
      if (session == null || !session.active) return const SessionEndedException();
      final question = await _repo.fetchQuestion(code, questionId);
      return switch (question?.status) {
        QuestionStatus.prepared => const VotingNotStartedException(),
        QuestionStatus.open => const NotAllowedException(),
        QuestionStatus.closed || null => const QuestionClosedException(),
      };
    } catch (_) {
      return const NotAllowedException();
    }
  }
}
