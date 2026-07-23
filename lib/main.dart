import 'package:flutter/material.dart';
import 'package:pptx_parsing/core/storage/store_theme.dart';

import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
    // Чистый await без сторонних библиотек
  final ThemeMode savedTheme = await loadThemeFromJson() ?? ThemeMode.system;
  // Передаем сохраненную тему в notifier
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(savedTheme);
  runApp(MyApp(themeNotifier: themeNotifier));
}