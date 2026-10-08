import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    runApp(_StartupErrorApp(message: '$e'));
    return;
  }

  final container = ProviderContainer();
  // Anonym anmelden. Schlägt das offline fehl, wird es bei der ersten
  // Aktion erneut versucht (siehe AuthService.ensureSignedIn).
  unawaited(
    container.read(authServiceProvider).ensureSignedIn().then((_) {}).catchError((_) {}),
  );

  runApp(UncontrolledProviderScope(container: container, child: const CheckClassApp()));
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(message, textAlign: TextAlign.center)),
          ),
        ),
      ),
    );
  }
}
