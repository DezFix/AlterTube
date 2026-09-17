import 'package:flutter/material.dart';
import '../../features/player/player_screen.dart';

// Единый переход в плеер: мягкий fade + лёгкий scale, без перегиба.
Future<T?> pushPlayer<T>(
  BuildContext context, {
  required String videoUrl,
  required String title,
  bool replace = false,
}) {
  final route = PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) =>
        PlayerScreen(videoUrl: videoUrl, title: title),
    transitionsBuilder: (_, anim, __, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
  return replace
      ? Navigator.pushReplacement(context, route)
      : Navigator.push(context, route);
}
