import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ar_core/slide_models.dart';
import '../painters/diamond_painter.dart';
import '../painters/triangle_painter.dart';

class SlideCanvas extends StatelessWidget {
  final SlideData slide;
  final PresentationTheme theme;
  const SlideCanvas({super.key, required this.slide, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(child: _buildBackground(slide.background)),
        ...slide.shapes.map((shape) => _buildShape(shape)),
      ],
    );
  }

  Widget _buildBackground(SlideBackground bg) {
    if (bg is SolidBackground) {
      return ColoredBox(color: bg.color);
    }
    if (bg is ImageBackground) {
      return Positioned.fill(
        child: Image.memory(
          bg.imageBytes,
          fit: bg.fit,
          alignment: Alignment.center,
        ),
      );
    }
    if (bg is GradientBackground) {
      if (bg.stops.isEmpty) return const SizedBox.expand();
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bg.stops.map((s) => s.color).toList(),
            stops: bg.stops.map((s) => s.position).toList(),
            transform: GradientRotation(bg.angle * math.pi / 180.0),
          ),
        ),
      );
    }
    return const SizedBox.expand();
  }

  Widget _buildShape(SlideShape shape) {
    final r = shape.bounds.rect;
    // debugPrint('SHAPE TYPE: ${shape.runtimeType}');
    // debugPrint('SHAPE: ${shape.toString()}');
    if (shape is TextShape) {
      // debugPrint(
      //   'TEXT SHAPE: ${shape.geometry}, '
      //   'fill=${shape.fill.runtimeType}, '
      //   'outline=${shape.outline.runtimeType}',
      // );
      return Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height, //высота
        child: _buildTextShape(shape),
      );
    }
    if (shape is ImageShape) {
      return Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height,
        child: ClipRect(
          child: SizedBox(
            width: r.width,
            height: r.height,
            child: Image.memory(shape.imageBytes, fit: BoxFit.fill),
          ),
        ),
      );
    }
    if (shape is GeometricShape) {
      debugPrint(
        'GEOMETRY SHAPE: ${shape.geometry}, '
        'fill=${shape.fill.runtimeType}, '
        'outline=${shape.outline.runtimeType}',
      );
      return Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height,
        child: _buildTransformedBox(
          rotationDegrees: shape.rotationDegrees,
          flipH: shape.flipH,
          flipV: shape.flipV,
          child: _buildGeometryBox(shape, r.width, r.height),
        ),
      );
    }
    if (shape is LineShape) {
      return Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height,
        child: _buildTransformedBox(
          rotationDegrees: shape.rotationDegrees,
          flipH: shape.flipH,
          flipV: shape.flipV,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              height: shape.widthPx,
              width: double.infinity,
              color: shape.color,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTextShape(TextShape shape) {
    final content = _buildParagraphs(shape);
    Widget box = Container(
      padding: shape.insets.edgeInsets,
      decoration: _shapeDecoration(shape),
      child: content,
    );
    // Применяем геометрию к текстовому шейпу так же как к GeometricShape
    switch (shape.geometry) {
      case GeometryType.roundRect:
        box = ClipRRect(borderRadius: BorderRadius.circular(18), child: box);
        break;
      case GeometryType.ellipse:
        box = ClipOval(child: box);
        break;
      default:
        break;
    }
    return _buildTransformedBox(
      rotationDegrees: shape.rotationDegrees,
      flipH: shape.flipH,
      flipV: shape.flipV,
      child: box,
    );
  }
  TextAlign _dominantAlign(TextShape shape) {
    for (final p in shape.paragraphs) {
      if (p.format.alignment != null) return p.format.alignment!;
    }
    return TextAlign.left;
  }
  Widget _buildParagraphs(TextShape shape) {
    final textAlign = _dominantAlign(shape);
    final spans = <InlineSpan>[];
    for (final paragraph in shape.paragraphs) {
      if (paragraph.format.bullet?.character != null) {
        final bullet = paragraph.format.bullet!;
        spans.add(
          TextSpan(
            text: '${bullet.character} ',
            style: TextStyle(
              color: bullet.color ?? Colors.black,
              fontSize: bullet.sizePx,
            ),
          ),
        );
      }
      for (final run in paragraph.runs) {
        spans.add(
          TextSpan(
            text: run.text,
            style: run.format.toTextStyle(
              fallbackColor: theme.dk1 ?? Colors.black,
              fallbackFont: theme.minorFont,
            ),
          ),
        );
      }
      spans.add(const TextSpan(text: '\n'));
    }
    return RichText(
      text: TextSpan(children: spans),
      textAlign: textAlign,
      softWrap: true,
      overflow: TextOverflow.clip,
    );
    
  }

  Widget _buildGeometryBox(GeometricShape shape, double width, double height) {
    final fillDecoration = _shapeDecoration(shape);
    debugPrint('GEOMETRY: ${shape.geometry}, fill=${shape.fill}, decoration=$fillDecoration');
    final base = Container(
      width: width,
      height: height,
      decoration: fillDecoration,
    );
    switch (shape.geometry) {
      case GeometryType.ellipse:
        return ClipOval(child: base);
      case GeometryType.roundRect:
        return ClipRRect(borderRadius: BorderRadius.circular(18), child: base);
      case GeometryType.triangle:
        return CustomPaint(
          size: Size(width, height),
          painter: TrianglePainter(fillDecoration),
        );
      case GeometryType.diamond:
        return CustomPaint(
          size: Size(width, height),
          painter: DiamondPainter(fillDecoration),
        );
      default:
        return base;
    }
  }

  BoxDecoration? _shapeDecoration(SlideShape shape) {
    final fill = shape.fill;
    final outline = shape.outline;
    final border = outline == null || outline.style == OutlineStyle.none
        ? null
        : Border.all(color: outline.color, width: outline.widthPx);
    if (fill is SolidShapeFill) {
      return BoxDecoration(color: fill.color, border: border);
    }
    if (fill is GradientShapeFill) {
      return BoxDecoration(
        gradient: LinearGradient(
          colors: fill.stops.map((e) => e.color).toList(),
        ),
        border: border,
      );
    }
    if (fill is NoShapeFill) {
      return BoxDecoration(color: Colors.transparent, border: border);
    }
    return BoxDecoration(color: Colors.transparent, border: border);
  }

  Widget _buildTransformedBox({
    required Widget child,
    required double rotationDegrees,
    required bool flipH,
    required bool flipV,
  }) {
    final radians = rotationDegrees * math.pi / 180.0;
    final matrix = Matrix4.identity()
      ..translate(0.0, 0.0)
      ..rotateZ(radians)
      ..scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0, 1.0);
    return Transform(
      alignment: Alignment.center,
      transform: matrix,
      child: child,
    );
  }

  //   Gradient _gradientFromStops(List<GradientStop> stops, double angleDeg) {
  //     if (stops.isEmpty) {
  //       return const LinearGradient(colors: [Colors.white, Colors.white]);
  //     }
  //     final angle = angleDeg % 360;
  //     final rad = angle * math.pi / 180.0;
  //     final x = math.cos(rad);
  //     final y = math.sin(rad);
  //     return LinearGradient(
  //       begin: Alignment(-x, -y),
  //       end: Alignment(x, y),
  //       colors: stops.map((e) => e.color).toList(),
  //       stops: stops.map((e) => e.position).toList(),
  //     );
  //   }
}
