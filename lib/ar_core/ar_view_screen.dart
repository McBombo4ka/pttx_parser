import 'package:arcore_flutter_plus/arcore_flutter_plus.dart';
import 'package:flutter/material.dart';

import 'ar_session_controller.dart';
import 'model_source.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class ArViewScreen extends StatefulWidget {
  final ModelSource modelSource;
    final void Function(
  vector.Vector3 position,
  vector.Vector4 rotation,
)? onCameraPose;
  const ArViewScreen({super.key, required this.modelSource, this.onCameraPose});

  @override
  State<ArViewScreen> createState() => _ArViewScreenState();
}

class _ArViewScreenState extends State<ArViewScreen>
    with WidgetsBindingObserver {
  ArSessionController? _sessionController;
  bool _arViewActive = true;
  Key _arViewKey = UniqueKey();
  String? _errorMessage;

  /// true только если мы уже ушли в paused и убрали view.
  /// Защищает от лишних пересозданий при inactive (permission dialog,
  /// уведомления и т.д.) — они не должны вызывать dispose/recreate.
  bool _pausedAndDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createSession();
  }

  void _createSession() {
    final ctrl = ArSessionController();
    ctrl.onStateChanged = _refresh;
    ctrl.onCameraPoseChanged = widget.onCameraPose;
    _sessionController = ctrl;
  }

  void _disposeSession() {
    _sessionController?.dispose();
    _sessionController = null;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ── Жизненный цикл ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    switch (state) {
      // ТОЛЬКО paused — именно здесь файловый пикер или свёртывание приложения.
      // inactive НЕ трогаем: оно срабатывает при диалоге камеры, уведомлениях
      // и любом системном overlay — реакция на него давала бесконечный цикл.
      case AppLifecycleState.paused:
        if (!_pausedAndDisposed) {
          _pausedAndDisposed = true;
          _disposeSession();
          setState(() => _arViewActive = false);
        }

      case AppLifecycleState.resumed:
        // Пересоздаём только если мы реально уходили в paused.
        if (_pausedAndDisposed) {
          _pausedAndDisposed = false;
          _createSession();
          setState(() {
            _arViewKey = UniqueKey(); // новый ключ = новый PlatformView
            _arViewActive = true;
          });
        }

      default:
        break;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          if (_arViewActive && _sessionController != null)
            _buildArCoreView()
          else
            _buildSuspendedOverlay(),

          if (_arViewActive &&
              _sessionController != null &&
              !_sessionController!.isModelPlaced)
            _buildScanHint(),

          if (_errorMessage != null) _buildErrorBanner(),

          if (_arViewActive &&
              _sessionController != null &&
              _sessionController!.isModelPlaced)
            _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildArCoreView() {
    final ctrl = _sessionController!;
    return ArCoreView(
      key: _arViewKey,
      onArCoreViewCreated: (arCtrl) =>
          ctrl.onArCoreViewCreated(arCtrl, widget.modelSource),
      enableTapRecognizer: true,
      enablePlaneRenderer: true,
      planeColor: Colors.cyanAccent.withOpacity(0.25),
    );
  }

  Widget _buildSuspendedOverlay() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: Colors.white30),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.modelSource.displayName,
            style: const TextStyle(fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.modelSource.formatLabel,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
      backgroundColor: Colors.black87,
      foregroundColor: Colors.white,
    );
  }

  Widget _buildScanHint() {
    return Positioned(
      top: 20,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
        ),
        // Row убран — он и давал overflow.
        // Иконка + текст в одну строку через RichText/Row c Flexible.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.crop_free, color: Colors.cyanAccent, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Наведите на плоскую поверхность и коснитесь',
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Positioned(
      bottom: 90,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.red.shade800.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _errorMessage = null),
                child:
                    const Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return Positioned(
      bottom: 24,
      right: 16,
      child: FloatingActionButton.extended(
        onPressed: _sessionController?.resetPlacement,
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.refresh),
        label: const Text('Переместить'),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeSession();
    super.dispose();
  }
}