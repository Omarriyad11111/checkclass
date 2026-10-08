import 'package:checkclass/models/vote_answer.dart';
import 'package:checkclass/models/vote_tally.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ohne Stimmen: alles 0', () {
    const t = VoteTally();
    expect((t.total, t.yesPercent, t.noPercent), (0, 0, 0));
  });

  test('24 Ja / 6 Nein ergibt 80 % / 20 %', () {
    final answers = [
      ...List.filled(24, VoteAnswer.yes),
      ...List.filled(6, VoteAnswer.no),
    ];
    final t = VoteTally.fromAnswers(answers);
    expect((t.yes, t.no, t.total), (24, 6, 30));
    expect((t.yesPercent, t.noPercent), (80, 20));
  });

  test('Prozentwerte ergeben immer 100', () {
    final t = VoteTally.fromAnswers([VoteAnswer.yes, VoteAnswer.no, VoteAnswer.no]);
    expect(t.yesPercent + t.noPercent, 100);
  });

  test('unbekannte Werte werden nicht als Antwort erkannt', () {
    expect(VoteAnswer.tryParse('maybe'), isNull);
    expect(VoteAnswer.tryParse('yes'), VoteAnswer.yes);
  });
}
