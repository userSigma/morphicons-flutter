/// Absolute SVG segment after resolving relative and shorthand commands.
class RawSeg {
  const RawSeg(this.tag, this.values);

  final String tag;
  final List<double> values;
}

class RawSubpath {
  RawSubpath(this.x0, this.y0);

  final double x0;
  final double y0;
  final List<RawSeg> segs = [];
  bool closed = false;
}

/// Parses all SVG path commands, including repetitions and compact arc flags.
///
/// Every successful scan consumes input; malformed data throws [FormatException]
/// instead of leaving the command-repetition loop stalled.
List<RawSubpath> parsePath(String d) => _PathParser(d).parse();

class _PathParser {
  _PathParser(this.d);

  static const _commands = 'MmLlHhVvCcSsQqTtAaZz';
  final String d;
  final List<RawSubpath> subs = [];
  int i = 0;
  double cx = 0;
  double cy = 0;
  double sx = 0;
  double sy = 0;
  double px = 0;
  double py = 0;
  String cmd = '';
  String prev = '';
  bool started = false;
  bool relative = false;
  RawSubpath? cur;

  Never error(String message) =>
      throw FormatException('morphicons: $message at d[$i]', d, i);

  bool digit(int c) => c >= 48 && c <= 57;

  void skip() {
    while (i < d.length) {
      final c = d.codeUnitAt(i);
      if (c == 32 || c == 9 || c == 10 || c == 13 || c == 12 || c == 44) {
        i++;
      } else {
        break;
      }
    }
  }

  double number() {
    skip();
    final start = i;
    if (i < d.length && (d[i] == '+' || d[i] == '-')) i++;
    var digits = false;
    while (i < d.length && digit(d.codeUnitAt(i))) {
      i++;
      digits = true;
    }
    if (i < d.length && d[i] == '.') {
      i++;
      while (i < d.length && digit(d.codeUnitAt(i))) {
        i++;
        digits = true;
      }
    }
    if (!digits) error('expected number');
    if (i < d.length && (d[i] == 'e' || d[i] == 'E')) {
      final save = i++;
      if (i < d.length && (d[i] == '+' || d[i] == '-')) i++;
      var exponentDigits = false;
      while (i < d.length && digit(d.codeUnitAt(i))) {
        i++;
        exponentDigits = true;
      }
      if (!exponentDigits) i = save;
    }
    final value = double.parse(d.substring(start, i));
    if (!value.isFinite) error('expected finite number');
    return value;
  }

  double flag() {
    skip();
    if (i < d.length && (d[i] == '0' || d[i] == '1')) {
      return d[i++] == '1' ? 1 : 0;
    }
    return error('expected arc flag (0|1)');
  }

  double nextX() {
    final value = number() + (relative ? cx : 0);
    if (!value.isFinite) error('non-finite coordinate');
    return value;
  }

  double nextY() {
    final value = number() + (relative ? cy : 0);
    if (!value.isFinite) error('non-finite coordinate');
    return value;
  }

  RawSubpath open() {
    if (!started) error('path must start with M/m');
    if (cur == null) {
      cur = RawSubpath(cx, cy);
      subs.add(cur!);
    }
    return cur!;
  }

  void add(String tag, List<double> values) {
    if (values.any((v) => !v.isFinite)) error('non-finite coordinate');
    open().segs.add(RawSeg(tag, values));
  }

  List<RawSubpath> parse() {
    while (true) {
      skip();
      if (i >= d.length) break;
      final before = i;
      final ch = d[i];
      if (_commands.contains(ch)) {
        cmd = ch;
        i++;
      } else if (cmd.isEmpty) {
        error('path must start with M/m');
      } else if (cmd == 'M') {
        cmd = 'L';
      } else if (cmd == 'm') {
        cmd = 'l';
      } else if (cmd == 'Z' || cmd == 'z') {
        error('stray data after Z');
      }
      relative = cmd == cmd.toLowerCase();
      switch (cmd.toUpperCase()) {
        case 'M':
          final x = nextX();
          final y = nextY();
          started = true;
          cx = sx = x;
          cy = sy = y;
          cur = RawSubpath(x, y);
          subs.add(cur!);
          prev = '';
        case 'L':
          final x = nextX();
          final y = nextY();
          add('L', [x, y]);
          cx = x;
          cy = y;
          prev = '';
        case 'H':
          final x = nextX();
          add('L', [x, cy]);
          cx = x;
          prev = '';
        case 'V':
          final y = nextY();
          add('L', [cx, y]);
          cy = y;
          prev = '';
        case 'C':
        case 'S':
          final full = cmd.toUpperCase() == 'C';
          final x1 = full ? nextX() : (prev == 'C' ? 2 * cx - px : cx);
          final y1 = full ? nextY() : (prev == 'C' ? 2 * cy - py : cy);
          final x2 = nextX();
          final y2 = nextY();
          final x = nextX();
          final y = nextY();
          add('C', [x1, y1, x2, y2, x, y]);
          px = x2;
          py = y2;
          cx = x;
          cy = y;
          prev = 'C';
        case 'Q':
        case 'T':
          final full = cmd.toUpperCase() == 'Q';
          final x1 = full ? nextX() : (prev == 'Q' ? 2 * cx - px : cx);
          final y1 = full ? nextY() : (prev == 'Q' ? 2 * cy - py : cy);
          final x = nextX();
          final y = nextY();
          add('Q', [x1, y1, x, y]);
          px = x1;
          py = y1;
          cx = x;
          cy = y;
          prev = 'Q';
        case 'A':
          final rx = number();
          final ry = number();
          final rotation = number();
          final large = flag();
          final sweep = flag();
          final x = nextX();
          final y = nextY();
          add('A', [rx, ry, rotation, large, sweep, x, y]);
          cx = x;
          cy = y;
          prev = '';
        case 'Z':
          if (!started) error('path must start with M/m');
          cur?.closed = true;
          cur = null;
          cx = sx;
          cy = sy;
          prev = '';
        default:
          error('unsupported command "$cmd"');
      }
      if (i <= before) error('expected number');
    }
    return subs.where((s) => s.segs.isNotEmpty).toList();
  }
}
