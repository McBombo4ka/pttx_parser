// =============================================================================
// pptx_parser.dart
// Asynchronous PPTX parsing service.
// =============================================================================

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'slide_models.dart';

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

extension XmlElementSearch on XmlElement {
  /// Ищет первый дочерний элемент с данным localName (только прямые дети).
  XmlElement? findFirstElement(String localName) {
    final name = localName.split(':').last;
    for (final child in childElements) {
      if (child.localName == name) return child;
    }
    return null;
  }

  /// Ищет первый элемент вглубь всего дерева (используй явно, когда нужно).
  XmlElement? findDeepElement(String localName) {
    final name = localName.split(':').last;
    try {
      return descendants.whereType<XmlElement>().firstWhere(
        (e) => e.localName == name,
      );
    } catch (_) {
      return null;
    }
  }
}

extension XmlDocumentSearch on XmlDocument {
  XmlElement? findFirstElement(String localName) {
    final name = localName.split(':').last;
    try {
      return descendants.whereType<XmlElement>().firstWhere(
        (e) => e.localName == name,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Slide context
// ---------------------------------------------------------------------------

/// Context for one slide: slide XML + resolved layout/master + media + theme.
class SlideContext {
  final XmlDocument slideDoc;
  final XmlDocument? layoutDoc;
  final XmlDocument? masterDoc;
  final Map<String, Uint8List> mediaByRId;
  final PresentationTheme theme;

  final Map<String, XmlElement> _layoutPhMap;
  final Map<String, XmlElement> _masterPhMap;

  SlideContext({
    required this.slideDoc,
    required this.layoutDoc,
    required this.masterDoc,
    required this.mediaByRId,
    required this.theme,
  }) : _layoutPhMap = _buildPhMap(layoutDoc),
       _masterPhMap = _buildPhMap(masterDoc);

  static Map<String, XmlElement> _buildPhMap(XmlDocument? doc) {
    if (doc == null) return {};

    final map = <String, XmlElement>{};

    for (final sp in doc.descendants.whereType<XmlElement>().where(
      (e) => e.localName == 'sp',
    )) {
      final ph = sp
          .findFirstElement('p:nvSpPr')
          ?.findFirstElement('p:nvPr')
          ?.findFirstElement('p:ph');

      if (ph == null) continue;

      final type = (ph.getAttribute('type') ?? '').trim();
      final idx = (ph.getAttribute('idx') ?? '').trim();

      if (type.isEmpty && idx.isEmpty) continue;

      map.putIfAbsent('$type:$idx', () => sp);
      if (type.isNotEmpty) {
        map.putIfAbsent('$type:', () => sp);
      }
      if (idx.isNotEmpty) {
        map.putIfAbsent(':$idx', () => sp);
      }
    }

    return map;
  }

  /// Resolve placeholder bounds in order: layout → master.
  ShapeBounds? resolvePlaceholderBounds(String? type, String? idx) {
    final t = (type ?? '').trim();
    final i = (idx ?? '').trim();

    if (t.isEmpty && i.isEmpty) return null;

    for (final map in [_layoutPhMap, _masterPhMap]) {
      final sp = map['$t:$i'] ?? map['$t:'] ?? map[':$i'];
      if (sp == null) continue;

      final bounds = _boundsFromSpElement(sp);
      if (bounds != null) return bounds;
    }

    return null;
  }

  ShapeBounds? _boundsFromSpElement(XmlElement sp) {
    final spPr = sp.findFirstElement('p:spPr');
    final xfrm = spPr?.findFirstElement('a:xfrm');
    final off = xfrm?.findFirstElement('a:off');
    final ext = xfrm?.findFirstElement('a:ext');
    if (off == null || ext == null) return null;

    return ShapeBounds.fromEmu(
      xEmu: int.tryParse(off.getAttribute('x') ?? '0') ?? 0,
      yEmu: int.tryParse(off.getAttribute('y') ?? '0') ?? 0,
      widthEmu: int.tryParse(ext.getAttribute('cx') ?? '0') ?? 0,
      heightEmu: int.tryParse(ext.getAttribute('cy') ?? '0') ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

Future<PptxPresentation> parsePptxFile(Uint8List fileBytes) {
  return Isolate.run(() => _PptxParserImpl(fileBytes).parse());
}

// ---------------------------------------------------------------------------
// Internal parser
// ---------------------------------------------------------------------------

class _PptxParserImpl {
  final Uint8List _bytes;
  late final Archive _archive;

  final Map<String, XmlDocument> _xmlCache = {};
  final Map<String, Uint8List> _mediaCache = {};

  _PptxParserImpl(this._bytes);

  // -------------------------------------------------------------------------
  // Entry point
  // -------------------------------------------------------------------------

  PptxPresentation parse() {
    _archive = ZipDecoder().decodeBytes(_bytes);
    _preloadMedia();

    final theme = _parseTheme();
    final slideSize = _parseSlideSize();
    final slideRefs = _parseSlideRefs();

    final slides = <SlideData>[];
    for (var i = 0; i < slideRefs.length; i++) {
      slides.add(_parseSlide(i, slideRefs[i], theme));
    }

    return PptxPresentation(slideSize: slideSize, slides: slides, theme: theme);
  }

  // -------------------------------------------------------------------------
  // Media pre-load
  // -------------------------------------------------------------------------

  void _preloadMedia() {
    for (final file in _archive.files) {
      if (file.isFile && file.name.startsWith('ppt/media/')) {
        final content = file.content;
        if (content is Uint8List) {
          _mediaCache[file.name] = content;
        } else if (content is List<int>) {
          _mediaCache[file.name] = Uint8List.fromList(content);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Archive helpers
  // -------------------------------------------------------------------------

  XmlDocument _getXml(String path) {
    final cached = _xmlCache[path];
    if (cached != null) return cached;

    final file = _archive.findFile(path);
    if (file == null) {
      throw StateError('Missing archive entry: $path');
    }

    final content = file.content;
    final bytes = content is Uint8List
        ? content
        : content is List<int>
        ? Uint8List.fromList(content)
        : throw StateError('Unsupported XML content type for $path');

    final doc = XmlDocument.parse(utf8.decode(bytes));
    _xmlCache[path] = doc;
    return doc;
  }

  XmlDocument? _tryGetXml(String path) {
    try {
      return _getXml(path);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _getMedia(String path) => _mediaCache[path];

  // -------------------------------------------------------------------------
  // Relationships helper
  // -------------------------------------------------------------------------

  Map<String, String> _parseRels(String relsPath) {
    final doc = _tryGetXml(relsPath);
    if (doc == null) return {};

    final result = <String, String>{};
    for (final rel in doc.descendants.whereType<XmlElement>()) {
      if (rel.localName != 'Relationship') continue;
      final id = rel.getAttribute('Id') ?? '';
      final target = rel.getAttribute('Target') ?? '';
      if (id.isNotEmpty && target.isNotEmpty) {
        result[id] = target;
      }
    }
    return result;
  }

  String _normalizePptxTarget(String target) {
    if (target.startsWith('../')) {
      return 'ppt/${target.substring(3)}';
    }
    if (target.startsWith('ppt/')) return target;
    return 'ppt/$target';
  }

  // -------------------------------------------------------------------------
  // Slide list
  // -------------------------------------------------------------------------

  List<String> _parseSlideRefs() {
    final rels = _parseRels('ppt/_rels/presentation.xml.rels');

    final presDoc = _getXml('ppt/presentation.xml');
    final sldIdList = presDoc.findAllElements('p:sldId');

    final orderedPaths = <String>[];
    for (final sldId in sldIdList) {
      final rId = sldId.getAttribute('r:id') ?? sldId.getAttribute('id');
      if (rId == null) continue;

      final rawTarget = rels[rId];
      if (rawTarget == null || rawTarget.isEmpty) continue;

      orderedPaths.add(_normalizePptxTarget(rawTarget));
    }

    return orderedPaths;
  }

  // -------------------------------------------------------------------------
  // Slide size
  // -------------------------------------------------------------------------

  SlideSize _parseSlideSize() {
    final doc = _getXml('ppt/presentation.xml');
    final sldSz = doc.findFirstElement('p:sldSz');
    if (sldSz == null) return SlideSize.widescreen;

    final cx = int.tryParse(sldSz.getAttribute('cx') ?? '') ?? 9144000;
    final cy = int.tryParse(sldSz.getAttribute('cy') ?? '') ?? 5143500;
    return SlideSize(widthEmu: cx, heightEmu: cy);
  }

  // -------------------------------------------------------------------------
  // Theme parsing
  // -------------------------------------------------------------------------

  PresentationTheme _parseTheme() {
    final doc = _tryGetXml('ppt/theme/theme1.xml');
    if (doc == null) return PresentationTheme.empty;

    Color? dk1, lt1, dk2, lt2;
    final accents = <Color>[];
    String? majorFont, minorFont;

    final clrScheme = doc.findFirstElement('a:clrScheme');
    if (clrScheme != null) {
      dk1 = _resolveThemeColorEl(clrScheme.findFirstElement('a:dk1'));
      lt1 = _resolveThemeColorEl(clrScheme.findFirstElement('a:lt1'));
      dk2 = _resolveThemeColorEl(clrScheme.findFirstElement('a:dk2'));
      lt2 = _resolveThemeColorEl(clrScheme.findFirstElement('a:lt2'));

      for (var i = 1; i <= 6; i++) {
        final c = _resolveThemeColorEl(
          clrScheme.findFirstElement('a:accent$i'),
        );
        if (c != null) accents.add(c);
      }
    }

    final fontScheme = doc.findFirstElement('a:fontScheme');
    majorFont = fontScheme
        ?.findFirstElement('a:majorFont')
        ?.findFirstElement('a:latin')
        ?.getAttribute('typeface');
    minorFont = fontScheme
        ?.findFirstElement('a:minorFont')
        ?.findFirstElement('a:latin')
        ?.getAttribute('typeface');

    return PresentationTheme(
      dk1: dk1,
      lt1: lt1,
      dk2: dk2,
      lt2: lt2,
      accents: accents,
      majorFont: majorFont,
      minorFont: minorFont,
    );
  }

  Color? _resolveThemeColorEl(XmlElement? el) {
    if (el == null) return null;

    final srgb = el.findFirstElement('a:srgbClr');
    if (srgb != null) return _hexToColor(srgb.getAttribute('val'));

    final sysClr = el.findFirstElement('a:sysClr');
    if (sysClr != null) {
      return _hexToColor(sysClr.getAttribute('lastClr'));
    }

    return null;
  }

  // -------------------------------------------------------------------------
  // Slide parsing
  // -------------------------------------------------------------------------

  SlideData _parseSlide(int index, String slidePath, PresentationTheme theme) {
    final ctx = _buildSlideContext(slidePath, theme);

    final background = _parseBackground(ctx);
    final shapes = _parseShapes(ctx);

    return SlideData(slideIndex: index, background: background, shapes: shapes);
  }

  SlideContext _buildSlideContext(String slidePath, PresentationTheme theme) {
    final slideDoc = _getXml(slidePath);

    final fileName = slidePath.split('/').last;
    final dirPart = slidePath.substring(0, slidePath.lastIndexOf('/'));
    final relsPath = '$dirPart/_rels/$fileName.rels';
    final rels = _parseRels(relsPath);

    XmlDocument? layoutDoc;
    XmlDocument? masterDoc;

    for (final target in rels.values) {
      if (!target.contains('slideLayout')) continue;

      final layoutPath = _normalizePptxTarget(target);
      layoutDoc = _tryGetXml(layoutPath);

      if (layoutDoc != null) {
        final layoutFile = layoutPath.split('/').last;
        final layoutRelsPath = 'ppt/slideLayouts/_rels/$layoutFile.rels';
        final layoutRels = _parseRels(layoutRelsPath);

        for (final relTarget in layoutRels.values) {
          if (!relTarget.contains('slideMaster')) continue;
          masterDoc = _tryGetXml(_normalizePptxTarget(relTarget));
          break;
        }
      }
      break;
    }

    final mediaByRId = <String, Uint8List>{};
    rels.forEach((rId, target) {
      final mediaPath = _normalizePptxTarget(target);
      final bytes = _getMedia(mediaPath);
      if (bytes != null) mediaByRId[rId] = bytes;
    });

    return SlideContext(
      slideDoc: slideDoc,
      layoutDoc: layoutDoc,
      masterDoc: masterDoc,
      mediaByRId: mediaByRId,
      theme: theme,
    );
  }

  // -------------------------------------------------------------------------
  // Background parsing
  // -------------------------------------------------------------------------

  SlideBackground _parseBackground(SlideContext ctx) {
    final bg = ctx.slideDoc.findFirstElement('p:bg');
    if (bg == null) return const NoBackground();

    final bgPr = bg.findFirstElement('p:bgPr');
    if (bgPr != null) {
      final solidFill = bgPr.findFirstElement('a:solidFill');
      if (solidFill != null) {
        final color = _resolveColor(solidFill, ctx.theme);
        if (color != null) return SolidBackground(color);
      }

      final gradFill = bgPr.findFirstElement('a:gradFill');
      if (gradFill != null) {
        final fill = _parseGradientFill(gradFill, ctx.theme);
        if (fill != null) {
          return GradientBackground(stops: fill.stops, angle: fill.angle);
        }
      }

      final blipFill = bgPr.findFirstElement('a:blipFill');
      if (blipFill != null) {
        final rId = blipFill
            .findFirstElement('a:blip')
            ?.getAttribute('r:embed');
        if (rId != null && ctx.mediaByRId.containsKey(rId)) {
          return ImageBackground(imageBytes: ctx.mediaByRId[rId]!);
        }
      }
    }

    return const NoBackground();
  }

  // -------------------------------------------------------------------------
  // Shape parsing
  // -------------------------------------------------------------------------

  List<SlideShape> _parseShapes(SlideContext ctx) {
    final spTree = ctx.slideDoc.findFirstElement('p:spTree');
    if (spTree == null) return [];

    final shapes = <SlideShape>[];
    final seenIds = <String>{};

    _walkSpTree(spTree, ctx, shapes, seenIds: seenIds, offsetX: 0, offsetY: 0);

    return shapes;
  }

  void _walkSpTree(
    XmlElement el,
    SlideContext ctx,
    List<SlideShape> out, {
    required Set<String> seenIds,
    required double offsetX,
    required double offsetY,
  }) {
    for (final child in el.childElements) {
      switch (child.localName) {
        case 'sp':
          final shapeId = _shapeIdFromSp(child);
          if (shapeId != null && !seenIds.add(shapeId)) {
            break;
          }

          final s = _parseSpElement(
            child,
            ctx,
            offsetX: offsetX,
            offsetY: offsetY,
          );
          if (s != null) out.add(s);
          break;

        case 'pic':
          final shapeId = _shapeIdFromPic(child);
          if (shapeId != null && !seenIds.add(shapeId)) {
            break;
          }

          final p = _parsePicElement(
            child,
            ctx,
            offsetX: offsetX,
            offsetY: offsetY,
          );
          if (p != null) out.add(p);
          break;

        case 'graphicFrame':
          final shapeId = _shapeIdFromGraphicFrame(child);
          if (shapeId != null && !seenIds.add(shapeId)) {
            break;
          }

          final g = _parseGraphicFrame(
            child,
            ctx,
            offsetX: offsetX,
            offsetY: offsetY,
          );
          if (g != null) out.add(g);
          break;

        case 'grpSp':
          final groupOffset = _groupOffset(child);
          _walkSpTree(
            child,
            ctx,
            out,
            seenIds: seenIds,
            offsetX: offsetX + groupOffset.dx,
            offsetY: offsetY + groupOffset.dy,
          );
          break;
      }
    }
  }

  String? _shapeIdFromSp(XmlElement el) {
    return el
        .findFirstElement('p:nvSpPr')
        ?.findFirstElement('p:cNvPr')
        ?.getAttribute('id');
  }

  String? _shapeIdFromPic(XmlElement el) {
    return el
        .findFirstElement('p:nvPicPr')
        ?.findFirstElement('p:cNvPr')
        ?.getAttribute('id');
  }

  String? _shapeIdFromGraphicFrame(XmlElement el) {
    return el
        .findFirstElement('p:nvGraphicFramePr')
        ?.findFirstElement('p:cNvPr')
        ?.getAttribute('id');
  }

  Offset _groupOffset(XmlElement grpSp) {
    final grpSpPr = grpSp.findFirstElement('p:grpSpPr');
    final xfrm = grpSpPr?.findFirstElement('a:xfrm');
    final off = xfrm?.findFirstElement('a:off');
    final chOff = xfrm?.findFirstElement('a:chOff');

    final offX = _emuToPx(off?.getAttribute('x'));
    final offY = _emuToPx(off?.getAttribute('y'));
    final chOffX = _emuToPx(chOff?.getAttribute('x'));
    final chOffY = _emuToPx(chOff?.getAttribute('y'));

    return Offset(offX - chOffX, offY - chOffY);
  }

  SlideShape? _parseSpElement(
    XmlElement el,
    SlideContext ctx, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final nvSpPr = el.findFirstElement('p:nvSpPr');
    final ph = nvSpPr?.findFirstElement('p:nvPr')?.findFirstElement('p:ph');

    final placeholderType = ph?.getAttribute('type');
    final placeholderIdx = ph?.getAttribute('idx');

    final shapeId =
        nvSpPr?.findFirstElement('p:cNvPr')?.getAttribute('id') ??
        'sp_${el.hashCode}';

    final spPr = el.findFirstElement('p:spPr');

    final bounds = _resolveShapeBounds(
      spPr: spPr,
      placeholderType: placeholderType,
      placeholderIdx: placeholderIdx,
      ctx: ctx,
      offsetX: offsetX,
      offsetY: offsetY,
    );

    final safeBounds =
        bounds ?? const ShapeBounds(x: 50, y: 50, width: 500, height: 100);

    final (rotation, flipH, flipV) = _parseTransform(spPr);
    final spStyle = el.findFirstElement('p:style');
    final fill =
        _parseFill(spPr, ctx.theme) ?? _parseFillFromStyle(spStyle, ctx.theme);
    final outline = _parseOutline(spPr, ctx.theme);

    final prstGeom = spPr?.findFirstElement('a:prstGeom');
    final geometry = prstGeom == null
        ? GeometryType.rect
        : GeometryType.fromOoxmlName(prstGeom.getAttribute('prst'));

    final txBody = el.findFirstElement('p:txBody');

    final isTextShape = txBody != null;

    // ─────────────────────────────────────────────
    // GEOMETRIC SHAPE (ВАЖНО: раньше это не существовало)
    // ─────────────────────────────────────────────
    if (!isTextShape) {
      return GeometricShape(
        shapeId: shapeId,
        bounds: safeBounds,
        rotationDegrees: rotation,
        flipH: flipH,
        flipV: flipV,
        fill: fill,
        outline: outline,
        geometry: geometry,
      );
    }

    // ─────────────────────────────────────────────
    // TEXT SHAPE
    // ─────────────────────────────────────────────
    final paragraphs = _parseTxBody(txBody!, ctx.theme);

    return TextShape(
      shapeId: shapeId,
      bounds: safeBounds,
      rotationDegrees: rotation,
      flipH: flipH,
      flipV: flipV,
      fill: fill,
      outline: outline,
      paragraphs: paragraphs,
      insets: _parseInsets(txBody),
      verticalAlignment: _parseVertAlign(txBody),
      geometry: geometry,
      wordWrap:
          txBody.findFirstElement('a:bodyPr')?.getAttribute('wrap') != 'none',
    );
  }

  ShapeBounds? _resolveShapeBounds({
    required XmlElement? spPr,
    required String? placeholderType,
    required String? placeholderIdx,
    required SlideContext ctx,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final direct = _parseBounds(spPr);
    if (direct != null) {
      return _translateBounds(direct, offsetX: offsetX, offsetY: offsetY);
    }

    final placeholderBounds = ctx.resolvePlaceholderBounds(
      placeholderType,
      placeholderIdx,
    );
    if (placeholderBounds != null) {
      return _translateBounds(
        placeholderBounds,
        offsetX: offsetX,
        offsetY: offsetY,
      );
    }

    return null;
  }

  ShapeBounds _translateBounds(
    ShapeBounds bounds, {
    required double offsetX,
    required double offsetY,
  }) {
    if (offsetX == 0 && offsetY == 0) return bounds;

    return ShapeBounds(
      x: bounds.x + offsetX,
      y: bounds.y + offsetY,
      width: bounds.width,
      height: bounds.height,
    );
  }

  SlideShape? _parsePicElement(
    XmlElement el,
    SlideContext ctx, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final nvPicPr = el.findFirstElement('p:nvPicPr');
    final shapeId =
        nvPicPr?.findFirstElement('p:cNvPr')?.getAttribute('id') ??
        'pic_${el.hashCode}';

    final spPr = el.findFirstElement('p:spPr');
    final bounds = _parseBounds(spPr, offsetX: offsetX, offsetY: offsetY);
    // print('PIC BOUNDS: $shapeId -> $bounds');
    if (bounds == null) return null;

    final (rotation, flipH, flipV) = _parseTransform(spPr);

    final blipFill = el.findFirstElement('p:blipFill');
    final rId = blipFill?.findFirstElement('a:blip')?.getAttribute('r:embed');
    final imageBytes = rId != null ? ctx.mediaByRId[rId] : null;
    if (imageBytes == null) return null;

    return ImageShape(
      shapeId: shapeId,
      bounds: bounds,
      rotationDegrees: rotation,
      flipH: flipH,
      flipV: flipV,
      imageBytes: imageBytes,
    );
  }

  SlideShape? _parseGraphicFrame(
    XmlElement el,
    SlideContext ctx, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final tbl = el.findFirstElement('a:tbl');
    if (tbl != null) {
      return _parseTable(el, tbl, ctx, offsetX: offsetX, offsetY: offsetY);
    }
    return null;
  }

  SlideShape? _parseTable(
    XmlElement graphicFrameEl,
    XmlElement tblEl,
    SlideContext ctx, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final xfrm = graphicFrameEl.findFirstElement('p:xfrm');
    final bounds = _parseBoundsFromXfrm(
      xfrm,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    if (bounds == null) return null;

    final paragraphs = <TextParagraph>[];
    for (final tr in tblEl.findAllElements('a:tr')) {
      for (final tc in tr.findAllElements('a:tc')) {
        final txBody = tc.findFirstElement('a:txBody');
        if (txBody != null) {
          paragraphs.addAll(_parseTxBody(txBody, ctx.theme));
        }
      }
    }

    return TextShape(
      shapeId: 'table_${graphicFrameEl.hashCode}',
      bounds: bounds,
      paragraphs: paragraphs,
      fill: const SolidShapeFill(Color(0xFFF5F5F5)),
      outline: ShapeOutline(color: Colors.grey, widthPx: 1),
      geometry: GeometryType.rect,
    );
  }

  // -------------------------------------------------------------------------
  // Bounds / transform helpers
  // -------------------------------------------------------------------------

  ShapeBounds? _parseBounds(
    XmlElement? spPr, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final xfrm = spPr?.findFirstElement('a:xfrm');
    return _parseBoundsFromXfrm(xfrm, offsetX: offsetX, offsetY: offsetY);
  }

  ShapeBounds? _parseBoundsFromXfrm(
    XmlElement? xfrm, {
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final off = xfrm?.findFirstElement('a:off');
    final ext = xfrm?.findFirstElement('a:ext');
    if (off == null || ext == null) return null;

    return ShapeBounds.fromEmu(
      xEmu: int.tryParse(off.getAttribute('x') ?? '0') ?? 0,
      yEmu: int.tryParse(off.getAttribute('y') ?? '0') ?? 0,
      widthEmu: int.tryParse(ext.getAttribute('cx') ?? '0') ?? 0,
      heightEmu: int.tryParse(ext.getAttribute('cy') ?? '0') ?? 0,
    ).let((b) => _translateBounds(b, offsetX: offsetX, offsetY: offsetY));
  }

  /// Returns (rotationDegrees, flipH, flipV).
  (double, bool, bool) _parseTransform(XmlElement? spPr) {
    final xfrm = spPr?.findFirstElement('a:xfrm');
    if (xfrm == null) return (0.0, false, false);

    final rotRaw = int.tryParse(xfrm.getAttribute('rot') ?? '0') ?? 0;
    final rotation = rotRaw / 60000.0;
    final flipH = xfrm.getAttribute('flipH') == '1';
    final flipV = xfrm.getAttribute('flipV') == '1';
    return (rotation, flipH, flipV);
  }

  // -------------------------------------------------------------------------
  // Fill parsing
  // -------------------------------------------------------------------------

  ShapeFill? _parseFill(XmlElement? spPr, PresentationTheme theme) {
    if (spPr == null) return null;

    final noFill = spPr.findFirstElement('a:noFill');
    if (noFill != null) return const NoShapeFill();

    final solidFill = spPr.findFirstElement('a:solidFill');
    if (solidFill != null) {
      final color = _resolveColor(solidFill, theme);
      return color != null ? SolidShapeFill(color) : null;
    }

    final gradFill = spPr.findFirstElement('a:gradFill');
    if (gradFill != null) return _parseGradientFill(gradFill, theme);

    return null;
  }

  ShapeFill? _parseFillFromStyle(XmlElement? style, PresentationTheme theme) {
    if (style == null) return null;
    final fillRef = style.findFirstElement('a:fillRef');
    if (fillRef == null) return null;

    // idx="0" означает "нет заливки"
    final idx = int.tryParse(fillRef.getAttribute('idx') ?? '1') ?? 1;
    if (idx == 0) return const NoShapeFill();

    final color = _resolveColor(fillRef, theme);
    if (color != null) return SolidShapeFill(color);
    return null;
  }

  GradientShapeFill? _parseGradientFill(
    XmlElement gradFill,
    PresentationTheme theme,
  ) {
    final gsLst = gradFill.findFirstElement('a:gsLst');
    if (gsLst == null) return null;

    final stops = <GradientStop>[];
    for (final gs in gsLst.findAllElements('a:gs')) {
      final pos = (int.tryParse(gs.getAttribute('pos') ?? '0') ?? 0) / 100000.0;
      final color = _resolveColor(gs, theme);
      if (color != null) {
        stops.add(GradientStop(color: color, position: pos));
      }
    }

    if (stops.isEmpty) return null;

    final lin = gradFill.findFirstElement('a:lin');
    final ang = (int.tryParse(lin?.getAttribute('ang') ?? '0') ?? 0) / 60000.0;

    return GradientShapeFill(stops: stops, angle: ang);
  }

  // -------------------------------------------------------------------------
  // Outline parsing
  // -------------------------------------------------------------------------

  ShapeOutline? _parseOutline(XmlElement? spPr, PresentationTheme theme) {
    final ln = spPr?.findFirstElement('a:ln');
    if (ln == null) return null;

    final noFill = ln.findFirstElement('a:noFill');
    if (noFill != null) return null;

    final solidFill = ln.findFirstElement('a:solidFill');
    final color = solidFill != null
        ? _resolveColor(solidFill, theme)
        : Colors.black;

    final wEmu = int.tryParse(ln.getAttribute('w') ?? '9525') ?? 9525;
    final widthPx = emuToLogicalPixels(wEmu);

    return ShapeOutline(
      color: color ?? Colors.black,
      widthPx: widthPx.clamp(0.5, 10.0),
    );
  }

  // -------------------------------------------------------------------------
  // Text body parsing
  // -------------------------------------------------------------------------

  List<TextParagraph> _parseTxBody(XmlElement txBody, PresentationTheme theme) {
    final defaultRunFmt = _parseDefRPr(txBody, theme);

    final paragraphs = <TextParagraph>[];

    for (final para in txBody.findAllElements('a:p')) {
      final pFmt = _parseParagraphFormat(para);
      final runs = <TextRun>[];

      for (final child in para.childElements) {
        if (child.localName == 'r') {
          final rPr = child.findFirstElement('a:rPr');
          final fmt = _parseRunFormat(rPr, theme, defaultRunFmt);
          final t = child.findFirstElement('a:t')?.innerText ?? '';
          runs.add(TextRun(text: t, format: fmt));
        } else if (child.localName == 'fld') {
          final t = child.findFirstElement('a:t')?.innerText ?? '';
          runs.add(TextRun(text: t, format: defaultRunFmt));
        } else if (child.localName == 'br') {
          runs.add(const TextRun(text: '\n'));
        }
      }

      paragraphs.add(TextParagraph(runs: runs, format: pFmt));
    }

    return paragraphs;
  }

  TextRunFormat _parseDefRPr(XmlElement txBody, PresentationTheme theme) {
    final lstStyle = txBody.findFirstElement('a:lstStyle');
    final defPPr = lstStyle?.findFirstElement('a:defPPr');
    final defRPr = defPPr?.findFirstElement('a:defRPr');
    return _parseRunFormat(defRPr, theme, const TextRunFormat());
  }

  ParagraphFormat _parseParagraphFormat(XmlElement para) {
    final pPr = para.findFirstElement('a:pPr');
    if (pPr == null) return const ParagraphFormat();

    final algn = pPr.getAttribute('algn');
    TextAlign? alignment;
    switch (algn) {
      case 'l':
        alignment = TextAlign.left;
        break;
      case 'ctr':
        alignment = TextAlign.center;
        break;
      case 'r':
        alignment = TextAlign.right;
        break;
      case 'just':
      case 'dist':
        alignment = TextAlign.justify;
        break;
    }

    final spcBef = pPr.findFirstElement('a:spcBef');
    final spcAft = pPr.findFirstElement('a:spcAft');
    final lnSpc = pPr.findFirstElement('a:lnSpc');

    final spaceBefore = _parseSpacing(spcBef);
    final spaceAfter = _parseSpacing(spcAft);
    final lineSpacing = _parseSpacingMultiplier(lnSpc);

    final marL = int.tryParse(pPr.getAttribute('marL') ?? '');
    final indent = int.tryParse(pPr.getAttribute('indent') ?? '');

    return ParagraphFormat(
      alignment: alignment,
      spaceBefore: spaceBefore,
      spaceAfter: spaceAfter,
      lineSpacing: lineSpacing,
      marginLeft: marL != null ? emuToLogicalPixels(marL) : null,
      indent: indent != null ? emuToLogicalPixels(indent) : null,
    );
  }

  double? _parseSpacing(XmlElement? spcEl) {
    if (spcEl == null) return null;
    final spcPts = spcEl.findFirstElement('a:spcPts');
    if (spcPts != null) {
      final val = int.tryParse(spcPts.getAttribute('val') ?? '');
      if (val != null) return ptToLogicalPixels(val / 100.0);
    }
    return null;
  }

  double? _parseSpacingMultiplier(XmlElement? lnSpc) {
    if (lnSpc == null) return null;
    final spcPct = lnSpc.findFirstElement('a:spcPct');
    if (spcPct != null) {
      final val = int.tryParse(spcPct.getAttribute('val') ?? '');
      if (val != null) return val / 100000.0;
    }
    return null;
  }

  TextRunFormat _parseRunFormat(
    XmlElement? rPr,
    PresentationTheme theme,
    TextRunFormat parent,
  ) {
    if (rPr == null) return parent;

    final szRaw = int.tryParse(rPr.getAttribute('sz') ?? '');
    final fontSizePx = szRaw != null
        ? ptToLogicalPixels(szRaw / 100.0)
        : parent.fontSizePx;

    final bold = rPr.getAttribute('b') == '1'
        ? true
        : rPr.getAttribute('b') == '0'
        ? false
        : parent.bold;

    final italic = rPr.getAttribute('i') == '1'
        ? true
        : rPr.getAttribute('i') == '0'
        ? false
        : parent.italic;

    final underline =
        (rPr.getAttribute('u') ?? '') != 'none' &&
            (rPr.getAttribute('u') ?? '').isNotEmpty
        ? true
        : parent.underline;

    final strike = rPr.getAttribute('strike') == 'sngStrike'
        ? true
        : rPr.getAttribute('strike') == 'noStrike'
        ? false
        : parent.strikethrough;

    final solidFill = rPr.findFirstElement('a:solidFill');
    final color = solidFill != null
        ? _resolveColor(solidFill, theme) ?? parent.color
        : parent.color;

    final latin = rPr.findFirstElement('a:latin');
    String? fontFamily = latin?.getAttribute('typeface') ?? parent.fontFamily;

    if (fontFamily == '+mj-lt') fontFamily = theme.majorFont ?? fontFamily;
    if (fontFamily == '+mn-lt') fontFamily = theme.minorFont ?? fontFamily;

    final spcRaw = int.tryParse(rPr.getAttribute('spc') ?? '');
    final charSpacing = spcRaw != null
        ? ptToLogicalPixels(spcRaw / 100.0)
        : parent.charSpacingPx;

    return TextRunFormat(
      fontFamily: fontFamily,
      fontSizePx: fontSizePx,
      color: color,
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strike,
      charSpacingPx: charSpacing,
    );
  }

  // -------------------------------------------------------------------------
  // Text insets and vertical alignment
  // -------------------------------------------------------------------------

  TextInsets _parseInsets(XmlElement? txBody) {
    final bodyPr = txBody?.findFirstElement('a:bodyPr');
    if (bodyPr == null) return const TextInsets();

    const defaultEmu = 91440;

    return TextInsets.fromEmu(
      leftEmu: int.tryParse(bodyPr.getAttribute('lIns') ?? '') ?? defaultEmu,
      topEmu: int.tryParse(bodyPr.getAttribute('tIns') ?? '') ?? 45720,
      rightEmu: int.tryParse(bodyPr.getAttribute('rIns') ?? '') ?? defaultEmu,
      bottomEmu: int.tryParse(bodyPr.getAttribute('bIns') ?? '') ?? 45720,
    );
  }

  VerticalAlignment _parseVertAlign(XmlElement? txBody) {
    final bodyPr = txBody?.findFirstElement('a:bodyPr');
    switch (bodyPr?.getAttribute('anchor')) {
      case 'ctr':
        return VerticalAlignment.middle;
      case 'b':
        return VerticalAlignment.bottom;
      default:
        return VerticalAlignment.top;
    }
  }

  // -------------------------------------------------------------------------
  // Colour resolution
  // -------------------------------------------------------------------------

  Color? _resolveColor(XmlElement container, PresentationTheme theme) {
    final srgb = container.findFirstElement('a:srgbClr');
    if (srgb != null) {
      final val = srgb.getAttribute('val');
      var color = _hexToColor(val);
      color = _applyColorMods(srgb, color);
      return color;
    }

    final schemeClr = container.findFirstElement('a:schemeClr');
    if (schemeClr != null) {
      final val = schemeClr.getAttribute('val') ?? '';
      var color = theme.resolveSchemeColor(val);
      if (color == null) {
        color = _namedColor(val);
      }
      color = _applyColorMods(schemeClr, color);
      return color;
    }

    final prstClr = container.findFirstElement('a:prstClr');
    if (prstClr != null) {
      return _namedColor(prstClr.getAttribute('val'));
    }

    final sysClr = container.findFirstElement('a:sysClr');
    if (sysClr != null) {
      return _hexToColor(sysClr.getAttribute('lastClr'));
    }

    return null;
  }

  Color? _applyColorMods(XmlElement colorEl, Color? base) {
    if (base == null) return null;

    final alphaEl = colorEl.findFirstElement('a:alpha');
    if (alphaEl != null) {
      final a =
          (int.tryParse(alphaEl.getAttribute('val') ?? '') ?? 100000) /
          100000.0;
      base = base.withOpacity(a);
    }

    final lumMod =
        int.tryParse(
          colorEl.findFirstElement('a:lumMod')?.getAttribute('val') ?? '',
        ) ??
        100000;
    final lumOff =
        int.tryParse(
          colorEl.findFirstElement('a:lumOff')?.getAttribute('val') ?? '',
        ) ??
        0;

    if (lumMod != 100000 || lumOff != 0) {
      final hsl = _rgbToHsl(base);
      double l = hsl[2] * (lumMod / 100000.0) + (lumOff / 100000.0);
      l = l.clamp(0.0, 1.0);
      base = _hslToRgb(hsl[0], hsl[1], l, base.opacity);
    }

    final shadeEl = colorEl.findFirstElement('a:shade');
    if (shadeEl != null) {
      final f =
          (int.tryParse(shadeEl.getAttribute('val') ?? '') ?? 100000) /
          100000.0;
      base = Color.fromARGB(
        base.alpha,
        (base.red * f).round().clamp(0, 255),
        (base.green * f).round().clamp(0, 255),
        (base.blue * f).round().clamp(0, 255),
      );
    }

    final tintEl = colorEl.findFirstElement('a:tint');
    if (tintEl != null) {
      final f =
          (int.tryParse(tintEl.getAttribute('val') ?? '') ?? 100000) / 100000.0;
      base = Color.fromARGB(
        base.alpha,
        (base.red + (255 - base.red) * (1.0 - f)).round().clamp(0, 255),
        (base.green + (255 - base.green) * (1.0 - f)).round().clamp(0, 255),
        (base.blue + (255 - base.blue) * (1.0 - f)).round().clamp(0, 255),
      );
    }

    return base;
  }

  // -------------------------------------------------------------------------
  // Colour utilities
  // -------------------------------------------------------------------------

  Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    return null;
  }

  Color? _namedColor(String? name) {
    if (name == null) return null;
    switch (name.toLowerCase()) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'yellow':
        return Colors.yellow;
      case 'cyan':
        return Colors.cyan;
      case 'magenta':
        return Colors.purple;
      case 'orange':
        return Colors.orange;
      default:
        return null;
    }
  }

  List<double> _rgbToHsl(Color c) {
    final r = c.red / 255.0, g = c.green / 255.0, b = c.blue / 255.0;
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    final l = (max + min) / 2.0;
    if (max == min) return [0, 0, l];
    final d = max - min;
    final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    double h;
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return [h / 6.0, s, l];
  }

  Color _hslToRgb(double h, double s, double l, double opacity) {
    if (s == 0) {
      final v = (l * 255).round().clamp(0, 255);
      return Color.fromARGB((opacity * 255).round(), v, v, v);
    }

    double hue2rgb(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    final r = hue2rgb(p, q, h + 1 / 3);
    final g = hue2rgb(p, q, h);
    final b = hue2rgb(p, q, h - 1 / 3);

    return Color.fromARGB(
      (opacity * 255).round().clamp(0, 255),
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  double _emuToPx(String? val) {
    return emuToLogicalPixels(int.tryParse(val ?? '0') ?? 0);
  }
}

// Tiny helper for one-off transforms.
extension _Let<T> on T {
  R let<R>(R Function(T value) fn) => fn(this);
}
