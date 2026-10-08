import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/session_repository.dart';
import 'models/question.dart';
import 'models/session.dart';
import 'models/vote_answer.dart';
import 'models/vote_tally.dart';
import 'services/auth_service.dart';
import 'services/connection_monitor.dart';
import 'services/session_service.dart';

final authServiceProvider =
    Provider((ref) => AuthService(FirebaseAuth.instance));

final sessionRepositoryProvider =
    Provider((ref) => SessionRepository(FirebaseFirestore.instance));

final sessionServiceProvider = Provider(
  (ref) => SessionService(
    ref.watch(authServiceProvider),
    ref.watch(sessionRepositoryProvider),
  ),
);

/// Schlüssel für Provider, die zu einer Frage gehören.
typedef QuestionKey = ({String code, String id});

final sessionProvider =
    StreamProvider.autoDispose.family<Session?, String>((ref, code) {
  return ref.watch(sessionRepositoryProvider).watchSession(code);
});

final questionProvider =
    StreamProvider.autoDispose.family<Question?, QuestionKey>((ref, key) {
  return ref.watch(sessionRepositoryProvider).watchQuestion(key.code, key.id);
});

final myVoteProvider =
    StreamProvider.autoDispose.family<VoteAnswer?, QuestionKey>((ref, key) {
  final uid = ref.watch(authServiceProvider).currentUid;
  if (uid == null) return Stream.value(null);
  return ref
      .watch(sessionRepositoryProvider)
      .watchMyVote(key.code, key.id, uid);
});

final tallyProvider =
    StreamProvider.autoDispose.family<VoteTally, QuestionKey>((ref, key) {
  return ref.watch(sessionRepositoryProvider).watchTally(key.code, key.id);
});

final participantCountProvider =
    StreamProvider.autoDispose.family<int, String>((ref, code) {
  return ref.watch(sessionRepositoryProvider).watchParticipantCount(code);
});

final connectionStatusProvider =
    StreamProvider.autoDispose.family<ConnectionStatus, String>((ref, code) {
  return monitorConnection(
    ref.watch(sessionRepositoryProvider).watchFromCache(code),
  );
});
