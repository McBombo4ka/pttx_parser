// =============================================================================
// slide_models.dart
// Core data models representing the parsed structure of a PPTX presentation.
// EMU (English Metric Units): 914400 EMUs = 1 inch = 96 logical pixels (at 96dpi)
// =============================================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// EMU conversion helpers
// ---------------------------------------------------------------------------

/// Converts EMUs to logical pixels at 96 dpi.
/// 1 inch = 914400 EMU = 96 logical pixels → factor = 96 / 914400
double emuToLogicalPixels(int emu) => emu * 96.0 / 914400.0;

/// Converts points (pt) to logical pixels (1 pt = 1/72 inch = 96/72 px).
double ptToLogicalPixels(double pt) => pt * 96.0 / 72.0;

/// Converts half-points (hundredths of a point, used in OOXML font sizes) to logical px.
double halfPointToLogicalPixels(int halfPt) => ptToLogicalPixels(halfPt / 200.0);

// ---------------------------------------------------------------------------
// Presentation-level model
// ---------------------------------------------------------------------------

/// Top-level model for a parsed PPTX file.
class PptxPresentation {
  final SlideSize slideSize;
  final List<SlideData> slides;
  final PresentationTheme theme;

  const PptxPresentation({
    required this.slideSize,
    required this.slides,
    required this.theme,
  });
}

/// Physical slide dimensions in EMUs.
class SlideSize {
  final int widthEmu;
  final int heightEmu;

  const SlideSize({required this.widthEmu, required this.heightEmu});

  /// Default widescreen 16:9 (10 in × 5.625 in).
  static const SlideSize widescreen = SlideSize(
    widthEmu: 9144000,
    heightEmu: 5143500,
  );

  double get widthPx => emuToLogicalPixels(widthEmu);
  double get heightPx => emuToLogicalPixels(heightEmu);
  double get aspectRatio => widthEmu / heightEmu;
}

// ---------------------------------------------------------------------------
// Theme model
// ---------------------------------------------------------------------------

/// Minimal theme colours extracted from theme1.xml (dk1, lt1, accent1–6, etc.)
class PresentationTheme {
  final Color? dk1; // dark 1
  final Color? lt1; // light 1
  final Color? dk2;
  final Color? lt2;
  final List<Color> accents; // accent1–accent6
  final String? majorFont; // heading font
  final String? minorFont; // body font

  const PresentationTheme({
    this.dk1,
    this.lt1,
    this.dk2,
    this.lt2,
    this.accents = const [],
    this.majorFont,
    this.minorFont,
  });

  static const PresentationTheme empty = PresentationTheme();

  /// Resolve a scheme colour reference to a concrete [Color].
  Color? resolveSchemeColor(String schemeClr) {
    switch (schemeClr) {
      case 'dk1':
        return dk1;
      case 'lt1':
        return lt1;
      case 'dk2':
        return dk2;
      case 'lt2':
        return lt2;
      case 'accent1':
        return accents.elementAtOrNull(0);
      case 'accent2':
        return accents.elementAtOrNull(1);
      case 'accent3':
        return accents.elementAtOrNull(2);
      case 'accent4':
        return accents.elementAtOrNull(3);
      case 'accent5':
        return accents.elementAtOrNull(4);
      case 'accent6':
        return accents.elementAtOrNull(5);
      default:
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Slide model
// ---------------------------------------------------------------------------

/// All data for a single slide, ready for rendering.
class SlideData {
  final int slideIndex; // 0-based
  final SlideBackground background;
  final List<SlideShape> shapes;

  const SlideData({
    required this.slideIndex,
    required this.background,
    required this.shapes,
  });
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

sealed class SlideBackground {
  const SlideBackground();
}

class SolidBackground extends SlideBackground {
  final Color color;
  const SolidBackground(this.color);
}

class GradientBackground extends SlideBackground {
  final List<GradientStop> stops;
  final double angle; // degrees
  const GradientBackground({required this.stops, required this.angle});
}

class ImageBackground extends SlideBackground {
  final Uint8List imageBytes;
  final BoxFit fit;
  const ImageBackground({required this.imageBytes, this.fit = BoxFit.cover});
}

class NoBackground extends SlideBackground {
  const NoBackground();
}

class GradientStop {
  final Color color;
  final double position; // 0.0–1.0
  const GradientStop({required this.color, required this.position});
}

// ---------------------------------------------------------------------------
// Shape model
// ---------------------------------------------------------------------------

/// Bounding box in logical pixels (already converted from EMU).
class ShapeBounds {
  final double x, y, width, height;
  const ShapeBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  factory ShapeBounds.fromEmu({
    required int xEmu,
    required int yEmu,
    required int widthEmu,
    required int heightEmu,
  }) {
    return ShapeBounds(
      x: emuToLogicalPixels(xEmu),
      y: emuToLogicalPixels(yEmu),
      width: emuToLogicalPixels(widthEmu),
      height: emuToLogicalPixels(heightEmu),
    );
  }
}

/// Base class for all renderable shapes on a slide.
sealed class SlideShape {
  final String shapeId;
  final ShapeBounds bounds;
  final double rotationDegrees; // clockwise
  final bool flipH;
  final bool flipV;
  final ShapeFill? fill;
  final ShapeOutline? outline;

  const SlideShape({
    required this.shapeId,
    required this.bounds,
    this.rotationDegrees = 0,
    this.flipH = false,
    this.flipV = false,
    this.fill,
    this.outline,
  });
}

// ---------------------------------------------------------------------------
// Shape subtypes
// ---------------------------------------------------------------------------

/// A text box / placeholder with styled text content.
class TextShape extends SlideShape {
  final List<TextParagraph> paragraphs;
  final TextInsets insets;
  final bool wordWrap;
  final VerticalAlignment verticalAlignment;
  final GeometryType geometry; // rect, roundRect, etc.

  const TextShape({
    required super.shapeId,
    required super.bounds,
    super.rotationDegrees,
    super.flipH,
    super.flipV,
    super.fill,
    super.outline,
    required this.paragraphs,
    this.insets = const TextInsets(),
    this.wordWrap = true,
    this.verticalAlignment = VerticalAlignment.top,
    this.geometry = GeometryType.rect,
  });

  String get plainText {
  return paragraphs
      .map(
        (p) => p.runs.map((r) => r.text).join(),
      )
      .join('\n');
}
}

/// A plain geometric shape (rectangle, ellipse, etc.) with optional text.
class GeometricShape extends SlideShape {
  final GeometryType geometry;
  final List<TextParagraph> paragraphs; // shapes can also contain text

  const GeometricShape({
    required super.shapeId,
    required super.bounds,
    super.rotationDegrees,
    super.flipH,
    super.flipV,
    super.fill,
    super.outline,
    required this.geometry,
    this.paragraphs = const [],
  });
}

/// An image shape (picture element).
class ImageShape extends SlideShape {
  final Uint8List imageBytes;
  final BoxFit fit;

  const ImageShape({
    required super.shapeId,
    required super.bounds,
    super.rotationDegrees,
    super.flipH,
    super.flipV,
    super.fill,
    super.outline,
    required this.imageBytes,
    this.fit = BoxFit.contain,
  });
}

/// A line connector.
class LineShape extends SlideShape {
  final Color color;
  final double widthPx;

  const LineShape({
    required super.shapeId,
    required super.bounds,
    super.rotationDegrees,
    super.fill,
    super.outline,
    required this.color,
    this.widthPx = 1.0,
  });
}

// ---------------------------------------------------------------------------
// Geometry enum
// ---------------------------------------------------------------------------

enum GeometryType {
  rect,
  roundRect,
  ellipse,
  triangle,
  rightTriangle,
  parallelogram,
  trapezoid,
  diamond,
  pentagon,
  hexagon,
  heptagon,
  octagon,
  star4,
  star5,
  star6,
  star7,
  star8,
  star10,
  star12,
  star16,
  star24,
  star32,
  cloud,
  callout,
  arrow,
  unknown;

  /// Parse the OOXML prstGeom val attribute.
  static GeometryType fromOoxmlName(String? name) {
    switch (name) {
      case 'rect':
        return GeometryType.rect;
      case 'roundRect':
        return GeometryType.roundRect;
      case 'ellipse':
        return GeometryType.ellipse;
      case 'triangle':
        return GeometryType.triangle;
      case 'rtTriangle':
        return GeometryType.rightTriangle;
      case 'parallelogram':
        return GeometryType.parallelogram;
      case 'trapezoid':
        return GeometryType.trapezoid;
      case 'diamond':
        return GeometryType.diamond;
      case 'pentagon':
        return GeometryType.pentagon;
      case 'hexagon':
        return GeometryType.hexagon;
      case 'star4':
        return GeometryType.star4;
      case 'star5':
        return GeometryType.star5;
      case 'star6':
        return GeometryType.star6;
      case 'star8':
        return GeometryType.star8;
      case 'cloud':
        return GeometryType.cloud;
      default:
        return GeometryType.unknown;
    }
  }
}

// ---------------------------------------------------------------------------
// Fill and outline
// ---------------------------------------------------------------------------

sealed class ShapeFill {
  const ShapeFill();
}

class SolidShapeFill extends ShapeFill {
  final Color color;
  const SolidShapeFill(this.color);
}

class GradientShapeFill extends ShapeFill {
  final List<GradientStop> stops;
  final double angle;
  const GradientShapeFill({required this.stops, required this.angle});
}

class NoShapeFill extends ShapeFill {
  const NoShapeFill();
}

class ShapeOutline {
  final Color color;
  final double widthPx;
  final OutlineStyle style;

  const ShapeOutline({
    required this.color,
    this.widthPx = 1.0,
    this.style = OutlineStyle.solid,
  });
}

enum OutlineStyle { solid, dashed, dotted, none }

// ---------------------------------------------------------------------------
// Text models
// ---------------------------------------------------------------------------

/// A paragraph of text with its paragraph-level formatting.
class TextParagraph {
  final List<TextRun> runs;
  final ParagraphFormat format;

  const TextParagraph({required this.runs, this.format = const ParagraphFormat()});

  bool get isEmpty => runs.isEmpty || runs.every((r) => r.text.isEmpty);
}

/// A single styled run of text within a paragraph.
class TextRun {
  final String text;
  final TextRunFormat format;

  const TextRun({required this.text, this.format = const TextRunFormat()});
}

/// Paragraph-level formatting (alignment, spacing, bullets, indent).
class ParagraphFormat {
  final TextAlign? alignment;
  final double? lineSpacing; // multiplier, e.g. 1.5
  final double? spaceBefore; // logical pixels
  final double? spaceAfter;
  final double? indent; // first line indent in logical px
  final double? marginLeft; // left margin in logical px
  final BulletFormat? bullet;

  const ParagraphFormat({
    this.alignment,
    this.lineSpacing,
    this.spaceBefore,
    this.spaceAfter,
    this.indent,
    this.marginLeft,
    this.bullet,
  });
}

class BulletFormat {
  final String? character; // e.g. '•'
  final Color? color;
  final double? sizePx;

  const BulletFormat({this.character, this.color, this.sizePx});
}

/// Run-level formatting (font, size, color, decoration).
class TextRunFormat {
  final String? fontFamily;
  final double? fontSizePx; // already converted from half-points
  final Color? color;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final double? charSpacingPx; // tracking / letter-spacing

  const TextRunFormat({
    this.fontFamily,
    this.fontSizePx,
    this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.charSpacingPx,
  });

  TextStyle toTextStyle({Color? fallbackColor, String? fallbackFont}) {
    return TextStyle(
      fontFamily: fontFamily ?? fallbackFont,
      fontSize: fontSizePx,
      color: color ?? fallbackColor ?? Colors.black,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      decoration: _decoration,
      letterSpacing: charSpacingPx,
    );
  }

  TextDecoration get _decoration {
    if (underline && strikethrough) {
      return TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]);
    } else if (underline) {
      return TextDecoration.underline;
    } else if (strikethrough) {
      return TextDecoration.lineThrough;
    }
    return TextDecoration.none;
  }
}

/// Internal padding / insets of a text box (in logical pixels).
class TextInsets {
  final double left, top, right, bottom;

  const TextInsets({
    this.left = 7.0,
    this.top = 3.7,
    this.right = 7.0,
    this.bottom = 3.7,
  });

  EdgeInsets get edgeInsets => EdgeInsets.fromLTRB(left, top, right, bottom);

  factory TextInsets.fromEmu({
    required int leftEmu,
    required int topEmu,
    required int rightEmu,
    required int bottomEmu,
  }) {
    return TextInsets(
      left: emuToLogicalPixels(leftEmu),
      top: emuToLogicalPixels(topEmu),
      right: emuToLogicalPixels(rightEmu),
      bottom: emuToLogicalPixels(bottomEmu),
    );
  }
}

enum VerticalAlignment { top, middle, bottom }

// ---------------------------------------------------------------------------
// Extension helpers
// ---------------------------------------------------------------------------

extension ListExt<T> on List<T> {
  T? elementAtOrNull(int index) =>
      index >= 0 && index < length ? this[index] : null;
}
