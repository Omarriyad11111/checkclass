class Session {
  const Session({
    required this.code,
    required this.teacherId,
    required this.question,
    required this.currentQuestionId,
    required this.active,
    this.createdAt,
  });

  final String code;
  final String teacherId;
  final String question;
  final String? currentQuestionId;
  final bool active;
  final DateTime? createdAt;

  bool get hasQuestion => currentQuestionId != null;

  factory Session.fromMap(String code, Map<String, dynamic> map) => Session(
        code: code,
        teacherId: map['teacherId'] as String? ?? '',
        question: map['question'] as String? ?? '',
        currentQuestionId: map['currentQuestionId'] as String?,
        active: map['active'] as bool? ?? false,
        createdAt: map['createdAt'] as DateTime?,
      );
}
