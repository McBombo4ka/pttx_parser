import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'model_source.dart';

/// Репозиторий привязок AR-моделей к слайдам.
///
/// Данные хранятся в JSON-файле в documents-директории приложения.
/// Имя файла формируется из [presentationKey], что позволяет хранить
/// привязки для нескольких презентаций независимо.
///
/// Один слайд — одна модель (повторная привязка перезаписывает старую).
///
/// Расширяет [ChangeNotifier], поэтому виджеты могут подписаться через
/// Provider или вручную через addListener.
class ArModelRepository extends ChangeNotifier {
  ArModelRepository({required this.presentationKey});

  /// Идентификатор презентации (например, имя файла без расширения).
  final String presentationKey;

  Map<int, ModelSource> _bindings = {};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Загружает привязки с диска. Нужно вызвать один раз при старте.
  Future<void> load() async {
    if (_isLoaded) return;
    _bindings = await _readFromDisk();
    _isLoaded = true;
    notifyListeners();
  }

  /// Привязывает [model] к слайду с индексом [slideIndex].
  /// Если привязка уже была — перезаписывает.
  Future<void> attachModel(int slideIndex, ModelSource model) async {
    _bindings[slideIndex] = model;
    notifyListeners();
    await _writeToDisk();
  }

  /// Удаляет привязку модели со слайда [slideIndex].
  Future<void> detachModel(int slideIndex) async {
    if (!_bindings.containsKey(slideIndex)) return;
    _bindings.remove(slideIndex);
    notifyListeners();
    await _writeToDisk();
  }

  /// Возвращает привязанную модель для [slideIndex], или null.
  ModelSource? getModel(int slideIndex) => _bindings[slideIndex];

  /// Есть ли привязанная модель для [slideIndex].
  bool hasModel(int slideIndex) => _bindings.containsKey(slideIndex);

  // ── Персистентность ────────────────────────────────────────────────────────

  Future<Map<int, ModelSource>> _readFromDisk() async {
    try {
      final file = await _storageFile();
      if (!file.existsSync()) return {};

      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return {};

      return raw.map((key, value) {
        final slideIndex = int.parse(key);
        final model = _modelFromJson(value as Map<String, dynamic>);
        return MapEntry(slideIndex, model);
      });
    } catch (e) {
      debugPrint('[ArModelRepository] load error: $e');
      return {};
    }
  }

  Future<void> _writeToDisk() async {
    try {
      final file = await _storageFile();
      final json = _bindings.map(
        (index, model) => MapEntry(index.toString(), _modelToJson(model)),
      );
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('[ArModelRepository] save error: $e');
    }
  }

  Future<File> _storageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ar_bindings_$presentationKey.json');
  }

  // ── Сериализация ModelSource ───────────────────────────────────────────────

  Map<String, dynamic> _modelToJson(ModelSource model) => {
        'path': model.path,
        'sourceType': model.sourceType.name,
        'format': model.format.name,
        'displayName': model.displayName,
      };

  ModelSource _modelFromJson(Map<String, dynamic> json) => ModelSource(
        path: json['path'] as String,
        sourceType: ModelSourceType.values.byName(json['sourceType'] as String),
        format: ModelFormat.values.byName(json['format'] as String),
        displayName: json['displayName'] as String,
      );
}