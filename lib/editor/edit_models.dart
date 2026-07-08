import 'package:flutter/material.dart';
import '../ar_core/slide_models.dart';

// Редактируемый run — хранит изменения поверх оригинала
class EditableRun {
  final String runId;      // stable id для HTML data-id
  String text;
  Color? color;
  double? fontSizePx;
  bool bold;
  bool italic;
  String? textAlign;

  EditableRun({
    required this.runId,
    required this.text,
    this.color,
    this.fontSizePx,
    this.bold = false,
    this.italic = false,
    this.textAlign
  });

  // Создаём из оригинального TextRun
  factory EditableRun.fromRun(TextRun run, String id) => EditableRun(
    runId: id,
    text: run.text,
    color: run.format.color,
    fontSizePx: run.format.fontSizePx,
    bold: run.format.bold,
    italic: run.format.italic,
  );
}

class EditableShape {
  final String shapeId;
  ShapeBounds bounds;
  // Только TextShape редактируется — остальные пока readonly
  final List<List<EditableRun>> paragraphRuns; // [paragraph][run]

  EditableShape({
    required this.shapeId,
    required this.bounds,
    required this.paragraphRuns,
  });

  factory EditableShape.fromShape(SlideShape shape) {
    final runs = <List<EditableRun>>[];
    if (shape is TextShape) {
      for (var pi = 0; pi < shape.paragraphs.length; pi++) {
        final p = shape.paragraphs[pi];
        final rowRuns = <EditableRun>[];
        for (var ri = 0; ri < p.runs.length; ri++) {
          rowRuns.add(EditableRun.fromRun(
            p.runs[ri],
            '${shape.shapeId}_p${pi}_r$ri', // стабильный id
          ));
        }
        runs.add(rowRuns);
      }
    }
    return EditableShape(
      shapeId: shape.shapeId,
      bounds: shape.bounds,
      paragraphRuns: runs,
    );
  }

  String get plainText =>
      paragraphRuns.map((p) => p.map((r) => r.text).join()).join('\n');
}

class EditableSlide {
  final int slideIndex;
  final SlideBackground background;
  final List<SlideShape> originalShapes; // readonly, для рендера non-text
  final List<EditableShape> editableShapes;

  EditableSlide({
    required this.slideIndex,
    required this.background,
    required this.originalShapes,
    required this.editableShapes,
  });

  factory EditableSlide.fromSlide(SlideData slide) => EditableSlide(
    slideIndex: slide.slideIndex,
    background: slide.background,
    originalShapes: slide.shapes,
    editableShapes: slide.shapes
        .whereType<TextShape>()
        .map(EditableShape.fromShape)
        .toList(),
  );
}

// Главная редактируемая модель — ChangeNotifier для Provider
class PresentationEditModel extends ChangeNotifier {
  final SlideSize slideSize;
  final PresentationTheme theme;
  final List<EditableSlide> slides;

  PresentationEditModel({
    required this.slideSize,
    required this.theme,
    required this.slides,
  });

  factory PresentationEditModel.fromPresentation(PptxPresentation p) =>
      PresentationEditModel(
        slideSize: p.slideSize,
        theme: p.theme,
        slides: p.slides.map(EditableSlide.fromSlide).toList(),
      );

  // Изменить текст конкретного run
  void updateRunText(int slideIdx, String shapeId, String runId, String text) {
    _findRun(slideIdx, shapeId, runId)?.text = text;
    notifyListeners();
  }

  void updateRunStyle(
    int slideIdx,
    String shapeId,
    String runId, {
    Color? color,
    double? fontSizePx,
    bool? bold,
    bool? italic,
  }) {
    final run = _findRun(slideIdx, shapeId, runId);
    if (run == null) return;
    if (color != null) run.color = color;
    if (fontSizePx != null) run.fontSizePx = fontSizePx;
    if (bold != null) run.bold = bold;
    if (italic != null) run.italic = italic;
    notifyListeners();
  }

  EditableRun? _findRun(int slideIdx, String shapeId, String runId) {
    final shape = slides[slideIdx].editableShapes
        .where((s) => s.shapeId == shapeId)
        .firstOrNull;
    if (shape == null) return null;
    for (final para in shape.paragraphRuns) {
      for (final run in para) {
        if (run.runId == runId) return run;
      }
    }
    return null;
  }
}