import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const AlterTubeApp(),
    ),
  );
}
