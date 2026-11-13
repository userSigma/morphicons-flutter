import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/adapters.dart';
import 'package:morphicons/src/core/normalize.dart';
import 'package:morphicons/src/core/serialize.dart';
import 'package:morphicons/src/core/types.dart';

const menu = '<path fill="none" stroke="currentColor" stroke-linecap="round" '
    'stroke-linejoin="round" stroke-width="2" d="M4 5h16M4 12h16M4 19h16"/>';
const cross =
    '<path fill="none" stroke="currentColor" d="M18 6L6 18M6 6l12 12"/>';
const search = '<g fill="none" stroke="currentColor" stroke-width="2">'
    '<path d="m21 21l-4.34-4.34"/><circle cx="11" cy="11" r="8"/></g>';
const pause = '<g fill="none" stroke="currentColor" stroke-width="2">'
    '<rect width="5" height="18" x="14" y="3" rx="1"/>'
    '<rect width="5" height="18" x="5" y="3" rx="1"/></g>';

String canon(IconInput icon) => cubicsToPathD(iconToCubics(icon));
List<IconNode> nodes(IconInput icon) => icon as List<IconNode>;

void expectGeometry(IconInput actual, IconInput expected) {
  final a = iconToCubics(actual);
  final b = iconToCubics(expected);
  expect(a, hasLength(b.length));
  for (var i = 0; i < a.length; i++) {
    expect(a[i].closed, b[i].closed);
    expect(a[i].pts, hasLength(b[i].pts.length));
    for (var j = 0; j < a[i].pts.length; j++) {
      // Baking serializes to four decimals before fitting, as in the TS port.
      expect(a[i].pts[j], closeTo(b[i].pts[j], 0.00011));
    }
  }
}

Matcher failsWith(String message) => throwsA(
      predicate<Object>((error) => error.toString().contains(message)),
    );

void main() {
  group('svgToIcon core contract', () {
    test('Iconify bodies lower to finite cubic paths', () {
      for (final body in [menu, cross, search, pause]) {
        final icon = svgToIcon(body);
        final paths = iconToCubics(icon);
        expect(paths, isNotEmpty);
        expect(
            paths.expand((path) => path.pts).every((p) => p.isFinite), isTrue);
        expect(canon(icon), startsWith('M'));
      }
    });

    test('untransformed stroke geometry and attributes stay verbatim', () {
      final node = nodes(svgToIcon(menu)).single;
      expect(node.tag, 'path');
      expect(node.attrs, {
        'fill': 'none',
        'stroke': 'currentColor',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
        'stroke-width': '2',
        'd': 'M4 5h16M4 12h16M4 19h16',
      });
      final rects = nodes(svgToIcon(pause));
      expect(rects.map((node) => node.tag), ['rect', 'rect']);
      expect(rects.first.attrs['rx'], '1');
    });

    test('tag case and single quoted attributes are accepted', () {
      final node = nodes(svgToIcon("<PATH stroke='currentColor' d='M0 0h4'/>"));
      expect(node.single.tag, 'path');
      expect(node.single.attrs['d'], 'M0 0h4');
    });

    test('greater-than signs inside quoted attributes do not end a tag', () {
      final node = nodes(svgToIcon('<path data-label="a > b" '
              'fill="none" d="M0 0h4"/>'))
          .single;
      expect(node.attrs['data-label'], 'a > b');
    });

    test('scanner state does not leak across calls', () {
      expect(canon(svgToIcon(menu)), canon(svgToIcon(menu)));
      expect(nodes(svgToIcon(cross)), hasLength(1));
    });

    test('raw path data is not markup', () {
      expect(() => svgToIcon('M4 5h16'), failsWith('expects SVG markup'));
      expect(() => svgToIcon(''), failsWith('expects SVG markup'));
    });
  });

  group('viewBox fitting', () {
    const line = '<path stroke="currentColor" fill="none" d="M0 24h48"/>';

    test('off-grid stroke markup returns fitted path data', () {
      final icon = svgToIcon('<svg viewBox="0 0 48 48">$line</svg>');
      expect(icon, isA<String>());
      expect(canon(icon), canon('M0 12h24'));
    });

    test('bare markup is not rescaled', () {
      expect(canon(svgToIcon(line)), canon('M0 24h48'));
    });

    test('24 viewBox is identity', () {
      expect(canon(svgToIcon('<svg viewBox="0 0 24 24">$menu</svg>')),
          canon(svgToIcon(menu)));
    });

    test('nonzero origins translate onto the grid', () {
      expect(
        canon(svgToIcon('<svg viewBox="4 4 40 40">'
            '<path fill="none" d="M4 24h40"/></svg>')),
        canon('M0 12h24'),
      );
    });

    test('non-square viewBox letterboxes with xMidYMid meet', () {
      expect(
        canon(svgToIcon('<svg viewBox="0,0,48,24">'
            '<path fill="none" d="M0 0L48 24"/></svg>')),
        canon('M0 6L24 18'),
      );
    });

    test('viewBox is read after comments and without attribute-order limits',
        () {
      expect(
        canon(svgToIcon('<!-- <svg viewBox="0 0 1 1"> -->'
            "<SVG data-label='a > b' VIEWBOX='0 0 48 48'>$line</SVG>")),
        canon('M0 12h24'),
      );
    });

    test('invalid viewBox is reported by the shared fitter', () {
      for (final vb in ['0 0 0 24', '0 0 24', '0 0 NaN 24']) {
        expect(() => svgToIcon('<svg viewBox="$vb">$line</svg>'),
            failsWith('viewBox'));
      }
    });
  });

  group('resolved fill metadata', () {
    test('implicit fill and explicit stroke none are filled', () {
      for (final stroke in ['', 'stroke="none"']) {
        final node =
            nodes(svgToIcon('<path $stroke d="M4 4h16v16H4z"/>')).single;
        expect(node.tag, 'path');
        expect(node.attrs['fill'], 'currentColor');
        expect(node.attrs['stroke'], 'none');
        expect(iconToCubics([node]).single.closed, isTrue);
      }
    });

    test('paint inherits through svg, group and link wrappers', () {
      final icon =
          svgToIcon('<svg fill="red" fill-rule="evenodd" opacity="0.7">'
              '<g stroke="blue" stroke-width="4"><a fill-opacity="0.4">'
              '<rect width="12" height="8"/></a></g></svg>');
      expect(nodes(icon).single.attrs, containsPair('fill', 'currentColor'));
      expect(nodes(icon).single.attrs, containsPair('stroke', 'currentColor'));
      expect(nodes(icon).single.attrs, containsPair('stroke-width', '4'));
      expect(nodes(icon).single.attrs, containsPair('fill-rule', 'evenodd'));
      expect(nodes(icon).single.attrs, containsPair('opacity', '0.7'));
      expect(nodes(icon).single.attrs, containsPair('fill-opacity', '0.4'));
    });

    test(
        'inline style overrides attributes and child paint overrides inheritance',
        () {
      final icon = svgToIcon('<g fill="none" stroke="red" '
          'style="fill: black; FILL-RULE: evenodd; opacity:0.5">'
          '<path fill="none" style="fill:blue;stroke:none" d="M0 0h8v8z"/>'
          '</g>');
      final attrs = nodes(icon).single.attrs;
      expect(attrs['fill'], 'currentColor');
      expect(attrs['stroke'], 'none');
      expect(attrs['fill-rule'], 'evenodd');
      expect(attrs['opacity'], '0.5');
    });

    test('mixed filled and stroked elements retain distinct surface paint', () {
      final icon = nodes(svgToIcon('<g stroke="red" stroke-width="2">'
          '<path fill="red" d="M0 0h4v4z"/>'
          '<path fill="none" d="M0 8h4"/></g>'));
      expect(icon.map((node) => node.attrs['fill']), ['currentColor', 'none']);
      expect(icon.map((node) => node.attrs['stroke']),
          ['currentColor', 'currentColor']);
      expect(icon.every((node) => node.tag == 'path'), isTrue);
    });

    test('bare stroke paint suppresses implicit fill', () {
      final icon = nodes(svgToIcon('<g stroke="currentColor">'
          '<circle cx="12" cy="12" r="8"/></g>'));
      expect(icon.single.tag, 'circle');
    });

    test('filled primitives become paths and fitting scales stroke width', () {
      final icon = nodes(svgToIcon('<svg viewBox="0 0 48 48" fill="red" '
          'stroke="blue" stroke-width="4px">'
          '<rect x="4" y="4" width="40" height="40"/></svg>'));
      expect(icon.single.tag, 'path');
      expect(icon.single.attrs['stroke-width'], '2');
      expectGeometry(icon, 'M2 2h20v20H2z');
    });
  });

  group('transform baking', () {
    test('translate bakes coordinates and removes transform', () {
      final icon = nodes(svgToIcon('<path stroke="currentColor" '
          'transform="translate(2 2)" d="M0 0h4"/>'));
      expect(icon.single.tag, 'path');
      expect(icon.single.attrs, isNot(contains('transform')));
      expect(canon(icon), canon('M2 2h4'));
    });

    test('nested group matrices compose with element matrices', () {
      expect(
        canon(svgToIcon('<g transform="translate(10 0)">'
            '<path stroke="currentColor" transform="scale(2)" d="M0 0h4"/></g>')),
        canon('M10 0h8'),
      );
    });

    test('transform lists compose in SVG order', () {
      expect(
        canon(svgToIcon('<line fill="none" x2="4" '
            'transform="translate(10,2) scale(2,3)"/>')),
        canon('M10 2h8'),
      );
    });

    test('matrix applies to every cubic control point', () {
      expect(
        canon(svgToIcon('<path fill="none" d="M0 0C1 2 3 4 5 6" '
            'transform="matrix(2 1 3 4 5 6)"/>')),
        canon('M5 6C13 15 23 25 33 35'),
      );
    });

    test('rotation supports origin and explicit centers', () {
      expect(
        canon(svgToIcon('<path fill="none" d="M0 0h4" '
            'transform="rotate(90)"/>')),
        canon('M0 0v4'),
      );
      expect(
        canon(svgToIcon('<path fill="none" d="M1 1h4" '
            'transform="rotate(90 1 1)"/>')),
        canon('M1 1v4'),
      );
    });

    test('skew matrices apply to both axes', () {
      expect(
        canon(svgToIcon('<path fill="none" d="M0 2h4" '
            'transform="skewX(45)"/>')),
        canon('M2 2h4'),
      );
      expect(
        canon(svgToIcon('<path fill="none" d="M2 0v4" '
            'transform="skewY(45)"/>')),
        canon('M2 2v4'),
      );
    });

    test('filled transformed primitives keep metadata and closing flags', () {
      final icon = svgToIcon('<g fill="red" transform="translate(2 3)">'
          '<rect width="4" height="5"/></g>');
      expect(nodes(icon).single.attrs['fill'], 'currentColor');
      expect(canon(icon), canon('M2 3h4v5H2z'));
    });

    test('transform precedes viewBox fitting', () {
      expectGeometry(
        svgToIcon('<svg viewBox="0 0 48 48">'
            '<path fill="none" transform="translate(4 8)" d="M0 0h8"/></svg>'),
        'M2 4h4',
      );
    });

    test('unknown or non-finite transforms have explicit errors', () {
      expect(
        () => svgToIcon('<path fill="none" transform="warp(2)" d="M0 0h4"/>'),
        failsWith('unsupported transform "warp"'),
      );
      expect(
        () => svgToIcon('<path fill="none" transform="matrix(1 0 0 1 NaN 0)" '
            'd="M0 0h4"/>'),
        failsWith('invalid transform'),
      );
    });
  });

  group('non-rendered content and unsupported markup', () {
    test('non-rendered container descendants are not hoisted', () {
      for (final tag in ['defs', 'mask', 'clipPath', 'symbol']) {
        expect(
          canon(svgToIcon('<svg stroke="currentColor" fill="none">'
              '<$tag><path d="M0 0h99"/></$tag>$menu</svg>')),
          canon(svgToIcon(menu)),
        );
      }
    });

    test('self-closed containers and title/description are skipped', () {
      expect(
        canon(svgToIcon('<defs/><mask/><clipPath/><symbol/>'
            '<title>Menu</title><desc>Three lines</desc>$menu')),
        canon(svgToIcon(menu)),
      );
    });

    test('commented-out markup is not geometry', () {
      expect(canon(svgToIcon('<!-- <path d="M0 0h99"/> -->$menu')),
          canon(svgToIcon(menu)));
    });

    test('comments are removed to a fixpoint and open comments run to EOF', () {
      expect(
        canon(svgToIcon('<!<!---->-- <path d="M0 0h99"/> -->$menu')),
        canon(svgToIcon(menu)),
      );
      expect(canon(svgToIcon('$menu<!-- <path d="M0 0h99"/>')),
          canon(svgToIcon(menu)));
    });

    test('display none stays hidden through descendant overrides', () {
      expect(
        canon(svgToIcon('<svg fill="none" stroke="currentColor">'
            '<path display="none" d="M0 0h99"/>'
            '<g display="none"><path display="inline" d="M0 0h98"/></g>'
            '<g style="display:none"><g style="display:inline">'
            '<path d="M0 0h97"/></g></g>$menu</svg>')),
        canon(svgToIcon(menu)),
      );
    });

    test('hidden and collapsed visibility inherit but may be overridden', () {
      expect(
        canon(svgToIcon('<g fill="none" visibility="hidden">'
            '<path d="M0 0h99"/><path style="visibility:collapse" d="M0 0h98"/>'
            '<path visibility="visible" d="M0 0h4"/></g>')),
        canon('M0 0h4'),
      );
    });

    test('unsupported visible elements throw', () {
      for (final tag in ['text', 'use', 'image', 'foreignObject']) {
        expect(() => svgToIcon('<$tag/>$menu'),
            failsWith('unsupported SVG element <${tag.toLowerCase()}>'));
      }
    });

    test('style elements throw even inside defs', () {
      expect(
        () => svgToIcon('<svg><defs><style>.a{fill:none}</style></defs>'
            '<path class="a" d="M0 0h4"/></svg>'),
        failsWith('unsupported SVG element <style>'),
      );
      expect(canon(svgToIcon('<!-- <style>ignored</style> -->$menu')),
          canon(svgToIcon(menu)));
    });

    test('empty markup wrappers or entirely hidden geometry throw', () {
      for (final markup in [
        '<g stroke="currentColor"></g>',
        '<defs><path d="M0 0h4"/></defs>',
        '<path display="none" d="M0 0h4"/>',
        '<!-- <path d="M0 0h4"/> -->',
      ]) {
        expect(() => svgToIcon(markup), failsWith('no morphable geometry'));
      }
    });
  });
}
