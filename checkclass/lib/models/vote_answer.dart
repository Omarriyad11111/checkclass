enum VoteAnswer {
  yes,
  no;

  /// Wert, wie er in Firestore gespeichert wird.
  String get value => name;

  static VoteAnswer? tryParse(Object? raw) {
    for (final answer in values) {
      if (answer.name == raw) return answer;
    }
    return null;
  }
}
