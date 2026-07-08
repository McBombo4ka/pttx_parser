import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'edit_models.dart';

class ShapeEditScreen extends StatefulWidget {
  final int slideIndex;
  final EditableShape shape;

  const ShapeEditScreen({
    super.key,
    required this.slideIndex,
    required this.shape,
  });

  @override
  State<ShapeEditScreen> createState() => _ShapeEditScreenState();
}

class _ShapeEditScreenState extends State<ShapeEditScreen> {
  // Один контроллер на параграф
  late final List<_ParagraphEditor> _paragraphs;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _paragraphs = widget.shape.paragraphRuns.asMap().entries.map((entry) {
      final paraIndex = entry.key;
      final runs = entry.value;
      return _ParagraphEditor(
        paraIndex: paraIndex,
        runs: runs,
        onChanged: () => setState(() => _hasChanges = true),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final p in _paragraphs) {
      p.dispose();
    }
    super.dispose();
  }

  void _save() {
    final model = context.read<PresentationEditModel>();
    for (final para in _paragraphs) {
      for (final runEditor in para.runEditors) {
        model.updateRunText(
          widget.slideIndex,
          widget.shape.shapeId,
          runEditor.run.runId,
          runEditor.controller.text,
        );
      }
    }
    Navigator.of(context).pop();
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить изменения?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти без сохранения'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _save();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Редактирование текста'),
          actions: [
            if (_hasChanges)
              TextButton(
                onPressed: _save,
                child: const Text(
                  'Сохранить',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        body: _paragraphs.isEmpty
            ? const Center(child: Text('Нет текста для редактирования'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _paragraphs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ParagraphEditorWidget(
                  editor: _paragraphs[i],
                  index: i,
                ),
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Вспомогательные классы для управления контроллерами

class _RunEditor {
  final EditableRun run;
  final TextEditingController controller;

  _RunEditor({required this.run})
      : controller = TextEditingController(text: run.text);

  void dispose() => controller.dispose();
}

class _ParagraphEditor {
  final int paraIndex;
  final List<_RunEditor> runEditors;
  final VoidCallback onChanged;

  _ParagraphEditor({
    required this.paraIndex,
    required List<EditableRun> runs,
    required this.onChanged,
  }) : runEditors = runs.map((r) => _RunEditor(run: r)).toList() {
    for (final re in runEditors) {
      re.controller.addListener(onChanged);
    }
  }

  void dispose() {
    for (final re in runEditors) {
      re.dispose();
    }
  }
}

class _ParagraphEditorWidget extends StatelessWidget {
  final _ParagraphEditor editor;
  final int index;

  const _ParagraphEditorWidget({required this.editor, required this.index});

  @override
  Widget build(BuildContext context) {
    // Если один run в параграфе — одно поле
    // Если несколько (разные стили) — несколько полей с пометкой
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (editor.runEditors.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Абзац ${index + 1} — ${editor.runEditors.length} фрагментов',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ...editor.runEditors.asMap().entries.map((e) {
          final ri = e.key;
          final runEditor = e.value;
          return Padding(
            padding: EdgeInsets.only(
                top: ri > 0 ? 6 : 0),
            child: _RunTextField(
              runEditor: runEditor,
              label: editor.runEditors.length > 1
                  ? 'Фрагмент ${ri + 1}'
                  : 'Абзац ${index + 1}',
            ),
          );
        }),
      ],
    );
  }
}

class _RunTextField extends StatelessWidget {
  final _RunEditor runEditor;
  final String label;

  const _RunTextField({required this.runEditor, required this.label});

  @override
  Widget build(BuildContext context) {
    final run = runEditor.run;
    final styleHint = [
      if (run.bold) 'жирный',
      if (run.italic) 'курсив',
      if (run.fontSizePx != null)
        '${run.fontSizePx!.toStringAsFixed(0)}px',
    ].join(', ');

    return TextField(
      controller: runEditor.controller,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: TextStyle(
        fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
        fontSize: (run.fontSizePx ?? 14).clamp(10, 32),
        color: run.color ?? Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        helperText: styleHint.isEmpty ? null : styleHint,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}