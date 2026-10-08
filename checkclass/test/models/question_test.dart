import 'package:checkclass/models/question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Status wird aus Firestore gelesen', () {
    for (final status in QuestionStatus.values) {
      final q = Question.fromMap('q1', {'text': 'Frage', 'status': status.value});
      expect(q.status, status);
    }
  });

  test('nur "open" bedeutet: Abstimmung läuft', () {
    expect(Question.fromMap('q', {'text': 'x', 'status': 'open'}).isOpen, isTrue);
    expect(Question.fromMap('q', {'text': 'x', 'status': 'prepared'}).isOpen, isFalse);
    expect(Question.fromMap('q', {'text': 'x', 'status': 'closed'}).isOpen, isFalse);
  });

  test('fehlender oder unbekannter Status gilt sicherheitshalber als beendet', () {
    expect(Question.fromMap('q', {'text': 'x'}).status, QuestionStatus.closed);
    expect(Question.fromMap('q', {'text': 'x', 'status': '???'}).status, QuestionStatus.closed);
  });
}
