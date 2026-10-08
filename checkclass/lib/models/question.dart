/// Lebenszyklus einer Frage: vorbereitet → läuft → beendet.
enum QuestionStatus {
  /// Frage ist sichtbar, es darf aber noch NICHT abgestimmt werden.
  prepared,

  /// Abstimmung läuft.
  open,

  /// Abstimmung beendet; Stimmen und Ergebnis bleiben erhalten.
  closed;

  /// Wert, wie er in Firestore gespeichert wird.
  String get value => name;

  /// Unbekannte Werte gelten sicherheitshalber als beendet.
  static QuestionStatus parse(Object? raw) {
    for (final status in values) {
      if (status.name == raw) return status;
    }
    return QuestionStatus.closed;
  }
}

class Question {
  const Question({required this.id, required this.text, required this.status});

  final String id;
  final String text;
  final QuestionStatus status;

  bool get isOpen => status == QuestionStatus.open;

  factory Question.fromMap(String id, Map<String, dynamic> map) => Question(
        id: id,
        text: map['text'] as String? ?? '',
        status: QuestionStatus.parse(map['status']),
      );
}
