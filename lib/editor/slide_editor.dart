import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ar_core/slide_models.dart';
import 'edit_models.dart';

class SlideEditor extends StatelessWidget {
  final int slideIndex;

  const SlideEditor({super.key, required this.slideIndex});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PresentationEditModel>();
    final slide = model.slides[slideIndex];

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Фон и non-text shapes рисуем как раньше через SlideCanvas
        Positioned.fill(child: _buildBackground(slide.background)),

        // Редактируемые текстовые shapes
        ...slide.editableShapes.map((s) => _EditableShapeWidget(
          shape: s,
          slideIndex: slideIndex,
        )),
      ],
    );
  }

  Widget _buildBackground(SlideBackground bg) {
    if (bg is SolidBackground) return ColoredBox(color: bg.color);
    if (bg is ImageBackground) {
      return Image.memory(bg.imageBytes, fit: bg.fit);
    }
    return const SizedBox.expand();
  }
}

class _EditableShapeWidget extends StatefulWidget {
  final EditableShape shape;
  final int slideIndex;

  const _EditableShapeWidget({
    required this.shape,
    required this.slideIndex,
  });

  @override
  State<_EditableShapeWidget> createState() => _EditableShapeWidgetState();
}

class _EditableShapeWidgetState extends State<_EditableShapeWidget> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.shape.bounds.rect;

    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: GestureDetector(
        onTap: () => setState(() => _editing = true),
        child: _editing
            ? _buildEditMode(context)
            : _buildViewMode(),
      ),
    );
  }

  Widget _buildViewMode() {
    // Отображение как обычно, но с рамкой-подсказкой что можно тапнуть
    final text = widget.shape.plainText;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: Text(text, overflow: TextOverflow.clip),
    );
  }

  Widget _buildEditMode(BuildContext context) {
    // Берём первый run первого параграфа для простого редактирования
    final allRuns = widget.shape.paragraphRuns.expand((p) => p).toList();
    if (allRuns.isEmpty) return _buildViewMode();

    return _ShapeTextEditor(
      shape: widget.shape,
      slideIndex: widget.slideIndex,
      onDone: () => setState(() => _editing = false),
    );
  }
}

class _ShapeTextEditor extends StatefulWidget {
  final EditableShape shape;
  final int slideIndex;
  final VoidCallback onDone;

  const _ShapeTextEditor({
    required this.shape,
    required this.slideIndex,
    required this.onDone,
  });

  @override
  State<_ShapeTextEditor> createState() => _ShapeTextEditorState();
}

class _ShapeTextEditorState extends State<_ShapeTextEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.shape.plainText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.95),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onDone,
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: _save,
                child: const Text('OK'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    final model = context.read<PresentationEditModel>();
    // Обновляем первый run первого параграфа новым текстом
    // (упрощение — полное решение разбивало бы по \n на параграфы)
    final allRuns = widget.shape.paragraphRuns.expand((p) => p).toList();
    if (allRuns.isNotEmpty) {
      model.updateRunText(
        widget.slideIndex,
        widget.shape.shapeId,
        allRuns.first.runId,
        _ctrl.text,
      );
    }
    widget.onDone();
  }
}