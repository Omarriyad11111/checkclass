import 'vote_answer.dart';

/// Ausgezählte Ergebnisse einer Frage.
class VoteTally {
  const VoteTally({this.yes = 0, this.no = 0});

  factory VoteTally.fromAnswers(Iterable<VoteAnswer> answers) {
    var yes = 0;
    var no = 0;
    for (final a in answers) {
      a == VoteAnswer.yes ? yes++ : no++;
    }
    return VoteTally(yes: yes, no: no);
  }

  final int yes;
  final int no;

  int get total => yes + no;
  int get yesPercent => total == 0 ? 0 : (yes * 100 / total).round();
  int get noPercent => total == 0 ? 0 : 100 - yesPercent;
}
