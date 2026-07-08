import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ar_core/model_source.dart';
import '../../editor/edit_models.dart';
import '../../ar_core/slide_models.dart';

/// Локальный LAN-сервер для трансляции презентации.
///
/// Отвечает за:
/// - раздачу HTML-страницы, сгенерированной из [PresentationEditModel];
/// - приём WebSocket-соединений от браузерных клиентов;
/// - синхронизацию навигации (next / prev / goto);
/// - текущий индекс слайда как единственный источник истины.
class PresentationWebServer extends ChangeNotifier {
  PresentationWebServer({
    required PresentationEditModel presentation,
    this.port = 8080,
  }) : _presentation = presentation;

  final int port;

  PresentationEditModel _presentation;
  PresentationEditModel get presentation => _presentation;

  HttpServer? _server;
  final Set<WebSocket> _clients = <WebSocket>{};

  int _currentSlideIndex = 0;
  String? _localIp;

  /// Модель, активная в AR прямо сейчас (null = AR не запущен).
  ModelSource? _arModel;
  bool get isArActive => _arModel != null;

  bool get isRunning => _server != null;
  int get clientCount => _clients.length;
  int get currentSlideIndex => _currentSlideIndex;
  int get totalSlides => _presentation.slides.length;

  Uri? get accessUri {
    final ip = _localIp;
    if (ip == null) return null;
    return Uri.parse('http://$ip:$port');
  }

  // ── Управление сервером ────────────────────────────────────────────────────

  Future<Uri> start() async {
    if (_server != null) {
      return accessUri ?? Uri.parse('http://127.0.0.1:$port');
    }

    _localIp = await _discoverLocalIpv4();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    unawaited(_server!.forEach(_handleRequest));

    notifyListeners();
    return accessUri ?? Uri.parse('http://127.0.0.1:$port');
  }

  Future<void> stop() async {
    for (final client in _clients.toList()) {
      try {
        await client.close(WebSocketStatus.normalClosure, 'Server stopped');
      } catch (_) {}
    }
    _clients.clear();

    await _server?.close(force: true);
    _server = null;
    _localIp = null;
    notifyListeners();
  }

  void updatePresentation(PresentationEditModel presentation) {
    _presentation = presentation;
    if (_currentSlideIndex >= totalSlides) {
      _currentSlideIndex = totalSlides == 0 ? 0 : totalSlides - 1;
    }
    _broadcastState();
    notifyListeners();
  }

  // ── Навигация ──────────────────────────────────────────────────────────────

  void nextSlide() => gotoSlide(_currentSlideIndex + 1);
  void previousSlide() => gotoSlide(_currentSlideIndex - 1);

  void gotoSlide(int index, {String source = 'server'}) {
    if (totalSlides == 0) return;

    final clamped = index.clamp(0, totalSlides - 1).toInt();
    final changed = clamped != _currentSlideIndex;

    _currentSlideIndex = clamped;

    if (changed) {
      _broadcast({
        'type': 'goto',
        'index': _currentSlideIndex,
        'source': source,
      });
    }

    _broadcastState();
    notifyListeners();
  }

  // ── AR-режим ───────────────────────────────────────────────────────────────

  /// Переключает браузер в режим просмотра 3D-модели.
  /// Для локальных файлов — отдаёт через /model; для remote — отправляет URL.
  void startArMode(ModelSource model) {
    _arModel = model;
    final base = accessUri?.origin ?? 'http://127.0.0.1:$port';
    final modelUrl = model.isRemote ? model.path : '$base/model';
    _broadcast({
      'type': 'ar_start',
      'modelUrl': modelUrl,
      'modelName': model.displayName,
    });
    notifyListeners();
  }

  /// Возвращает браузер к презентации.
  void stopArMode() {
    _arModel = null;
    _broadcast({'type': 'ar_stop'});
    notifyListeners();
  }

  // ── HTTP-обработчик ────────────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/' || path == '/index.html') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_buildIndexHtml());
      await request.response.close();
      return;
    }

    if (path == '/model') {
      final model = _arModel;
      if (model == null || model.isRemote) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('No local model active');
        await request.response.close();
        return;
      }
      try {
        final bytes = await File(model.path).readAsBytes();
        request.response.headers.set('Content-Type', 'model/gltf-binary');
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.add(bytes);
        await request.response.close();
      } catch (_) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
      return;
    }

    if (path == '/state') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_statePayload()));
      await request.response.close();
      return;
    }

    if (path == '/ws') {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('WebSocket upgrade required.');
        await request.response.close();
        return;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      _clients.add(socket);
      notifyListeners();

      socket.listen(
        (dynamic data) => _handleSocketMessage(socket, data),
        onDone: () {
          _clients.remove(socket);
          notifyListeners();
        },
        onError: (_) {
          _clients.remove(socket);
          notifyListeners();
        },
        cancelOnError: true,
      );

      _sendState(socket);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not found');
    await request.response.close();
  }

  // ── WebSocket-сообщения ────────────────────────────────────────────────────

  void _handleSocketMessage(WebSocket socket, dynamic data) {
    try {
      final raw = data is String ? data : utf8.decode(data as List<int>);
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type']?.toString();

      switch (type) {
        case 'ready':
        case 'request_state':
          _sendState(socket);
        case 'next':
          nextSlide();
        case 'prev':
          previousSlide();
        case 'goto':
          final index = _extractIndex(msg['index']);
          if (index != null) gotoSlide(index, source: 'browser');
      }
    } catch (_) {
      // Игнорируем некорректные сообщения.
    }
  }

  int? _extractIndex(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  void _broadcastState() => _broadcast(_statePayload());

  Map<String, dynamic> _statePayload() {
    final payload = <String, dynamic>{
      'type': 'state',
      'index': _currentSlideIndex,
      'total': totalSlides,
      'server': {'running': isRunning, 'port': port, 'address': _localIp},
    };
    // Если AR активен — клиент при реконнекте сразу увидит модель.
    if (_arModel != null) {
      payload['arActive'] = true;
      payload['modelUrl'] = _arModel!.isRemote ? _arModel!.path : '/model';
      payload['modelName'] = _arModel!.displayName;
    } else {
      payload['arActive'] = false;
    }
    return payload;
  }

  void _sendState(WebSocket socket) {
    try {
      socket.add(jsonEncode(_statePayload()));
    } catch (_) {}
  }

  void _broadcast(Map<String, dynamic> payload) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(payload);
    for (final socket in _clients.toList()) {
      try {
        socket.add(encoded);
      } catch (_) {
        _clients.remove(socket);
      }
    }
  }

  // ── Обнаружение локального IP ──────────────────────────────────────────────

  Future<String?> _discoverLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      final preferredPrefixes = ['wlan', 'wifi', 'eth', 'en', 'ap'];
      final candidates = <InternetAddress>[];

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          if (addr.isLoopback || addr.isLinkLocal) continue;
          candidates.add(addr);
        }
      }

      if (candidates.isEmpty) return null;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (preferredPrefixes.any(name.contains)) {
          final preferred = iface.addresses.where(
            (a) =>
                a.type == InternetAddressType.IPv4 &&
                !a.isLoopback &&
                !a.isLinkLocal,
          );
          if (preferred.isNotEmpty) return preferred.first.address;
        }
      }

      return candidates.first.address;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HTML ГЕНЕРАЦИЯ
  // ═══════════════════════════════════════════════════════════════════════════

  String _buildIndexHtml() {
    final slides = _presentation.slides.map(_slideToHtml).join('\n');
    final w = _presentation.slideSize.widthPx;
    final h = _presentation.slideSize.heightPx;
    final initialIndex = _currentSlideIndex;

    return '''<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Presentation</title>
<style>
  html, body {
    width: 100%;
    height: 100%;
    margin: 0;
    overflow: hidden;
    background: #111;
    font-family: Arial, sans-serif;
  }

  * { box-sizing: border-box; }

  .deck {
    position: relative;
    width: 100vw;
    height: 100vh;
  }

  /* Слайд — абсолютный блок фиксированного размера, масштабируется через transform */
  .slide {
    display: none;
    position: absolute;
    left: 0;
    top: 0;
    width: ${w}px;
    height: ${h}px;
    transform-origin: top left;
    overflow: hidden;
    background: white;
  }

  .slide.active { display: block; }

  /* Общий контейнер для каждого шейпа */
  .shape {
    position: absolute;
    transform-origin: center center;
    overflow: hidden;
    -webkit-font-smoothing: antialiased;
    text-rendering: geometricPrecision;
  }

  /* Текстовый шейп.
     overflow: visible — намеренно:
       - Браузер рендерит шрифты чуть ШИРЕ, чем PowerPoint (разница метрик).
       - overflow:hidden обрезает символы на пиксель-два справа.
       - Слова больше не ломаются в произвольных местах (word-break:normal),
         поэтому небольшое выхождение текста за шейп не создаёт хаоса.
       - Финальный клип происходит на уровне .slide { overflow:hidden }.
     Вертикальный текст из одного шейпа не попадёт в другой благодаря
     корректному line-height и height каждого шейпа из PPTX. */
  .text-shape {
    overflow: visible;
    display: flex;
    flex-direction: column;
  }

  /* Внутренний блок с паддингами и вертикальным выравниванием */
  .text-box {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: visible;
    /* vertical-align задаётся через inline style: justify-content */
  }

  /* Параграф */
  .paragraph {
    margin: 0;
    padding: 0;
    /* pre-wrap сохраняет намеренные переносы строк из PPTX */
    white-space: pre-wrap;
    /* break-word переносит слово ТОЛЬКО если оно целиком не влезает в строку.
       Именно это предотвращает "Распространенны | е каналы" */
    overflow-wrap: break-word;
    /* normal — никогда не рубит слово в произвольном месте.
       break-word здесь устарело и эквивалентно break-all — удалено. */
    word-break: normal;
    /* line-height задаётся через inline style */
  }

  /* Маркер списка */
  .bullet {
    display: inline-block;
    margin-right: 0.35em;
    vertical-align: baseline;
  }

  /* HUD-бейдж статуса */
  .hud {
    position: fixed;
    left: 16px;
    bottom: 16px;
    z-index: 10;
    padding: 8px 14px;
    border-radius: 999px;
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    font-size: 13px;
    backdrop-filter: blur(8px);
    pointer-events: none;
    transition: opacity .3s;
  }
  /* ── AR-оверлей ─────────────────────────────────────────────────── */
  #ar-overlay {
    display: none;
    position: fixed;
    inset: 0;
    z-index: 100;
    background: #0a0a0f;
    flex-direction: column;
    align-items: center;
    justify-content: center;
  }
  #ar-overlay.active { display: flex; }

  #ar-canvas {
    width: 100vw;
    height: 100vh;
    display: block;
  }

  #ar-label {
    position: fixed;
    top: 20px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(0,0,0,0.6);
    color: #fff;
    padding: 8px 20px;
    border-radius: 999px;
    font-size: 15px;
    backdrop-filter: blur(8px);
    pointer-events: none;
    white-space: nowrap;
    z-index: 101;
  }

</style>
</head>
<body>
<div class="deck" id="deck">
$slides
</div>
<div class="hud" id="hud">Подключение…</div>

<!-- AR-оверлей: Three.js сцена с 3D-моделью -->
<div id="ar-overlay">
  <div id="ar-label">3D Model</div>
  <canvas id="ar-canvas"></canvas>
</div>

<script type="importmap">
{
  "imports": {
    "three": "https://cdn.jsdelivr.net/npm/three@0.165.0/build/three.module.js",
    "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.165.0/examples/jsm/"
  }
}
</script>

<script type="module">
import * as THREE from 'three';
import { GLTFLoader }    from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ── Three.js сцена ───────────────────────────────────────────────────────
const canvas   = document.getElementById('ar-canvas');
const overlay  = document.getElementById('ar-overlay');
const arLabel  = document.getElementById('ar-label');

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.shadowMap.enabled = true;

const scene  = new THREE.Scene();
scene.background = new THREE.Color(0x0a0a0f);

const camera = new THREE.PerspectiveCamera(45, 1, 0.01, 1000);
camera.position.set(0, 1, 3);

// Освещение
scene.add(new THREE.AmbientLight(0xffffff, 1.2));
const dir = new THREE.DirectionalLight(0xffffff, 2);
dir.position.set(5, 8, 5);
dir.castShadow = true;
scene.add(dir);
scene.add(new THREE.HemisphereLight(0x8888ff, 0x442200, 0.6));

// OrbitControls
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping  = true;
controls.dampingFactor  = 0.07;
controls.autoRotate     = true;
controls.autoRotateSpeed = 1.2;
controls.minDistance    = 0.3;
controls.maxDistance    = 20;

let model3d = null;
const loader = new GLTFLoader();

function fitCameraToModel(object) {
  const box    = new THREE.Box3().setFromObject(object);
  const center = box.getCenter(new THREE.Vector3());
  const size   = box.getSize(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z);
  const fov    = camera.fov * (Math.PI / 180);
  let   dist   = Math.abs(maxDim / Math.sin(fov / 2)) * 0.7;
  camera.position.set(center.x, center.y + size.y * 0.2, center.z + dist);
  camera.lookAt(center);
  controls.target.copy(center);
  controls.update();
}

function loadModel(url) {
  // Удаляем предыдущую модель
  if (model3d) { scene.remove(model3d); model3d = null; }
  loader.load(url,
    (gltf) => {
      model3d = gltf.scene;
      scene.add(model3d);
      fitCameraToModel(model3d);
    },
    undefined,
    (err) => console.error('[AR] load error', err)
  );
}

function resizeRenderer() {
  if (!overlay.classList.contains('active')) return;
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

window.addEventListener('resize', resizeRenderer);

let animId = null;
function startLoop() {
  if (animId) return;
  function tick() {
    animId = requestAnimationFrame(tick);
    controls.update();
    renderer.render(scene, camera);
  }
  tick();
}
function stopLoop() {
  if (animId) { cancelAnimationFrame(animId); animId = null; }
}

// ── Управление оверлеем ──────────────────────────────────────────────────
window._arShow = function(modelUrl, modelName) {
  arLabel.textContent = modelName || '3D Model';
  overlay.classList.add('active');
  resizeRenderer();
  startLoop();
  loadModel(modelUrl);
};

window._arHide = function() {
  overlay.classList.remove('active');
  stopLoop();
};

// ── Интеграция с WebSocket (основной скрипт ниже) ────────────────────────
window._onWsMessage = function(msg) {
  if (msg.type === 'ar_start') {
    window._arShow(msg.modelUrl, msg.modelName);
  } else if (msg.type === 'ar_stop') {
    window._arHide();
  } else if (msg.type === 'state' && msg.arActive) {
    window._arShow(msg.modelUrl, msg.modelName);
  } else if (msg.type === 'state' && !msg.arActive) {
    window._arHide();
  }
};
</script>

<script>
const initialSlideIndex = $initialIndex;
const hud   = document.getElementById('hud');
const deck  = document.getElementById('deck');
const slides = deck.querySelectorAll('.slide');
let current = 0;
let ws = null;
let wsReady = false;

/* ── Масштабирование слайда под любой экран ─────────────────────────── */
function scale() {
  const sw = $w, sh = $h;
  const s  = Math.min(window.innerWidth / sw, window.innerHeight / sh);
  const ox = (window.innerWidth  - sw * s) / 2;
  const oy = (window.innerHeight - sh * s) / 2;
  slides.forEach(slide => {
    slide.style.transform = 'translate(' + ox + 'px,' + oy + 'px) scale(' + s + ')';
  });
}

/* ── Показ слайда ───────────────────────────────────────────────────── */
function showSlide(n, sendToServer) {
  if (!slides.length) return;
  slides.forEach(s => s.classList.remove('active'));
  current = Math.max(0, Math.min(n, slides.length - 1));
  slides[current].classList.add('active');
  hud.textContent = (current + 1) + ' / ' + slides.length + (wsReady ? ' • online' : ' • offline');
  if (sendToServer && ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'goto', index: current }));
  }
}

/* ── WebSocket ──────────────────────────────────────────────────────── */
function connect() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(proto + '//' + location.host + '/ws');

  ws.onopen = () => {
    wsReady = true;
    ws.send(JSON.stringify({ type: 'ready' }));
    hud.textContent = 'Подключено';
  };

  ws.onclose = () => {
    wsReady = false;
    hud.textContent = 'Переподключение…';
    setTimeout(connect, 1500);
  };

  ws.onerror = () => { wsReady = false; };

  ws.onmessage = e => {
    try {
      const msg = JSON.parse(e.data);
      // AR-режим
      if (window._onWsMessage) window._onWsMessage(msg);
      // Навигация по слайдам
      if ((msg.type === 'state' || msg.type === 'goto') && typeof msg.index === 'number') {
        showSlide(msg.index, false);
      }
    } catch (_) {}
  };
}

/* ── Клавиатура ─────────────────────────────────────────────────────── */
document.addEventListener('keydown', e => {
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === ' ') {
    showSlide(current + 1, true);
  }
  if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
    showSlide(current - 1, true);
  }
});

window.addEventListener('resize', scale);
scale();
showSlide(initialSlideIndex, false);
connect();
</script>
</body>
</html>''';
  }

  // ── Слайд ─────────────────────────────────────────────────────────────────

  String _slideToHtml(EditableSlide slide) {
    final bg = _backgroundStyle(slide.background);
    final shapes = slide.originalShapes
        .map((shape) => _shapeToHtml(shape, slide))
        .join('\n');

    return '  <section class="slide" data-index="${slide.slideIndex}" style="$bg">\n'
        '$shapes\n'
        '  </section>';
  }

  // ── Шейпы ─────────────────────────────────────────────────────────────────

  String _shapeToHtml(SlideShape shape, EditableSlide slide) {
    if (shape is TextShape) {
      final editable = _editableShapeFor(slide, shape.shapeId);
      return _textShapeToHtml(shape, editable);
    }
    if (shape is ImageShape) return _imageShapeToHtml(shape);
    if (shape is GeometricShape) return _geometryShapeToHtml(shape);
    if (shape is LineShape) return _lineShapeToHtml(shape);
    return '';
  }

  EditableShape? _editableShapeFor(EditableSlide slide, String shapeId) {
    for (final shape in slide.editableShapes) {
      if (shape.shapeId == shapeId) return shape;
    }
    return null;
  }

  // ── Текстовый шейп ────────────────────────────────────────────────────────

  String _textShapeToHtml(TextShape shape, EditableShape? editable) {
    final b = shape.bounds;
    final outerStyle =
        _positionStyle(b) +
        _rotationAndFlipStyle(shape.rotationDegrees, shape.flipH, shape.flipV);

    final padding = shape.insets.edgeInsets;

    // Вертикальное выравнивание — flex justify-content.
    final vertAlign = _verticalAlignCss(shape.verticalAlignment);

    final content = editable != null
        ? _editableTextContent(shape, editable)
        : _originalTextContent(shape);

    return '''    <div class="shape text-shape" data-shape="${shape.shapeId}" style="$outerStyle">
      <div class="text-box" style="padding:${padding.top.toStringAsFixed(1)}px ${padding.right.toStringAsFixed(1)}px ${padding.bottom.toStringAsFixed(1)}px ${padding.left.toStringAsFixed(1)}px;$vertAlign">
$content
      </div>
    </div>''';
  }

  String _verticalAlignCss(VerticalAlignment va) {
    switch (va) {
      case VerticalAlignment.middle:
        return 'justify-content:center;';
      case VerticalAlignment.bottom:
        return 'justify-content:flex-end;';
      case VerticalAlignment.top:
        return 'justify-content:flex-start;';
    }
  }

  String _editableTextContent(TextShape shape, EditableShape editable) {
    final count = shape.paragraphs.length < editable.paragraphRuns.length
        ? shape.paragraphs.length
        : editable.paragraphRuns.length;

    final paragraphs = List.generate(count, (i) {
      return _paragraphToHtml(
        shape.paragraphs[i],
        editableRuns: editable.paragraphRuns[i],
      );
    });

    return paragraphs.isEmpty
        ? '        <p class="paragraph"></p>'
        : paragraphs.join('\n');
  }

  String _originalTextContent(TextShape shape) {
    final paragraphs = shape.paragraphs.map(_paragraphToHtml).toList();
    return paragraphs.isEmpty
        ? '        <p class="paragraph"></p>'
        : paragraphs.join('\n');
  }

  // ── Параграф ──────────────────────────────────────────────────────────────

  String _paragraphToHtml(
    TextParagraph paragraph, {
    List<EditableRun>? editableRuns,
  }) {
    final styleParts = <String>[];

    if (paragraph.format.alignment != null) {
      styleParts.add('text-align:${_textAlignCss(paragraph.format.alignment)}');
    }

    // PowerPoint по умолчанию ~1.15; 1.0 слишком плотный и вызывал наезд строк.
    final lineHeight = paragraph.format.lineSpacing ?? 1.15;
    styleParts.add('line-height:$lineHeight');

    if (paragraph.format.spaceBefore != null) {
      styleParts.add(
        'margin-top:${paragraph.format.spaceBefore!.toStringAsFixed(1)}px',
      );
    }
    if (paragraph.format.spaceAfter != null) {
      styleParts.add(
        'margin-bottom:${paragraph.format.spaceAfter!.toStringAsFixed(1)}px',
      );
    }
    if (paragraph.format.marginLeft != null) {
      styleParts.add(
        'margin-left:${paragraph.format.marginLeft!.toStringAsFixed(1)}px',
      );
    }
    if (paragraph.format.indent != null) {
      styleParts.add(
        'text-indent:${paragraph.format.indent!.toStringAsFixed(1)}px',
      );
    }

    final spans = <String>[];

    final bullet = paragraph.format.bullet;
    if (bullet?.character != null) {
      final bulletStyle = <String>[];
      if (bullet!.color != null) {
        bulletStyle.add('color:#${_colorToHex(bullet.color!)}');
      }
      if (bullet.sizePx != null) {
        bulletStyle.add('font-size:${bullet.sizePx!.toStringAsFixed(1)}px');
      }
      spans.add(
        '<span class="bullet" style="${bulletStyle.join(';')}">'
        '${_escapeHtml('${bullet.character} ')}</span>',
      );
    }

    if (editableRuns != null) {
      for (final run in editableRuns) {
        spans.add(
          '<span data-id="${run.runId}" style="${_runStyle(run)}">'
          '${_escapeHtml(run.text)}</span>',
        );
      }
    } else {
      for (final run in paragraph.runs) {
        spans.add(
          '<span style="${_originalRunStyle(run)}">'
          '${_escapeHtml(run.text)}</span>',
        );
      }
    }

    return '        <p class="paragraph" style="${styleParts.join(';')}">'
        '${spans.join('')}</p>';
  }

  // ── Другие шейпы ──────────────────────────────────────────────────────────

  String _imageShapeToHtml(ImageShape shape) {
    final b = shape.bounds;
    final outerStyle =
        _positionStyle(b) +
        _rotationAndFlipStyle(shape.rotationDegrees, shape.flipH, shape.flipV);

    final mime = _guessImageMimeType(shape.imageBytes);
    final dataUrl = 'data:$mime;base64,${base64Encode(shape.imageBytes)}';

    return '    <div class="shape image-shape" data-shape="${shape.shapeId}" style="$outerStyle">'
        '<img src="$dataUrl" style="width:100%;height:100%;object-fit:${_boxFitCss(shape.fit)};display:block;"/>'
        '</div>';
  }

  String _geometryShapeToHtml(GeometricShape shape) {
    final b = shape.bounds;
    final outerStyle =
        _positionStyle(b) +
        _rotationAndFlipStyle(shape.rotationDegrees, shape.flipH, shape.flipV);

    final fillStyle = _shapeFillCss(shape.fill);
    final outlineStyle = _shapeOutlineCss(shape.outline);
    final clipStyle = _geometryClipCss(shape.geometry);

    return '    <div class="shape geometry-shape" data-shape="${shape.shapeId}" '
        'style="$outerStyle$fillStyle$outlineStyle$clipStyle"></div>';
  }

  String _lineShapeToHtml(LineShape shape) {
    final b = shape.bounds;
    final outerStyle =
        _positionStyle(b) +
        _rotationAndFlipStyle(shape.rotationDegrees, false, false);

    return '    <div class="shape line-shape" data-shape="${shape.shapeId}" '
        'style="${outerStyle}background-color:#${_colorToHex(shape.color)};'
        'height:${shape.widthPx.toStringAsFixed(1)}px;"></div>';
  }

  // ── CSS-хелперы ───────────────────────────────────────────────────────────

  String _positionStyle(ShapeBounds b) =>
      'left:${b.x.toStringAsFixed(1)}px;'
      'top:${b.y.toStringAsFixed(1)}px;'
      'width:${b.width.toStringAsFixed(1)}px;'
      'height:${b.height.toStringAsFixed(1)}px;';

  String _rotationAndFlipStyle(double rotationDegrees, bool flipH, bool flipV) {
    final transforms = <String>[];
    if (flipH) transforms.add('scaleX(-1)');
    if (flipV) transforms.add('scaleY(-1)');
    if (rotationDegrees != 0) {
      transforms.add('rotate(${rotationDegrees.toStringAsFixed(3)}deg)');
    }
    if (transforms.isEmpty) return '';
    return 'transform:${transforms.join(' ')};';
  }

  String _originalRunStyle(TextRun run) {
    final f = run.format;
    final parts = <String>[];
    if (f.fontFamily != null) parts.add('font-family:${f.fontFamily}');
    if (f.fontSizePx != null)
      parts.add('font-size:${f.fontSizePx!.toStringAsFixed(1)}px');
    if (f.color != null) parts.add('color:#${_colorToHex(f.color!)}');
    if (f.bold) parts.add('font-weight:bold');
    if (f.italic) parts.add('font-style:italic');
    if (f.underline || f.strikethrough) {
      final deco = <String>[];
      if (f.underline) deco.add('underline');
      if (f.strikethrough) deco.add('line-through');
      parts.add('text-decoration:${deco.join(' ')}');
    }
    if (f.charSpacingPx != null) {
      parts.add('letter-spacing:${f.charSpacingPx!.toStringAsFixed(1)}px');
    }
    return parts.join(';');
  }

  String _runStyle(EditableRun run) {
    final parts = <String>[];
    if (run.color != null) parts.add('color:#${_colorToHex(run.color!)}');
    if (run.fontSizePx != null)
      parts.add('font-size:${run.fontSizePx!.toStringAsFixed(1)}px');
    if (run.bold) parts.add('font-weight:bold');
    if (run.italic) parts.add('font-style:italic');
    return parts.join(';');
  }

  String _shapeFillCss(ShapeFill? fill) {
    if (fill is SolidShapeFill) {
      return 'background-color:#${_colorToHex(fill.color)};';
    }
    if (fill is GradientShapeFill) {
      final stops = fill.stops
          .map((s) {
            final pct = (s.position * 100).clamp(0, 100).toStringAsFixed(2);
            return '#${_colorToHex(s.color)} ${pct}%';
          })
          .join(',');
      return 'background:linear-gradient(${fill.angle}deg,$stops);';
    }
    return 'background-color:transparent;';
  }

  String _shapeOutlineCss(ShapeOutline? outline) {
    if (outline == null || outline.style == OutlineStyle.none)
      return 'border:none;';
    return 'border:${outline.widthPx.toStringAsFixed(1)}px solid '
        '#${_colorToHex(outline.color)};';
  }

  String _geometryClipCss(GeometryType geometry) {
    switch (geometry) {
      case GeometryType.ellipse:
        return 'border-radius:50%;';
      case GeometryType.roundRect:
        return 'border-radius:18px;';
      case GeometryType.triangle:
        return 'clip-path:polygon(50% 0%,100% 100%,0% 100%);';
      case GeometryType.diamond:
        return 'clip-path:polygon(50% 0%,100% 50%,50% 100%,0% 50%);';
      default:
        return '';
    }
  }

  String _textAlignCss(TextAlign? align) {
    switch (align) {
      case TextAlign.center:
        return 'center';
      case TextAlign.right:
      case TextAlign.end:
        return 'right';
      case TextAlign.justify:
        return 'justify';
      default:
        return 'left';
    }
  }

  String _boxFitCss(BoxFit fit) {
    switch (fit) {
      case BoxFit.fill:
        return 'fill';
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fitWidth:
      case BoxFit.fitHeight:
      case BoxFit.contain:
      case BoxFit.scaleDown:
        return 'contain';
      case BoxFit.none:
        return 'none';
    }
  }

  String _backgroundStyle(SlideBackground bg) {
    if (bg is SolidBackground) {
      return 'background-color:#${_colorToHex(bg.color)};';
    }
    if (bg is GradientBackground) {
      final stops = bg.stops
          .map((s) {
            final pct = (s.position * 100).clamp(0, 100).toStringAsFixed(2);
            return '#${_colorToHex(s.color)} ${pct}%';
          })
          .join(',');
      return 'background:linear-gradient(${bg.angle}deg,$stops);';
    }
    if (bg is ImageBackground) {
      final dataUrl = 'data:image/png;base64,${base64Encode(bg.imageBytes)}';
      return 'background-image:url("$dataUrl");'
          'background-size:${_boxFitToBackgroundSize(bg.fit)};'
          'background-position:center;'
          'background-repeat:no-repeat;';
    }
    return 'background-color:#ffffff;';
  }

  String _boxFitToBackgroundSize(BoxFit fit) {
    switch (fit) {
      case BoxFit.fill:
        return '100% 100%';
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fitWidth:
        return '100% auto';
      case BoxFit.fitHeight:
        return 'auto 100%';
      case BoxFit.none:
        return 'auto';
      case BoxFit.contain:
      case BoxFit.scaleDown:
        return 'contain';
    }
  }

  String _guessImageMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A)
      return 'image/png';

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        bytes[5] == 0x61)
      return 'image/gif';

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50)
      return 'image/webp';

    return 'image/png';
  }

  String _colorToHex(Color color) =>
      color.value.toRadixString(16).padLeft(8, '0').substring(2);

  String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
