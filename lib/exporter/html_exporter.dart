import '../ar_core/slide_models.dart';
import '../editor/edit_models.dart';

class HtmlExporter {
  final PresentationEditModel model;

  HtmlExporter(this.model);

  String export() {
    final slides = model.slides.map(_slideToHtml).join('\n');
    final w = model.slideSize.widthPx;
    final h = model.slideSize.heightPx;

    return '''<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Presentation</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #111; display: flex;
         justify-content: center; align-items: center;
         height: 100vh; overflow: hidden; }
  .deck { position: relative; width: 100vw; height: 100vh; }
  .slide {
    display: none;
    position: absolute; inset: 0;
    width: ${w}px; height: ${h}px;
    transform-origin: top left;
  }
  .slide.active { display: block; }
  .shape {
    position: absolute;
    overflow: hidden;
  }
  .shape[contenteditable="true"] {
    outline: 2px solid #4A90E2;
    cursor: text;
  }
</style>
</head>
<body>
<div class="deck" id="deck">
$slides
</div>

<script>
// Масштабирование под любой экран
function scale() {
  const deck = document.getElementById('deck');
  const allSlides = deck.querySelectorAll('.slide');
  const sw = $w, sh = $h;
  const vw = (window.visualViewport?.width  ?? document.documentElement.clientWidth);
  const vh = (window.visualViewport?.height ?? document.documentElement.clientHeight);
  const s = Math.min(vw / sw, vh / sh);
  const ox = (vw - sw * s) / 2;
  const oy = (vh - sh * s) / 2;
  allSlides.forEach(slide => {
    slide.style.transform = `translate(\${ox}px, \${oy}px) scale(\${s})`;
  });
}
window.visualViewport?.addEventListener('resize', scale);
window.addEventListener('resize', scale);
scale();

let touchStartX = 0;
document.addEventListener('touchstart', e => { touchStartX = e.touches[0].clientX; }, { passive: true });
document.addEventListener('touchend', e => {
  const dx = e.changedTouches[0].clientX - touchStartX;
  if (Math.abs(dx) > 50) showSlide(dx < 0 ? current + 1 : current - 1);
});

// Переключение слайдов
let current = 0;
const slides = document.querySelectorAll('.slide');

function showSlide(n) {
  slides.forEach(s => s.classList.remove('active'));
  current = Math.max(0, Math.min(n, slides.length - 1));
  slides[current].classList.add('active');
}
showSlide(0);

document.addEventListener('keydown', e => {
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown') showSlide(current + 1);
  if (e.key === 'ArrowLeft'  || e.key === 'ArrowUp')   showSlide(current - 1);
});

// WebSocket — получаем команды от Flutter
</script>
const wsProto = location.protocol === 'https:' ? 'wss:' : 'ws:';
const ws = new WebSocket(`\${wsProto}//\${location.host}/ws`);
</script>
ws.onmessage = e => {
  const msg = JSON.parse(e.data);
  if (msg.type === 'next')  showSlide(current + 1);
  if (msg.type === 'prev')  showSlide(current - 1);
  if (msg.type === 'goto')  showSlide(msg.index);
  // Обновление текста run по data-id (live sync)
  if (msg.type === 'updateRun') {
    const el = document.querySelector('[data-id="\${msg.runId}"]');
    if (el) el.textContent = msg.text;
  }
};
</script>
</body>
</html>''';
  }

  String _slideToHtml(EditableSlide slide) {
    final shapes = slide.editableShapes.map(_shapeToHtml).join('\n  ');
    final bg = _backgroundStyle(slide.background);
    return '''  <section class="slide" data-index="${slide.slideIndex}" style="$bg">
  $shapes
  </section>''';
  }

String _shapeToHtml(EditableShape shape) {
    final b = shape.bounds;
    final style = 'left:${b.x.toStringAsFixed(1)}px;'
        'top:${b.y.toStringAsFixed(1)}px;'
        'width:${b.width.toStringAsFixed(1)}px;'
        'height:${b.height.toStringAsFixed(1)}px;';

    final runsHtml = shape.paragraphRuns.map((para) {
      final paraSpans = para.map((run) {
        final s = _runStyle(run);
        return '<span data-id="${run.runId}" style="$s">'
            '${_escapeHtml(run.text)}</span>';
      }).join('');
      final align = para.isNotEmpty && para.first.textAlign != null
          ? 'text-align:${para.first.textAlign};'
          : '';
      return '<p style="margin:0;$align">$paraSpans</p>';
    }).join('\n    ');

    return '''    <div class="shape" data-shape="${shape.shapeId}" style="$style">
    $runsHtml
    </div>''';
  }

  String _runStyle(EditableRun run) {
    final parts = <String>[];
    if (run.color != null) {
      parts.add('color:#${run.color!.value.toRadixString(16).substring(2)}');
    }
    if (run.fontSizePx != null) {
      parts.add('font-size:${run.fontSizePx!.toStringAsFixed(1)}px');
    }
    if (run.bold) parts.add('font-weight:bold');
    if (run.italic) parts.add('font-style:italic');
      if (run.textAlign != null) {
    parts.add('text-align:${run.textAlign}');
  }
    return parts.join(';');
  }

  String _backgroundStyle(SlideBackground bg) {
    if (bg is SolidBackground) {
      final hex = bg.color.value.toRadixString(16).padLeft(8, '0').substring(2);
      return 'background-color:#$hex;';
    }
    return 'background-color:#ffffff;';
  }

  String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}