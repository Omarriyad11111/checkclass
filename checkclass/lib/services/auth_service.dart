import 'package:firebase_auth/firebase_auth.dart';

import '../data/firebase_error_mapper.dart';

/// Anonyme Anmeldung: keine E-Mail, kein Passwort, kein Login-Screen.
class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  String? get currentUid => _auth.currentUser?.uid;

  /// Meldet anonym an, falls noch nicht geschehen, und liefert die uid.
  Future<String> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing.uid;
    try {
      final credential = await _auth.signInAnonymously();
      return credential.user!.uid;
    } catch (e) {
      throw mapFirebaseError(e);
    }
  }
}
