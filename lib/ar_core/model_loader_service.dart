import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_source.dart';

/// Результат попытки загрузки модели.
sealed class ModelLoadResult {}

class ModelLoadSuccess extends ModelLoadResult {
  final ModelSource source;
  ModelLoadSuccess(this.source);
}

class ModelLoadFailure extends ModelLoadResult {
  final String message;
  ModelLoadFailure(this.message);
}

class ModelLoadCancelled extends ModelLoadResult {}

/// Сервис загрузки 3D моделей.
/// Отвечает только за получение файла/URL и преобразование в [ModelSource].
/// Не содержит UI-логики.
class ModelLoaderService {
  /// Открывает системный файловый пикер и возвращает выбранную модель.
  /// Автоматически копирует файл в кеш приложения для стабильного доступа.
  Future<ModelLoadResult> pickFromStorage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ModelSource.supportedExtensions,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return ModelLoadCancelled();
    }

    final file = result.files.first;
    if (file.path == null) {
      return ModelLoadFailure('Не удалось получить путь к файлу.');
    }

    final extension = p.extension(file.name).replaceFirst('.', '');
    final format = ModelSource.formatFromExtension(extension);

    if (format == null) {
      return ModelLoadFailure(
        'Формат .$extension не поддерживается.\n'
        'Поддерживаются: ${ModelSource.supportedExtensions.join(', ')}.',
      );
    }

    final cachedPath = await _copyToAppCache(file.path!, file.name);

    return ModelLoadSuccess(
      ModelSource(
        path: cachedPath,
        sourceType: ModelSourceType.localFile,
        format: format,
        displayName: file.name,
      ),
    );
  }

  /// Валидирует URL и создаёт [ModelSource] без скачивания.
  /// ARCore сам загрузит модель по URL во время AR-сессии.
  ModelLoadResult createFromUrl(String rawUrl) {
    final url = rawUrl.trim();

    if (url.isEmpty) {
      return ModelLoadFailure('Введите URL.');
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.scheme.startsWith('http'))) {
      return ModelLoadFailure('Некорректный URL. Должен начинаться с http:// или https://.');
    }

    final extension = p.extension(uri.path).replaceFirst('.', '').toLowerCase();
    final format = ModelSource.formatFromExtension(extension);

    if (format == null) {
      return ModelLoadFailure(
        'URL не ведёт к поддерживаемому формату.\n'
        'Ожидается один из: ${ModelSource.supportedExtensions.join(', ')}.',
      );
    }

    final displayName = p.basename(uri.path).isNotEmpty
        ? p.basename(uri.path)
        : uri.host;

    return ModelLoadSuccess(
      ModelSource(
        path: url,
        sourceType: ModelSourceType.remoteUrl,
        format: format,
        displayName: displayName,
      ),
    );
  }

  /// Копирует файл в приватный кеш-каталог приложения.
  /// Это гарантирует доступ ARCore к файлу без лишних разрешений.
  Future<String> _copyToAppCache(String sourcePath, String fileName) async {
    final cacheDir = await getTemporaryDirectory();
    final modelsDir = Directory(p.join(cacheDir.path, 'ar_models'));

    if (!modelsDir.existsSync()) {
      await modelsDir.create(recursive: true);
    }

    // Уникальное имя, чтобы не перетирать разные модели с одинаковым именем.
    final uniqueName =
        '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final targetPath = p.join(modelsDir.path, uniqueName);

    await File(sourcePath).copy(targetPath);
    return targetPath;
  }
}