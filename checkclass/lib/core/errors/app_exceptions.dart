/// Verständliche, für Nutzer:innen formulierte Fehler.
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class InvalidCodeException extends AppException {
  const InvalidCodeException()
      : super('Diesen Code gibt es nicht. Bitte prüfe deine Eingabe.');
}

final class SessionEndedException extends AppException {
  const SessionEndedException() : super('Diese Session wurde beendet.');
}

final class QuestionClosedException extends AppException {
  const QuestionClosedException()
      : super('Die Abstimmung ist beendet.');
}

final class VotingNotStartedException extends AppException {
  const VotingNotStartedException()
      : super('Die Abstimmung hat noch nicht begonnen.');
}

final class AlreadyVotedException extends AppException {
  const AlreadyVotedException()
      : super('Du hast bei dieser Frage bereits abgestimmt.');
}

final class NoConnectionException extends AppException {
  const NoConnectionException()
      : super(
          'Keine Internetverbindung. Bitte prüfe WLAN oder mobile Daten '
          'und versuche es erneut.',
        );
}

final class NotAllowedException extends AppException {
  const NotAllowedException() : super('Diese Aktion ist nicht erlaubt.');
}

final class ValidationException extends AppException {
  const ValidationException(super.message);
}

final class ConfigException extends AppException {
  const ConfigException(super.message);
}

final class UnknownAppException extends AppException {
  const UnknownAppException([
    super.message = 'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
  ]);
}
