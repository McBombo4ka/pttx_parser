import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'edit_models.dart';
import 'shape_edit_screen.dart';

class EditScreen extends StatefulWidget {
  final int initialSlideIndex;

  const EditScreen({super.key, required this.initialSlideIndex});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late int _slideIndex;

  @override
  void initState() {
    super.initState();
    _slideIndex = widget.initialSlideIndex;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PresentationEditModel>();
    final slide = model.slides[_slideIndex];
    final total = model.slides.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Редактор — слайд ${_slideIndex + 1} / $total'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Готово',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Навигация по слайдам
          _SlideNavigator(
            current: _slideIndex,
            total: total,
            onChanged: (i) => setState(() => _slideIndex = i),
          ),
          const Divider(height: 1),
          // Список редактируемых текстовых элементов
          Expanded(
            child: slide.editableShapes.isEmpty
                ? const Center(
                    child: Text(
                      'На этом слайде нет текстовых элементов',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: slide.editableShapes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final shape = slide.editableShapes[i];
                      return _ShapeCard(shape: shape, slideIndex: _slideIndex);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SlideNavigator extends StatelessWidget {
  final int current;
  final int total;
  final ValueChanged<int> onChanged;

  const _SlideNavigator({
    required this.current,
    required this.total,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: current > 0 ? () => onChanged(current - 1) : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(total, (i) {
                  final active = i == current;
                  return GestureDetector(
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(
                                context,
                              ).colorScheme.inversePrimary
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: current < total - 1
                ? () => onChanged(current + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ShapeCard extends StatelessWidget {
  final EditableShape shape;
  final int slideIndex;

  const _ShapeCard({required this.shape, required this.slideIndex});

  @override
  Widget build(BuildContext context) {
    final preview = shape.plainText.trim();
    final isEmpty = preview.isEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          child: const Icon(Icons.text_fields, color: Colors.blue, size: 20),
        ),
        title: Text(
          isEmpty ? '(пустой текстовый блок)' : preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        subtitle: Text(
          'ID: ${shape.shapeId}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ShapeEditScreen(slideIndex: slideIndex, shape: shape),
          ),
        ),
      ),
    );
  }
}
