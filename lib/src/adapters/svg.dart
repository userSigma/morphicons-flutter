import 'dart:math' as math;

import '../core/normalize.dart';
import '../core/serialize.dart';
import '../core/types.dart';

// This scanner intentionally handles icon markup, not arbitrary SVG documents.
// In particular, CSS selectors and referenced geometry cannot be resolved here.
final _svgTag = RegExp(
  r'''<(\/?)([a-zA-Z][\w:-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>''',
);
final _svgAttr =
    RegExp(r"""([\w:-]+)\s*=\s*"([^"]*)"|([\w:-]+)\s*=\s*'([^']*)'""");
final _svgStyle = RegExp(r'<style\b', caseSensitive: false);
final _comment = RegExp(r'<!--[\s\S]*?-->');
final _transform = RegExp(r'(\w+)\s*\(([^)]*)\)');
final _separators = RegExp(r'[\s,]+');
final _floatPrefix = RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');

const _geometry = {
  'path',
  'line',
  'circle',
  'ellipse',
  'rect',
  'polyline',
  'polygon'
};
const _groups = {'svg', 'g', 'a'};
const _skip = {'title', 'desc', 'defs', 'mask', 'clippath', 'symbol'};
const _paintKeys = {
  'fill',
  'stroke',
  'stroke-width',
  'fill-rule',
  'opacity',
  'fill-opacity',
  'visibility',
  'display',
};
const _identity = <double>[1, 0, 0, 1, 0, 0];

// SVG's six affine coefficients: a b c d e f.
typedef _Mat = List<double>;

class _Context {
  const _Context(this.paint, this.matrix);

  final Map<String, String> paint;
  final _Mat? matrix;
}

class _Found {
  const _Found(this.tag, this.attrs, this.paint, this.matrix);

  final String tag;
  final IconNodeAttrs attrs;
  final Map<String, String> paint;
  final _Mat? matrix;
}

IconNodeAttrs _readAttrs(String raw) {
  final attrs = <String, Object?>{};
  for (final match in _svgAttr.allMatches(raw)) {
    attrs[(match[1] ?? match[3])!] = match[2] ?? match[4] ?? '';
  }
  return attrs;
}

Map<String, String> _paintOf(Map<String, String> parent, IconNodeAttrs attrs) {
  final out = Map<String, String>.of(parent);
  for (final key in _paintKeys) {
    if (attrs[key] != null) out[key] = attrs[key].toString();
  }
  // Inline declarations override presentation attributes, just as in SVG.
  for (final declaration in (attrs['style'] ?? '').toString().split(';')) {
    final colon = declaration.indexOf(':');
    if (colon <= 0) continue;
    final key = declaration.substring(0, colon).trim().toLowerCase();
    if (_paintKeys.contains(key)) {
      out[key] = declaration.substring(colon + 1).trim();
    }
  }
  return out;
}

_Mat _mul(_Mat m, _Mat n) => [
      m[0] * n[0] + m[2] * n[1],
      m[1] * n[0] + m[3] * n[1],
      m[0] * n[2] + m[2] * n[3],
      m[1] * n[2] + m[3] * n[3],
      m[0] * n[4] + m[2] * n[5] + m[4],
      m[1] * n[4] + m[3] * n[5] + m[5],
    ];

_Mat? _parseTransform(Object? value) {
  final source = (value ?? '').toString().trim();
  if (source.isEmpty) return null;
  var matrix = _identity;
  for (final match in _transform.allMatches(source)) {
    final name = match[1]!;
    final raw = match[2]!.trim();
    final args = raw.isEmpty
        ? <double>[]
        : raw
            .split(_separators)
            .map((s) => double.tryParse(s) ?? double.nan)
            .toList();
    double arg(int index, [double fallback = double.nan]) =>
        index < args.length ? args[index] : fallback;
    final radians = arg(0) * math.pi / 180;
    final _Mat next;
    switch (name) {
      case 'matrix':
        next = [for (var i = 0; i < 6; i++) arg(i)];
      case 'translate':
        next = [1, 0, 0, 1, arg(0), arg(1, 0)];
      case 'scale':
        next = [arg(0), 0, 0, arg(1, arg(0)), 0, 0];
      case 'rotate':
        final cosine = math.cos(radians);
        final sine = math.sin(radians);
        final cx = arg(1, 0);
        final cy = arg(2, 0);
        next = [
          cosine,
          sine,
          -sine,
          cosine,
          cx - cosine * cx + sine * cy,
          cy - sine * cx - cosine * cy
        ];
      case 'skewX':
        next = [1, 0, math.tan(radians), 1, 0, 0];
      case 'skewY':
        next = [1, math.tan(radians), 0, 1, 0, 0];
      default:
        throw FormatException('morphicons: unsupported transform "$name"');
    }
    if (next.any((v) => !v.isFinite)) {
      throw FormatException('morphicons: invalid transform "$source"');
    }
    matrix = _mul(matrix, next);
  }
  return matrix;
}

String _bake(String tag, IconNodeAttrs attrs, _Mat matrix) {
  final paths = iconToCubics([IconNode(tag, attrs)]);
  for (final path in paths) {
    final pts = path.pts;
    for (var i = 0; i < pts.length; i += 2) {
      final x = pts[i];
      final y = pts[i + 1];
      pts[i] = matrix[0] * x + matrix[2] * y + matrix[4];
      pts[i + 1] = matrix[1] * x + matrix[3] * y + matrix[5];
    }
  }
  return cubicsToPathD(paths);
}

String _stripComments(String markup) {
  var out = markup;
  while (true) {
    final previous = out;
    out = out.replaceAll(_comment, '');
    if (out == previous) break;
  }
  final open = out.indexOf('<!--');
  return open < 0 ? out : out.substring(0, open);
}

bool _painted(String? value) =>
    value != null && value.trim().toLowerCase() != 'none';

String _scaledWidth(String value, double scale) {
  // SVG lengths commonly carry a px suffix; match Number.parseFloat in TS.
  final prefix = _floatPrefix.stringMatch(value.trimLeft());
  final width = (prefix == null ? double.nan : double.parse(prefix)) * scale;
  final text = width.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Converts an Iconify body, a complete SVG, or bare geometry markup to an icon.
///
/// Pure Dart and independent of Flutter, XML packages and the DOM. Parses once
/// into the core's [IconInput] contract: a path-data string or [List<IconNode>].
/// Supported shapes are path, line, circle, ellipse, rect, polyline and polygon.
/// Paint inherits through svg/g/a wrappers and inline style wins over attributes.
/// Transforms are baked into cubic coordinates; a viewBox fits onto the 24 grid.
///
/// Stroke-only icons retain their original node attributes (or return a fitted
/// path string). If any element is filled, all elements become paths carrying
/// resolved fill/stroke, stroke-width, fill-rule, opacity and fill-opacity.
/// Non-rendered containers and hidden geometry are skipped; unsupported elements
/// and empty markup throw [FormatException]. CSS selector styles are unsupported.
IconInput svgToIcon(String markup) {
  if (!markup.trimLeft().startsWith('<')) {
    throw const FormatException(
      'morphicons: svgToIcon expects SVG markup — a d string or IconNode is already an IconInput',
    );
  }
  final clean = _stripComments(markup);
  // Detect CSS before skipping defs, where exporters usually put their styles.
  if (_svgStyle.hasMatch(clean)) {
    throw const FormatException('morphicons: unsupported SVG element <style>');
  }
  final found = <_Found>[];
  final stack = <_Context>[const _Context({}, null)];
  String? viewBox;
  String? skippedTag;
  var skippedDepth = 0;
  for (final match in _svgTag.allMatches(clean)) {
    final closing = match[1]!.isNotEmpty;
    final tag = match[2]!.toLowerCase();
    final selfClosing = match[4]!.isNotEmpty;
    // Skip entire non-rendered subtrees, including nested containers of one kind.
    if (skippedTag != null) {
      if (tag == skippedTag) {
        if (closing) {
          if (--skippedDepth == 0) skippedTag = null;
        } else if (!selfClosing) {
          skippedDepth++;
        }
      }
      continue;
    }
    if (closing) {
      if (_groups.contains(tag) && stack.length > 1) stack.removeLast();
      continue;
    }
    if (_skip.contains(tag)) {
      if (!selfClosing) {
        skippedTag = tag;
        skippedDepth = 1;
      }
      continue;
    }
    final attrs = _readAttrs(match[3]!);
    if (tag == 'svg' && viewBox == null) {
      for (final entry in attrs.entries) {
        if (entry.key.toLowerCase() == 'viewbox') {
          viewBox = entry.value.toString();
          break;
        }
      }
    }
    final top = stack.last;
    final own = _parseTransform(attrs['transform']);
    final matrix = own == null
        ? top.matrix
        : top.matrix == null
            ? own
            : _mul(top.matrix!, own);
    final paint = _paintOf(top.paint, attrs);
    // display:none is not an inherited CSS value but hides the whole subtree.
    if (top.paint['display'] == 'none') paint['display'] = 'none';
    if (_groups.contains(tag)) {
      if (!selfClosing) stack.add(_Context(paint, matrix));
      continue;
    }
    if (!_geometry.contains(tag)) {
      throw FormatException('morphicons: unsupported SVG element <$tag>');
    }
    if (paint['display'] == 'none' ||
        paint['visibility'] == 'hidden' ||
        paint['visibility'] == 'collapse') {
      continue;
    }
    found.add(_Found(tag, attrs, paint, matrix));
  }
  if (found.isEmpty) {
    throw const FormatException('morphicons: no morphable geometry in SVG');
  }

  // SVG defaults to black fill, except bare stroke declarations denote a stroke
  // icon in common icon packs that omit an explicit fill="none".
  final fills = [
    for (final node in found)
      node.paint.containsKey('fill')
          ? _painted(node.paint['fill'])
          : !_painted(node.paint['stroke'])
  ];
  if (!fills.any((fill) => fill)) {
    final nodes = <IconNode>[];
    for (final node in found) {
      if (node.matrix == null) {
        nodes.add(IconNode(node.tag, node.attrs));
      } else {
        final attrs = Map<String, Object?>.of(node.attrs)..remove('transform');
        attrs['d'] = _bake(node.tag, node.attrs, node.matrix!);
        nodes.add(IconNode('path', attrs));
      }
    }
    return viewBox == null ? nodes : fitIcon(nodes, viewBox);
  }

  var scale = 1.0;
  if (viewBox != null) {
    // Validate using the shared fitter before reading dimensions for paint.
    // Empty geometry avoids doing the same lowering twice.
    fitIcon(const <IconNode>[], viewBox);
    final dimensions =
        viewBox.trim().split(_separators).map(double.parse).toList();
    scale = math.min(24 / dimensions[2], 24 / dimensions[3]);
  }
  return <IconNode>[
    for (var i = 0; i < found.length; i++)
      _filledNode(found[i], fills[i], viewBox, scale),
  ];
}

IconNode _filledNode(_Found node, bool filled, String? viewBox, double scale) {
  final d = node.matrix != null
      ? _bake(node.tag, node.attrs, node.matrix!)
      : node.tag == 'path'
          ? (node.attrs['d'] ?? '').toString()
          : _bake(node.tag, node.attrs, _identity);
  final paint = node.paint;
  final attrs = <String, Object?>{
    'd': viewBox == null ? d : fitIcon(d, viewBox),
    'fill': filled ? 'currentColor' : 'none',
    'stroke': _painted(paint['stroke']) ? 'currentColor' : 'none',
  };
  if (_painted(paint['stroke'])) {
    attrs['stroke-width'] = _scaledWidth(paint['stroke-width'] ?? '1', scale);
  }
  for (final key in ['fill-rule', 'opacity', 'fill-opacity']) {
    final value = paint[key];
    if (value != null && value.isNotEmpty) attrs[key] = value;
  }
  return IconNode('path', attrs);
}
