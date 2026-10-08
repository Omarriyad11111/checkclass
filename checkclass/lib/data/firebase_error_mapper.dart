import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../core/errors/app_exceptions.dart';

/// Übersetzt technische Firebase-Fehler in verständliche [AppException]s.
AppException mapFirebaseError(Object error) {
  if (error is AppException) return error;
  if (error is TimeoutException) return const NoConnectionException();

  // FirebaseAuthException erbt von FirebaseException – daher zuerst prüfen.
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
        return const NoConnectionException();
      case 'operation-not-allowed':
      case 'admin-restricted-operation':
        return const ConfigException(
          'Anonyme Anmeldung ist in Firebase noch nicht aktiviert.',
        );
      default:
        return UnknownAppException('Anmeldung fehlgeschlagen (${error.code}).');
    }
  }

  if (error is FirebaseException) {
    switch (error.code) {
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return const NoConnectionException();
      case 'permission-denied':
        return const NotAllowedException();
      default:
        return UnknownAppException('Fehler (${error.code}). Bitte versuche es erneut.');
    }
  }
  return const UnknownAppException();
}
