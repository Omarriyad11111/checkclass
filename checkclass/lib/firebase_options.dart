import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'Firebase ist aktuell nur für Android konfiguriert.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyCxSPQPnEQzxaMb8MLkEMm3kHaIUhdhxJ0",
    appId: "1:869262005442:android:f6bcf0e2623f73b0d4975b",
    messagingSenderId: "869262005442",
    projectId: "checkclass-f0e86",
    storageBucket: "checkclass-f0e86.firebasestorage.app",
  );
}
