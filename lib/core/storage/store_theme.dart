import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pptx_parsing/app/app.dart';

class ThemeModeInheritedWidget extends InheritedWidget {
  final ValueNotifier<ThemeMode> themeNotifier;

  const ThemeModeInheritedWidget({
    super.key,
    required this.themeNotifier, required super.child
  });

  // Метод определяет, нужно ли обновлять дочерние виджеты при изменении данных
  @override
  bool updateShouldNotify(ThemeModeInheritedWidget oldWidget) {
    return themeNotifier != oldWidget.themeNotifier;
  }

  // Статический метод для удобного получения данных из любого места поддерева
  static ThemeModeInheritedWidget of(BuildContext context) {
    final ThemeModeInheritedWidget? result = context.dependOnInheritedWidgetOfExactType<ThemeModeInheritedWidget>();
    assert(result != null, 'No ThemeModeInheritedWidget found in context');
    return result!;
  }
}

/// Сохранение темы в JSON файл.
Future<void> saveThemeToJson(ValueNotifier<ThemeMode> themeNotifier) async {
  final theme = {'theme': themeNotifier.value.toString()};
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/my_theme.json');
  Map<String, String> data = theme;

  String jsonString = jsonEncode(data);

  await file.writeAsString(jsonString);
}

/// Функция чтения JSON файла.
Future<ThemeMode?> loadThemeFromJson() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/my_theme.json');
  
  if (await file.exists()) {
    String jsonString = await file.readAsString();

    Map<String, dynamic> data = jsonDecode(jsonString);
    final String themeString = data['theme'] ?? 'system';
    return themeString.toThemeMode();
  } else {
    debugPrint('Файл еще не создан');
  }
  return null;
}
// доделать обработку null и реализовать сохранение темы в файл и его выгрузку соответственно.