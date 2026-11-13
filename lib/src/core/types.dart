import 'dart:typed_data';

/// A raw SVG path-data string or a [List<IconNode>].
///
/// Dart has no union typedef; core entry points validate this union at runtime.
typedef IconInput = Object;

typedef IconNodeAttrs = Map<String, Object?>;

/// One SVG primitive. A list of nodes is a complete icon.
class IconNode {
  const IconNode(this.tag, this.attrs);

  final String tag;
  final IconNodeAttrs attrs;
}

/// Cubic chain packed as [p0, c1, c2, p1, c1', c2', p2, ...].
class CubicPath {
  CubicPath(this.pts, {required this.closed});

  final Float64List pts;
  final bool closed;
}

/// Arc-length samples and intrinsic topology, shared by the planning pipeline.
class Sampled {
  Sampled(this.pts, {required this.closed, this.hole = false});

  final Float64List pts;
  final bool closed;
  final bool hole;
}

/// Number of segments in a well-formed cubic chain (a lone point has zero).
int segCount(CubicPath path) {
  final length = path.pts.length;
  if (length < 2 || (length - 2) % 6 != 0) {
    throw ArgumentError('morphicons: invalid cubic point count $length');
  }
  return (length - 2) ~/ 6;
}
