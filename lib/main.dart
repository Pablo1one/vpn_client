import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsDesktop) {
    runApp(const App());
    return;
  }

  await windowManager.ensureInitialized();
  await windowManager.setTitle('VPN Client');
  await windowManager.setMinimumSize(const Size(480, 600));
  await windowManager.setPreventClose(true);

  runApp(const App());
}

// ignore: non_constant_identifier_names
bool get kIsDesktop =>
    !const bool.fromEnvironment('dart.library.js_util') &&
    (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
