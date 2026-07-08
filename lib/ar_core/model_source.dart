/// Поддерживаемые форматы 3D моделей.
/// ARCore нативно работает с .glb и .sfb.
/// .gltf поддерживается через URL. .obj — экспериментально.
enum ModelFormat { glb, gltf, sfb, obj }

/// Откуда пришла модель.
enum ModelSourceType { localFile, remoteUrl }

/// Неизменяемое описание загруженной пользователем 3D модели.
/// Содержит всё необходимое для отображения в AR и в UI.
class ModelSource {
  final String path; // абсолютный путь к файлу или HTTP(S) URL
  final ModelSourceType sourceType;
  final ModelFormat format;
  final String displayName;

  const ModelSource({
    required this.path,
    required this.sourceType,
    required this.format,
    required this.displayName,
  });

  bool get isRemote => sourceType == ModelSourceType.remoteUrl;
  bool get isLocal => sourceType == ModelSourceType.localFile;

  /// URI, готовый для передачи в [ArCoreReferenceNode.objectUrl].
  /// Для локальных файлов добавляет схему file://.
  String get arUri => isLocal ? 'file://$path' : path;

  static const List<String> supportedExtensions = [
    'glb',
    'gltf',
    'sfb',
    'obj',
  ];

  /// Возвращает [ModelFormat] по расширению файла, или null если не поддерживается.
  static ModelFormat? formatFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'glb':
        return ModelFormat.glb;
      case 'gltf':
        return ModelFormat.gltf;
      case 'sfb':
        return ModelFormat.sfb;
      case 'obj':
        return ModelFormat.obj;
      default:
        return null;
    }
  }

  /// Человекочитаемое название формата.
  String get formatLabel => format.name.toUpperCase();

  @override
  String toString() => 'ModelSource($displayName, $formatLabel, $sourceType)';
}