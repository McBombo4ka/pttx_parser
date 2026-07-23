# pptx-ar-viewer

Мобильное приложение на Flutter для просмотра PPTX-презентаций 
с интеграцией 3D-моделей через ARCore и трансляцией в браузер по Wi-Fi со синхронизацией.

## Возможности
- Трансляция презентации в браузер по локальной сети;
- Просмотр 3D GLB-моделей через ARCore;
- Синхронизация слайдов телефон ↔ браузер в реальном времени.
- Парсинг PPTX на устройстве без сервера;

## Стек
- Flutter 3.41.9 / Dart 3.11.5
- ARCore (arcore_flutter_plus немного изменён внутри для корректной работы)
- archive, equatable, http, xml, path_provider, file_saver, permission_handler, share_plus, Provider, arcore_flutter_plus(modified), file_picker

## Установка
- git clone https://github.com/McBombo4ka/pttx_parser.git
- flutter pub get
- flutter run

## Структура проекта
```text
└── lib/
    ├── app/
    │   └── app.dart
    ├── ar_core/
    │   ├── ar_model_repository.dart
    │   ├── ar_session_controller.dart
    │   ├── ar_view_screen.dart
    │   ├── donload.dart
    │   ├── model_loader_service.dart
    │   ├── model_picker_screen.dart
    │   ├── model_source.dart
    │   ├── pptx_parser.dart
    │   ├── remote_control_page.dart
    │   └── slide_models.dart
    ├── core/
    │   ├── network/
    │   │   ├── api_client.dart
    │   │   └── presentation_web_server.dart
    │   └── storage/
    │       └── store_theme.dart
    ├── editor/
    │   ├── edit_models.dart
    │   ├── edit_screen.dart
    │   ├── shape_edit_screen.dart
    │   └── slide_editor.dart
    ├── exporter/
    │   └── html_exporter.dart
    ├── features/
    │   └── pptx_viewer/
    │       ├── pages/
    │       │   └── pptx_viewer_page.dart
    │       ├── painters/
    │       │   ├── diamond_painter.dart
    │       │   └── triangle_painter.dart
    │       └── widgets/
    │           └── slide_canvas.dart
    ├── main.dart
    └── theme/
        └── theme.dart
```
