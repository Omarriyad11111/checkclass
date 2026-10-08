import 'package:flutter/widgets.dart';

/// Liefert Duration.zero, wenn das System „Bewegung reduzieren“ meldet
/// (iOS: Bewegung reduzieren, Android: Animationen entfernen).
Duration motionDuration(BuildContext context, Duration normal) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
