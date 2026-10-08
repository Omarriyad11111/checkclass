import 'package:flutter/material.dart';

import '../errors/app_exceptions.dart';

String errorText(Object error) => error is AppException
    ? error.message
    : 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(errorText(error)),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Vollflächige Hinweisansicht (Fehler, Session beendet, ...).
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.onRetry,
    this.onHome,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 24),
          if (onRetry != null)
            FilledButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
          if (onHome != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onHome, child: const Text('Zur Startseite')),
          ],
        ],
      ),
    );
  }
}
