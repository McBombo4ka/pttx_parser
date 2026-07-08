import 'dart:async';

import 'package:arcore_flutter_plus/arcore_flutter_plus.dart';
import 'package:arcore_flutter_plus/arcore_flutter_plus.dart' as arCoreController;
import 'package:vector_math/vector_math_64.dart' as vector;

import 'model_source.dart';

sealed class ArPlacementResult {}

class ArPlacementSuccess extends ArPlacementResult {}

class ArPlacementFailure extends ArPlacementResult {
  final String message;
  ArPlacementFailure(this.message);
}

/// Управляет AR-сессией.
///
/// Ключевые гарантии:
/// - [dispose] идемпотентен и безопасен для повторного вызова.
/// - После [dispose] все методы — no-op.
/// - [onArCoreViewCreated] безопасно вызывать после предыдущего dispose.
class ArSessionController {
  vector.Vector3? cameraPosition;
  vector.Vector4? cameraRotation;
  ArCoreController? _arcoreController;
  bool _modelPlaced = false;
  int _nodeCount = 0;
  bool _disposed = false;
  Timer? _poseTimer;
  bool get isReady => _arcoreController != null && !_disposed;
  bool get isModelPlaced => _modelPlaced;
  
  void Function()? onStateChanged;
  Future<void> updateCameraPose() async {
    arCoreController.onCameraPositionUpdate = (pose) {
   print("Координаты смартфона обновились сами: ${pose['translation']}");
};
    if (_disposed || _arcoreController == null) return;

    final pose = await _arcoreController!.getCameraPose();
    if (pose == null) return;

    final translation = pose['translation'];
    final rotation = pose['rotation'];
    print("Позиция - $translation");
    print("Позиция - $rotation");
    cameraPosition = vector.Vector3(
      translation[0],
      translation[1],
      translation[2],
    );

    cameraRotation = vector.Vector4(
      rotation[0],
      rotation[1],
      rotation[2],
      rotation[3],
    );

    onStateChanged?.call();
  }

  void onArCoreViewCreated(
    ArCoreController controller,
    ModelSource modelSource,
  ) {
    _poseTimer?.cancel();
    _poseTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => updateCameraPose(),
    );
    if (_disposed) return;
    _arcoreController = controller;
    _arcoreController!.onPlaneTap = (hits) =>
        _handlePlaneTap(hits, modelSource);
    onStateChanged?.call();
  }

  Future<ArPlacementResult> _handlePlaneTap(
    List<ArCoreHitTestResult> hits,
    ModelSource modelSource,
  ) async {
    if (_disposed || _arcoreController == null) {
      return ArPlacementFailure('AR контроллер не готов.');
    }
    if (_modelPlaced) return ArPlacementSuccess();
    if (hits.isEmpty) return ArPlacementFailure('Поверхность не обнаружена.');
    return _placeModel(hits.first, modelSource);
  }

  Future<ArPlacementResult> _placeModel(
    ArCoreHitTestResult hit,
    ModelSource modelSource,
  ) async {
    if (_disposed) return ArPlacementFailure('Сессия завершена.');
    try {
      final node = _buildNode(hit.pose.translation, modelSource);
      await _arcoreController!.addArCoreNodeWithAnchor(node);
      _modelPlaced = true;
      onStateChanged?.call();
      return ArPlacementSuccess();
    } catch (e) {
      return ArPlacementFailure('Не удалось разместить модель: $e');
    }
  }

  ArCoreReferenceNode _buildNode(
    vector.Vector3 position,
    ModelSource modelSource,
  ) {
    _nodeCount++;
    return ArCoreReferenceNode(
      name: 'ar_model_$_nodeCount',
      objectUrl: modelSource.arUri,
      position: position,
      scale: vector.Vector3.all(0.2),
    );
  }

  void resetPlacement() {
    if (_disposed || _arcoreController == null) return;
    _arcoreController!.removeNode(nodeName: 'ar_model_$_nodeCount');
    _modelPlaced = false;
    onStateChanged?.call();
  }

  /// Освобождает ресурсы. Безопасно вызывать повторно.
  void dispose() {
    if (_disposed) return;
    _poseTimer?.cancel();
    _disposed = true;
    _arcoreController?.dispose();
    _arcoreController = null;
    onStateChanged = null;
  }
}
